import Combine
import Foundation
import AppKit
import UniformTypeIdentifiers
import Network

struct DiagnosticResult {
    let category: String
    let checks: [DiagnosticCheck]

    var hasissues: Bool {
        checks.contains { $0.status != .passed }
    }

    var criticalIssues: [DiagnosticCheck] {
        checks.filter { $0.status == .failed }
    }
}

struct DiagnosticCheck: Identifiable {
    let id = UUID()
    let name: String
    let status: DiagnosticStatus
    let message: String
    let suggestion: String?

    enum DiagnosticStatus {
        case passed
        case warning
        case failed
        case info

        var icon: String {
            switch self {
            case .passed: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .failed: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: String {
            switch self {
            case .passed: return "green"
            case .warning: return "orange"
            case .failed: return "red"
            case .info: return "blue"
            }
        }
    }
}

@MainActor
class DiagnosticService: ObservableObject {
    @Published var isRunning = false
    @Published var results: [DiagnosticResult] = []
    @Published var progress: Double = 0.0

    private let commandExecutor: CommandExecutor
    private let systemEnvironment: SystemEnvironment
    private let openclawService: OpenClawService

    init(
        commandExecutor: CommandExecutor,
        systemEnvironment: SystemEnvironment,
        openclawService: OpenClawService
    ) {
        self.commandExecutor = commandExecutor
        self.systemEnvironment = systemEnvironment
        self.openclawService = openclawService
    }

    /// Run all diagnostic checks
    func runDiagnostics() async {
        isRunning = true
        results = []
        progress = 0.0

        let categories: [(String, () async -> DiagnosticResult)] = [
            ("System Requirements", checkSystemRequirements),
            ("Node.js Installation", checkNodeInstallation),
            ("OpenClaw Installation", checkOpenClawInstallation),
            ("Network Connectivity", checkNetworkConnectivity),
            ("Port Availability", checkPortAvailability),
            ("File Permissions", checkFilePermissions),
            ("Service Status", checkServiceStatus)
        ]

        let totalChecks = Double(categories.count)

        for (index, (_, check)) in categories.enumerated() {
            let result = await check()
            results.append(result)
            progress = Double(index + 1) / totalChecks
        }

        isRunning = false
    }

    // MARK: - Individual Diagnostic Checks

    private func checkSystemRequirements() async -> DiagnosticResult {
        var checks: [DiagnosticCheck] = []

        // Check macOS version
        let osVersion = systemEnvironment.osVersion
        let versionComponents = osVersion.split(separator: ".").compactMap { Int($0) }
        if let major = versionComponents.first, major >= 12 {
            checks.append(DiagnosticCheck(
                name: "macOS Version",
                status: .passed,
                message: "macOS \(osVersion) is supported",
                suggestion: nil
            ))
        } else {
            checks.append(DiagnosticCheck(
                name: "macOS Version",
                status: .failed,
                message: "macOS \(osVersion) - Minimum required: macOS 12.0",
                suggestion: "Upgrade your macOS to version 12.0 or later"
            ))
        }

        // Check disk space
        let diskSpace = systemEnvironment.availableDiskSpace
        if let spaceValue = Double(diskSpace.split(separator: " ").first ?? "0"), spaceValue >= 1.0 {
            checks.append(DiagnosticCheck(
                name: "Disk Space",
                status: .passed,
                message: "\(diskSpace) available",
                suggestion: nil
            ))
        } else {
            checks.append(DiagnosticCheck(
                name: "Disk Space",
                status: .warning,
                message: "Only \(diskSpace) available",
                suggestion: "Free up more disk space for optimal performance"
            ))
        }

        // Check architecture
        checks.append(DiagnosticCheck(
            name: "Architecture",
            status: .info,
            message: systemEnvironment.architecture,
            suggestion: nil
        ))

        return DiagnosticResult(category: "System Requirements", checks: checks)
    }

    private func checkNodeInstallation() async -> DiagnosticResult {
        var checks: [DiagnosticCheck] = []

        await systemEnvironment.detectNode()

        if let nodeInfo = systemEnvironment.nodeInfo {
            // Node is installed
            if nodeInfo.isCompatible {
                checks.append(DiagnosticCheck(
                    name: "Node.js Version",
                    status: .passed,
                    message: "\(nodeInfo.version) is installed",
                    suggestion: nil
                ))
            } else {
                checks.append(DiagnosticCheck(
                    name: "Node.js Version",
                    status: .warning,
                    message: "\(nodeInfo.version) - Upgrade recommended",
                    suggestion: "Upgrade to Node.js 18 or later for best compatibility"
                ))
            }

            checks.append(DiagnosticCheck(
                name: "Node.js Path",
                status: .info,
                message: nodeInfo.path,
                suggestion: nil
            ))

            // Check npm
            if let npmPath = await commandExecutor.getCommandPath("npm") {
                if let npmVersion = await commandExecutor.getCommandVersion("npm") {
                    checks.append(DiagnosticCheck(
                        name: "npm",
                        status: .passed,
                        message: "npm \(npmVersion) at \(npmPath)",
                        suggestion: nil
                    ))
                }
            }
        } else {
            checks.append(DiagnosticCheck(
                name: "Node.js Installation",
                status: .failed,
                message: "Node.js is not installed",
                suggestion: "Run the installation wizard to install Node.js"
            ))
        }

        return DiagnosticResult(category: "Node.js Installation", checks: checks)
    }

