import Combine
import Foundation

enum OpenClawInstallationError: LocalizedError {
    case installFailed(String)
    case onboardingFailed(String)
    case verificationFailed
    case bundleNotFound

    var errorDescription: String? {
        switch self {
        case .installFailed(let message):
            return "Failed to install OpenClaw: \(message)"
        case .onboardingFailed(let message):
            return "Failed to configure OpenClaw: \(message)"
        case .verificationFailed:
            return "OpenClaw installation could not be verified"
        case .bundleNotFound:
            return "Bundled OpenClaw package not found in app resources"
        }
    }
}

@MainActor
class OpenClawInstaller: ObservableObject {
    @Published var installationProgress: Double = 0.0
    @Published var installationStatus: String = ""
    @Published var installationLog: String = ""
    @Published var isInstalling = false
    @Published var error: OpenClawInstallationError?

    private let commandExecutor: CommandExecutor
    private(set) var verifiedOpenclawPath: String?

    /// Installation target directory (under user home, no sudo needed)
    private var installDir: String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(homeDir)/.npm-global"
    }

    init(commandExecutor: CommandExecutor) {
        self.commandExecutor = commandExecutor
    }

    /// Get path to bundled openclaw tar.gz in app resources
    private func getBundledOpenclawPath() -> URL? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        let bundledPath = URL(fileURLWithPath: resourcePath)
            .appendingPathComponent("openclaw-bundle.tar.gz")
        return FileManager.default.fileExists(atPath: bundledPath.path) ? bundledPath : nil
    }

    /// Install OpenClaw from bundled package
    func installOpenClaw() async throws {
        isInstalling = true
        error = nil
        installationLog = ""
        installationProgress = 0.0

        do {
            // Find bundled openclaw package
            guard let bundlePath = getBundledOpenclawPath() else {
                throw OpenClawInstallationError.bundleNotFound
            }

            installationStatus = "Installing OpenClaw from bundled package..."
            appendLog("Found bundled OpenClaw package: \(bundlePath.lastPathComponent)")
            installationProgress = 0.1

            // Create install directory
            let targetDir = installDir
            appendLog("Install directory: \(targetDir)")

            let fm = FileManager.default
            if !fm.fileExists(atPath: targetDir) {
                try fm.createDirectory(atPath: targetDir, withIntermediateDirectories: true)
                appendLog("Created directory: \(targetDir)")
            }

            installationStatus = "Extracting OpenClaw..."
            installationProgress = 0.2

            // Remove quarantine from the bundle tar.gz itself before extraction,
            // so extracted files won't inherit the attribute
            let _ = try? await commandExecutor.execute(
                "/usr/bin/xattr",
                args: ["-d", "com.apple.quarantine", bundlePath.path],
                withSudo: false
            )

            // Start a progress timer to show activity during extraction
            let progressTask = Task { @MainActor in
                var progress = 0.2
                while progress < 0.75 {
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                    progress += 0.05
                    self.installationProgress = progress
                    self.installationStatus = "Extracting OpenClaw... \(Int(progress * 100))%"
                }
            }

            // Extract bundled openclaw to install directory (no sudo needed)
            let extractCmd = """
            tar -xzf '\(bundlePath.path)' -C '\(targetDir)' 2>&1
            """
            appendLog("Executing: tar -xzf ... -C \(targetDir)")

            let output = try await commandExecutor.execute(
                "/bin/bash",
                args: ["-c", extractCmd],
                withSudo: false
            ) { output in
                self.appendLog(output)
            }

            progressTask.cancel()

            if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendLog(output)
            }
            appendLog("Extraction complete.")

            // Remove macOS quarantine attributes to prevent Gatekeeper from
            // blocking unsigned native modules (e.g. clipboard.darwin-universal.node)
            installationStatus = "Removing quarantine attributes..."
            installationProgress = 0.75
            appendLog("Removing quarantine attributes from extracted files...")
            let xattrCmd = "xattr -cr '\(targetDir)/lib/node_modules/openclaw' 2>&1"
            let _ = try? await commandExecutor.execute(
                "/bin/bash",
                args: ["-c", xattrCmd],
                withSudo: false
            )
            appendLog("Quarantine attributes removed.")

            installationStatus = "Setting up OpenClaw binary..."
            installationProgress = 0.8

            // Ensure the openclaw.mjs has execute permission
            let openclawMjs = "\(targetDir)/lib/node_modules/openclaw/openclaw.mjs"
            if fm.fileExists(atPath: openclawMjs) {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: openclawMjs)
                appendLog("Set execute permission on openclaw.mjs")
            }

            // Ensure the bin directory exists and symlink is correct
            let binDir = "\(targetDir)/bin"
            if !fm.fileExists(atPath: binDir) {
                try fm.createDirectory(atPath: binDir, withIntermediateDirectories: true)
            }

            // Recreate the symlink (tar may have preserved it, but let's ensure)
            let binLink = "\(binDir)/openclaw"
            try? fm.removeItem(atPath: binLink)
            try fm.createSymbolicLink(
                atPath: binLink,
                withDestinationPath: "../lib/node_modules/openclaw/openclaw.mjs"
            )
            appendLog("Created bin symlink: \(binLink)")

            // Verify installation (also sets verifiedOpenclawPath)
            try await verifyInstallation()

            // Ensure the bin directory is in user's shell PATH
            await ensureBinInPath()

            installationProgress = 1.0
            isInstalling = false
            installationStatus = "Installation complete!"

        } catch let err as OpenClawInstallationError {
            self.error = err
            installationStatus = err.localizedDescription
            appendLog("\n❌ Error: \(err.localizedDescription)")
            isInstalling = false
            throw err
        } catch {
            let err = OpenClawInstallationError.installFailed(error.localizedDescription)
            self.error = err
            installationStatus = err.localizedDescription
            appendLog("\n❌ Error: \(error.localizedDescription)")
            isInstalling = false
            throw err
        }
    }

    /// Run openclaw onboard
    func runOnboarding(apiKey: String? = nil) async throws {
        isInstalling = true
        installationStatus = "Configuring OpenClaw..."
        appendLog("\nRunning openclaw onboard...")

        do {
            // Get openclaw path
            var openclawPath = verifiedOpenclawPath
            if openclawPath == nil {
                openclawPath = await commandExecutor.getCommandPath("openclaw")
            }
            guard let openclawPath = openclawPath else {
                throw OpenClawInstallationError.verificationFailed
            }

            // Build onboard command
            var args = ["onboard"]
            if let apiKey = apiKey, !apiKey.isEmpty {
                args.append(contentsOf: ["--api-key", apiKey])
            }

            appendLog("Executing: openclaw onboard")

            let output = try await commandExecutor.execute(
                openclawPath,
                args: args,
                withSudo: false
            ) { output in
                self.appendLog(output)
            }

            appendLog(output)
            installationStatus = "OpenClaw configured successfully"

            isInstalling = false

        } catch {
            let err = OpenClawInstallationError.onboardingFailed(error.localizedDescription)
            self.error = err
            installationStatus = err.localizedDescription
            appendLog("\n❌ Error: \(error.localizedDescription)")
            isInstalling = false
            throw err
        }
    }

    /// Verify OpenClaw installation
    func verifyInstallation() async throws {
        installationStatus = "Verifying installation..."
        appendLog("Verifying OpenClaw installation...")

        // Wait briefly for filesystem to settle
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Check known installation paths directly (most reliable)
        var openclawPath: String? = nil
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let candidatePaths = [
            "\(homeDir)/.npm-global/bin/openclaw",
            "/opt/homebrew/bin/openclaw",
            "/usr/local/bin/openclaw"
        ]
        for path in candidatePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                openclawPath = path
                appendLog("Found openclaw at: \(path)")
                break
            }
        }

        // Fallback: try `which openclaw` via login shell
        if openclawPath == nil {
            openclawPath = await commandExecutor.getCommandPath("openclaw")
        }

        guard let verifiedPath = openclawPath else {
            appendLog("Could not find openclaw command in PATH or common locations")
            throw OpenClawInstallationError.verificationFailed
        }

        // Save for later use (e.g. PATH configuration)
        verifiedOpenclawPath = verifiedPath
        appendLog("openclaw found at: \(verifiedPath)")

        // Get version using the full path directly
        let versionResult = try? await commandExecutor.execute(
            "/bin/bash",
            args: ["-l", "-c", "'\(verifiedPath)' --version 2>&1"],
            withSudo: false
        )

        if let versionOutput = versionResult {
            // Extract version from possibly multi-line output
            let lines = versionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines)
            let versionStr = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            installationStatus = "OpenClaw \(versionStr) verified at \(verifiedPath)"
            appendLog("✓ OpenClaw \(versionStr) installed at \(verifiedPath)")
        } else {
            // Command exists but version check failed - still consider it installed
            installationStatus = "OpenClaw installed at \(verifiedPath)"
            appendLog("✓ OpenClaw installed at \(verifiedPath) (version check skipped)")
        }
    }

    /// Ensure the openclaw bin directory is in the user's shell PATH
    private func ensureBinInPath() async {
        guard let openclawPath = verifiedOpenclawPath else {
            appendLog("No verified openclaw path, skipping PATH configuration")
            return
        }

        // Get the bin directory from the full path
        let binDir = (openclawPath as NSString).deletingLastPathComponent
        appendLog("openclaw bin directory: \(binDir)")

        // Skip if it's a standard system PATH location (already in PATH by default)
        let standardPaths = ["/usr/local/bin", "/usr/bin", "/opt/homebrew/bin"]
        if standardPaths.contains(binDir) {
            appendLog("bin directory \(binDir) is a standard PATH location, skipping")
            return
        }

        // Check if this bin dir is already in current PATH
        let pathCheckResult = try? await commandExecutor.execute(
            "/bin/bash", args: ["-l", "-c", "echo $PATH"], withSudo: false
        )
        let currentPath = pathCheckResult?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if currentPath.contains(binDir) {
            appendLog("bin directory already in PATH")
            return
        }

        // Add to .zshrc (macOS default shell)
        appendLog("Adding \(binDir) to PATH in ~/.zshrc...")
        let addPathCmd = """
            PROFILE_FILE="$HOME/.zshrc"
            [ -f "$HOME/.bash_profile" ] && [ ! -f "$HOME/.zshrc" ] && PROFILE_FILE="$HOME/.bash_profile"
            if ! grep -qF '\(binDir)' "$PROFILE_FILE" 2>/dev/null; then
                echo '' >> "$PROFILE_FILE"
                echo '# npm global bin path (added by OpenClaw Installer)' >> "$PROFILE_FILE"
                echo 'export PATH="\(binDir):$PATH"' >> "$PROFILE_FILE"
            fi
            """
        let _ = try? await commandExecutor.execute(
            "/bin/bash", args: ["-c", addPathCmd], withSudo: false
        )
        appendLog("PATH configured in shell profile.")
    }

    /// Append to installation log
    private func appendLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        installationLog += "[\(timestamp)] \(message)\n"
    }

    /// Clear log
    func clearLog() {
        installationLog = ""
    }

    /// Reset state
    func reset() {
        installationProgress = 0.0
        installationStatus = ""
        installationLog = ""
        isInstalling = false
        error = nil
    }

    /// Complete installation process
    func completeInstallation(apiKey: String? = nil) async throws {
        // Install OpenClaw
        try await installOpenClaw()

        // Run onboarding if API key provided
        if let apiKey = apiKey, !apiKey.isEmpty {
            try await runOnboarding(apiKey: apiKey)
        }
    }
}
