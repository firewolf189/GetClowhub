import Foundation
import Combine
import AppKit

enum ServiceStatus: String {
    case running = "Running"
    case stopped = "Stopped"
    case starting = "Starting"
    case stopping = "Stopping"
    case error = "Error"
    case unknown = "Unknown"

    var icon: String {
        switch self {
        case .running: return "checkmark.circle.fill"
        case .stopped: return "stop.circle.fill"
        case .starting: return "arrow.clockwise.circle.fill"
        case .stopping: return "arrow.clockwise.circle"
        case .error: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var color: String {
        switch self {
        case .running: return "green"
        case .stopped: return "gray"
        case .starting, .stopping: return "orange"
        case .error: return "red"
        case .unknown: return "gray"
        }
    }
}

enum ServiceError: LocalizedError {
    case commandFailed(String)
    case notInstalled
    case timeout

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return "Service command failed: \(message)"
        case .notInstalled:
            return "OpenClaw is not installed"
        case .timeout:
            return "Operation timed out"
        }
    }
}

@MainActor
class OpenClawService: ObservableObject {
    @Published var status: ServiceStatus = .unknown
    @Published var isMonitoring = false
    @Published var uptime: TimeInterval = 0
    @Published var version: String = ""
    @Published var port: Int = 18789
    @Published var dashboardURL: String = "http://127.0.0.1:18789"
    @Published var lastError: String?
    @Published var logs: [String] = []

    private let commandExecutor: CommandExecutor
    private var statusTimer: Timer?
    private var startTime: Date?
    var resolvedOpenclawPath: String?

    init(commandExecutor: CommandExecutor) {
        self.commandExecutor = commandExecutor
    }

    deinit {
        Task { @MainActor in
            stopMonitoring()
        }
    }

    // MARK: - Service Control

    /// Start OpenClaw service
    /// Uses `gateway install` which safely installs + starts the LaunchAgent.
    /// If already running, it does nothing (safe to call anytime).
    func start() async throws {
        status = .starting
        addLog("Starting OpenClaw service...")

        guard let _ = await openclawCmd("--version") else {
            status = .error
            let msg = "openclaw command not found at any known location"
            lastError = msg
            addLog("Failed: \(msg)")
            throw ServiceError.notInstalled
        }

        // Ensure gateway.mode is set (required by openclaw)
        if let configCmd = await openclawCmd("config set gateway.mode local 2>&1") {
            let configOutput = await runShellQuietly(configCmd)
            addLog("Config gateway.mode=local: \(configOutput ?? "ok")")
        }

        guard let cmd = await openclawCmd("gateway install 2>&1") else {
            throw ServiceError.notInstalled
        }

        addLog("Running: \(cmd)")
        let output = await runShellQuietly(cmd, timeout: 30)
        addLog("Start output: \(output ?? "(no output)")")

        // Wait and retry status check - service may need time to start
        for attempt in 1...3 {
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            await checkStatus()
            if status == .running {
                addLog("OpenClaw service started successfully")
                startTime = Date()
                return
            }
            addLog("Status check attempt \(attempt): \(status.rawValue)")
        }

        status = .error
        let msg = "Service did not start. Output: \(output ?? "none")"
        lastError = msg
        addLog("Failed to start: \(msg)")
        throw ServiceError.commandFailed(msg)
    }

    /// Stop OpenClaw service
    func stop() async throws {
        status = .stopping
        addLog("Stopping OpenClaw service...")

        let cmd = await openclawCmd("gateway stop 2>&1") ?? "openclaw gateway stop 2>&1"
        let output = await runShellQuietly(cmd)
        addLog("Stop output: \(output ?? "(no output)")")

        // Wait for service to stop
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Verify stopped
        await checkStatus()

        if status == .stopped {
            addLog("OpenClaw service stopped")
            startTime = nil
            uptime = 0
        }
    }

    /// Restart OpenClaw service
    func restart() async throws {
        status = .starting
        addLog("Restarting OpenClaw service...")

        let cmd = await openclawCmd("gateway restart 2>&1") ?? "openclaw gateway restart 2>&1"
        let output = await runShellQuietly(cmd)
        addLog("Restart output: \(output ?? "(no output)")")

        // Wait for service to restart
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        await checkStatus()

        if status == .running {
            addLog("OpenClaw service restarted successfully")
            startTime = Date()
        } else {
            status = .error
            let msg = "Service did not restart"
            lastError = msg
            addLog("Failed to restart: \(msg)")
            throw ServiceError.commandFailed(msg)
        }
    }

    // MARK: - Status Monitoring