    private func checkOpenClawInstallation() async -> DiagnosticResult {
        var checks: [DiagnosticCheck] = []

        await systemEnvironment.detectOpenClaw()

        if let openclawInfo = systemEnvironment.openclawInfo {
            checks.append(DiagnosticCheck(
                name: "OpenClaw Version",
                status: .passed,
                message: openclawInfo.version,
                suggestion: nil
            ))

            checks.append(DiagnosticCheck(
                name: "OpenClaw Path",
                status: .info,
                message: openclawInfo.path,
                suggestion: nil
            ))

            // Check configuration
            if openclawInfo.isConfigured {
                checks.append(DiagnosticCheck(
                    name: "Configuration",
                    status: .passed,
                    message: "Configuration file found",
                    suggestion: nil
                ))
            } else {
                checks.append(DiagnosticCheck(
                    name: "Configuration",
                    status: .warning,
                    message: "Configuration file not found",
                    suggestion: "Run 'openclaw onboard' to create configuration"
                ))
            }
        } else {
            checks.append(DiagnosticCheck(
                name: "OpenClaw Installation",
                status: .failed,
                message: "OpenClaw is not installed",
                suggestion: "Run the installation wizard to install OpenClaw"
            ))
        }

        return DiagnosticResult(category: "OpenClaw Installation", checks: checks)
    }

    private func checkNetworkConnectivity() async -> DiagnosticResult {
        var checks: [DiagnosticCheck] = []

        // Check internet connectivity
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "NetworkMonitor")

        await withCheckedContinuation { continuation in
            monitor.pathUpdateHandler = { path in
                if path.status == .satisfied {
                    checks.append(DiagnosticCheck(
                        name: "Internet Connection",
                        status: .passed,
                        message: "Connected",
                        suggestion: nil
                    ))
                } else {
                    checks.append(DiagnosticCheck(
                        name: "Internet Connection",
                        status: .failed,
                        message: "Not connected",
                        suggestion: "Check your network connection"
                    ))
                }
                monitor.cancel()
                continuation.resume()
            }
            monitor.start(queue: queue)
        }

        // Check DNS resolution
        do {
            let url = URL(string: "https://www.google.com")!
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                checks.append(DiagnosticCheck(
                    name: "DNS Resolution",
                    status: .passed,
                    message: "Working correctly",
                    suggestion: nil
                ))
            }
        } catch {
            checks.append(DiagnosticCheck(
                name: "DNS Resolution",
                status: .warning,
                message: "Failed to resolve DNS",
                suggestion: "Check your DNS settings"
            ))
        }

        return DiagnosticResult(category: "Network Connectivity", checks: checks)
    }

    private func checkPortAvailability() async -> DiagnosticResult {
        var checks: [DiagnosticCheck] = []

        let port = 3928 // OpenClaw default port

        // Simple port check (not perfect but works for basic diagnostics)
        do {
            let result = try await commandExecutor.execute(
                "/usr/bin/lsof",
                args: ["-i", ":\(port)"]
            )

            if result.isEmpty {
                checks.append(DiagnosticCheck(
                    name: "Port \(port)",
                    status: .passed,
                    message: "Available",
                    suggestion: nil
                ))
            } else {
                checks.append(DiagnosticCheck(
                    name: "Port \(port)",
                    status: .warning,
                    message: "Already in use",
                    suggestion: "Change the port in settings or stop the conflicting service"
                ))
            }
        } catch {
            checks.append(DiagnosticCheck(
                name: "Port \(port)",
                status: .info,
                message: "Could not check port status",
                suggestion: nil
            ))
        }

        return DiagnosticResult(category: "Port Availability", checks: checks)
    }

    private func checkFilePermissions() async -> DiagnosticResult {
        var checks: [DiagnosticCheck] = []

        // Check write permissions in common directories
        let directories = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".openclaw"),
            URL(fileURLWithPath: "/usr/local/bin")
        ]

        for directory in directories {
            let isWritable = FileManager.default.isWritableFile(atPath: directory.path)

            checks.append(DiagnosticCheck(
                name: directory.lastPathComponent,
                status: isWritable ? .passed : .warning,
                message: isWritable ? "Writable" : "Not writable",
                suggestion: isWritable ? nil : "Check file permissions for this directory"
            ))
        }

        return DiagnosticResult(category: "File Permissions", checks: checks)
    }

    private func checkServiceStatus() async -> DiagnosticResult {
        var checks: [DiagnosticCheck] = []

        await openclawService.checkStatus()

        let status = openclawService.status

        checks.append(DiagnosticCheck(
            name: "Service Status",
            status: status == .running ? .passed : .info,
            message: status.rawValue,
            suggestion: status == .running ? nil : "Start the service from the Dashboard"
        ))

        if status == .running {
            checks.append(DiagnosticCheck(
                name: "Uptime",
                status: .info,
                message: formatUptime(openclawService.uptime),
                suggestion: nil
            ))
        }

        return DiagnosticResult(category: "Service Status", checks: checks)
    }

    // MARK: - Helper Methods

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }

    /// Generate diagnostic report as text
    func generateReport() -> String {
        var report = "=== OpenClaw Diagnostic Report ===\n"
        report += "Generated: \(Date())\n\n"

        for result in results {
            report += "\(result.category):\n"
            for check in result.checks {
                let statusSymbol = check.status == .passed ? "✓" :
                                 check.status == .failed ? "✗" :
                                 check.status == .warning ? "⚠" : "ℹ"
                report += "  \(statusSymbol) \(check.name): \(check.message)\n"

                if let suggestion = check.suggestion {
                    report += "    → \(suggestion)\n"
                }
            }
            report += "\n"
        }

        return report
    }

    /// Export report to file
    func exportReport() {
        let report = generateReport()

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.text]
        savePanel.nameFieldStringValue = "openclaw-diagnostic-\(Date().timeIntervalSince1970).txt"

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? report.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