    /// Start monitoring service status
    func startMonitoring(interval: TimeInterval = 5.0) {
        guard !isMonitoring else { return }

        isMonitoring = true
        addLog("Started monitoring service status")

        // Initial check
        Task {
            await checkStatus()
        }

        // Set up timer for periodic checks
        statusTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkStatus()
            }
        }
    }

    /// Stop monitoring service status
    func stopMonitoring() {
        statusTimer?.invalidate()
        statusTimer = nil
        isMonitoring = false
        addLog("Stopped monitoring service status")
    }

    /// Check current service status
    /// Uses fast launchctl + lsof check first, then parses openclaw gateway status for details
    func checkStatus() async {
        // Step 1: Fast check via launchctl (instant, no network probes)
        let launchctlOutput = await runShellQuietly(
            "launchctl list ai.openclaw.gateway 2>&1",
            timeout: 5
        )

        if let output = launchctlOutput {
            let outputLower = output.lowercased()
            // launchctl list returns info if loaded; "could not find service" if not
            if outputLower.contains("could not find service") || outputLower.contains("no such") {
                // Service not loaded - check port as fallback
                await detectByPort()
            } else {
                // Service is loaded in launchctl, check if PID exists (running)
                // launchctl list output has "PID" = xxx; or PID = 0 if not running
                let lines = output.components(separatedBy: .newlines)
                var pidFound = false
                for line in lines {
                    // Format: "PID" = 30626; or tab-separated: pid\tstatus\tlabel
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.contains("\"PID\"") {
                        // Property list format: "PID" = 30626;
                        if let range = trimmed.range(of: "\\d+", options: .regularExpression) {
                            let pidStr = String(trimmed[range])
                            if let pid = Int(pidStr), pid > 0 {
                                status = .running
                                if startTime == nil { startTime = Date() }
                                if let startTime = startTime {
                                    uptime = Date().timeIntervalSince(startTime)
                                }
                                pidFound = true
                            }
                        }
                    }
                }

                if !pidFound {
                    // Loaded but maybe not running; double check with port
                    await detectByPort()
                }
            }
        } else {
            // launchctl failed, try port check
            await detectByPort()
        }

        // Step 2: Get details (dashboard URL, port) from gateway status in background
        // Only do this occasionally, not every 5 seconds
        if dashboardURL == "http://127.0.0.1:18789" {
            if let statusCmd = await openclawCmd("gateway status 2>&1") {
                let gatewayOutput = await runShellQuietly(
                    statusCmd,
                    timeout: 10
                )
                if let output = gatewayOutput {
                    parseGatewayDetails(output)
                }
            }
        }

        lastError = nil
    }

    /// Parse dashboard URL and port from gateway status output
    private func parseGatewayDetails(_ output: String) {
        for line in output.components(separatedBy: .newlines) {
            let lineLower = line.lowercased()

            if lineLower.hasPrefix("dashboard:") {
                if let range = line.range(of: "http[s]?://[^\\s]+", options: .regularExpression) {
                    let url = String(line[range]).trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                    dashboardURL = url
                    if let portRange = url.range(of: ":(\\d+)", options: .regularExpression) {
                        let portStr = url[portRange].dropFirst()
                        if let p = Int(portStr) {
                            port = p
                        }
                    }
                }
            }
        }
    }

    /// Detect service by checking if the gateway port is in use
    private func detectByPort() async {
        let lsofOutput = await runShellQuietly(
            "lsof -i :\(port) -sTCP:LISTEN 2>/dev/null | grep -c LISTEN",
            timeout: 5
        )
        let count = Int(lsofOutput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0") ?? 0
        if count > 0 {
            status = .running
            if startTime == nil { startTime = Date() }
        } else {
            status = .stopped
            uptime = 0
            startTime = nil
        }
    }

    /// Resolve the full path to the openclaw binary.
    /// Caches the result for subsequent calls.
    private func getOpenclawPath() async -> String? {
        if let cached = resolvedOpenclawPath {
            return cached
        }

        // 1. Try `which openclaw` via login shell
        //    zsh built-in `which` prints "openclaw not found" to stdout on failure,
        //    so we must verify the result is an actual executable path.
        if let path = await runShellQuietly("which openclaw 2>/dev/null"),
           !path.isEmpty,
           path.hasPrefix("/"),
           FileManager.default.isExecutableFile(atPath: path) {
            resolvedOpenclawPath = path
            return path
        }

        // 2. Check common locations directly
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = [
            "\(homeDir)/.npm-global/bin/openclaw",
            "/opt/homebrew/bin/openclaw",
            "/usr/local/bin/openclaw",
            "\(homeDir)/.volta/bin/openclaw",
            "\(homeDir)/Library/pnpm/openclaw",
            "\(homeDir)/.nvs/default/bin/openclaw",
            "\(homeDir)/tools/nvs/default/bin/openclaw",
        ]
        // nvm: scan ~/.nvm/versions/node/*/bin, pick latest version
        if let nvmBin = CommandExecutor.findLatestNvmBin(homeDir: homeDir, command: "openclaw") {
            candidates.insert(nvmBin, at: 0)
        }
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                resolvedOpenclawPath = candidate
                return candidate
            }
        }

        return nil
    }

    /// Build a shell command using the resolved openclaw path
    private func openclawCmd(_ subcommand: String) async -> String? {
        guard let path = await getOpenclawPath() else { return nil }
        return "'\(path)' \(subcommand)"
    }

    /// Run a shell command quietly without triggering UI updates
    /// Uses proper pipe reading pattern to avoid deadlocks, with timeout
    private func runShellQuietly(_ command: String, timeout: TimeInterval = 15) async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-l", "-c", command]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                // Read data FIRST (in background), then wait for exit
                // This avoids pipe buffer deadlock
                var outputData = Data()
                let readQueue = DispatchQueue(label: "pipe.read")
                let readGroup = DispatchGroup()
                readGroup.enter()
                readQueue.async {
                    outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                    readGroup.leave()
                }

                // Wait for process with timeout
                let deadline = Date().addingTimeInterval(timeout)
                var timedOut = false
                while process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                if process.isRunning {
                    process.terminate()
                    timedOut = true
                }

                // Wait for pipe read to complete
                readGroup.wait()

                if timedOut {
                    continuation.resume(returning: nil)
                } else {
                    let output = String(data: outputData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: output)
                }
            }
        }
    }

    /// Get detailed service info
    func getServiceInfo() async -> [String: String] {
        var info: [String: String] = [:]

        info["Status"] = status.rawValue
        info["Port"] = String(port)
        info["Version"] = version.isEmpty ? "Unknown" : version

        if status == .running {
            let uptimeStr = formatUptime(uptime)
            info["Uptime"] = uptimeStr
        }

        if let error = lastError {
            info["Last Error"] = error
        }

        return info
    }

    // MARK: - Dashboard Operations

    /// Open OpenClaw dashboard in browser, with auth token appended as query parameter
    func openDashboard(authToken: String? = nil) {
        var urlString = dashboardURL
        if let token = authToken, !token.isEmpty {
            let separator = urlString.contains("?") ? "&" : "?"
            urlString += "\(separator)token=\(token)"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            addLog("Opened dashboard at \(dashboardURL)")
        }
    }

    /// Open OpenClaw logs in system text editor
    func openLogs() {
        let logPath = NSString("~/.openclaw/logs/gateway.log").expandingTildeInPath
        if FileManager.default.fileExists(atPath: logPath) {
            let url = URL(fileURLWithPath: logPath)
            NSWorkspace.shared.open(url)
            addLog("Opened log file at \(logPath)")
        } else {
            addLog("Log file not found at \(logPath)")
        }
    }

    /// Read latest lines from gateway log file
    func readGatewayLogs(lines: Int = 200) async -> [String] {
        let logPath = NSString("~/.openclaw/logs/gateway.log").expandingTildeInPath
        guard FileManager.default.fileExists(atPath: logPath) else {
            return ["Log file not found: \(logPath)"]
        }

        let output = await runShellQuietly("tail -n \(lines) '\(logPath)'", timeout: 5)
        if let output = output, !output.isEmpty {
            return output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        } else {
            return ["Failed to read logs"]
        }
    }

    // MARK: - Version Info

    /// Get OpenClaw version
    func fetchVersion() async {
        if let cmd = await openclawCmd("--version 2>/dev/null"),
           let output = await runShellQuietly(cmd) {
            let ver = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ver.isEmpty {
                version = ver
            }
        }
    }

    // MARK: - Diagnostics

    /// Run `openclaw doctor` and return the output
    func runDoctor() async -> String {
        addLog("Running openclaw doctor...")
        guard let cmd = await openclawCmd("doctor --fix 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'") else {
            return "openclaw command not found"
        }
        // Strip ANSI color codes for clean display
        let output = await runShellQuietly(
            cmd,
            timeout: 30
        )
        return output ?? "Failed to run openclaw doctor"
    }

    // MARK: - Logs Management

    /// Add log entry
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logEntry = "[\(timestamp)] \(message)"
        logs.append(logEntry)

        // Keep only last 100 logs
        if logs.count > 100 {
            logs.removeFirst(logs.count - 100)
        }
    }

    /// Clear logs
    func clearLogs() {
        logs.removeAll()
        addLog("Logs cleared")
    }

    /// Get logs as string
    func getLogsString() -> String {
        return logs.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Format uptime duration
    private func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, secs)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }

    /// Check if service is healthy
    func isHealthy() -> Bool {
        return status == .running && lastError == nil
    }

    /// Run an arbitrary shell command and return the output.
    /// Automatically resolves "openclaw" to the full binary path.
    func runCommand(_ command: String, timeout: TimeInterval = 30) async -> String? {
        var resolved = command
        if resolved.hasPrefix("openclaw ") || resolved.contains(" openclaw ") {
            if let fullPath = await getOpenclawPath() {
                // Replace first occurrence of bare "openclaw" with the resolved path (quoted)
                if let range = resolved.range(of: "openclaw") {
                    resolved.replaceSubrange(range, with: "'\(fullPath)'")
                }
            }
        }
        return await runShellQuietly(resolved, timeout: timeout)
    }
}
