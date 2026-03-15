import Foundation

enum UninstallManager {

    /// Perform a full uninstall of OpenClaw components.
    /// Preserves: ~/.openclaw/openclaw.json, ~/.openclaw/config.json, ~/.openclaw/extensions/, Keychain tokens.
    @MainActor
    static func uninstall() async {
        // 1. Stop and remove gateway LaunchAgent
        await stopGateway()

        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        // 2. Use npm to formally uninstall openclaw before deleting directories
        await npmUninstall(home: home)

        // 3. Remove directories and files

        // Remove ~/.npm-global/ (OpenClaw program)
        removeIfExists("\(home)/.npm-global")

        // Remove ~/.openclaw/node/ (dedicated Node.js)
        removeIfExists("\(home)/.openclaw/node")

        // Remove ~/.openclaw/logs/
        removeIfExists("\(home)/.openclaw/logs")

        // Remove ~/.openclaw/providers_preset.json
        removeIfExists("\(home)/.openclaw/providers_preset.json")

        // Remove LaunchAgent plist
        removeIfExists("\(home)/Library/LaunchAgents/ai.openclaw.gateway.plist")

        // 4. Revert shell profile PATH changes
        revertShellProfile()
    }

    // MARK: - Stop Gateway

    private static func stopGateway() async {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let plistPath = "\(home)/Library/LaunchAgents/ai.openclaw.gateway.plist"

        if FileManager.default.fileExists(atPath: plistPath) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["unload", plistPath]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }

    // MARK: - npm Uninstall

    private static func npmUninstall(home: String) async {
        let npmPath = "\(home)/.openclaw/node/bin/npm"
        guard FileManager.default.fileExists(atPath: npmPath) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: npmPath)
        process.arguments = ["rm", "-g", "openclaw"]
        // Set PREFIX so npm knows where globals live
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(home)/.openclaw/node/bin:\(env["PATH"] ?? "/usr/bin")"
        env["npm_config_prefix"] = "\(home)/.npm-global"
        process.environment = env
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - File Removal

    private static func removeIfExists(_ path: String) {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            try? fm.removeItem(atPath: path)
        }
    }

    // MARK: - Revert Shell Profile

    private static func revertShellProfile() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        // Determine which profile file to edit
        let zshrc = "\(home)/.zshrc"
        let bashProfile = "\(home)/.bash_profile"
        let profilePath: String

        if fm.fileExists(atPath: zshrc) {
            profilePath = zshrc
        } else if fm.fileExists(atPath: bashProfile) {
            profilePath = bashProfile
        } else {
            return
        }

        guard let content = try? String(contentsOfFile: profilePath, encoding: .utf8) else { return }

        let lines = content.components(separatedBy: "\n")
        var filtered: [String] = []
        var skipNext = false

        for line in lines {
            if skipNext {
                // Skip the export PATH line that follows the comment
                if line.contains(".openclaw/node/bin") || line.contains(".npm-global/bin") {
                    skipNext = false
                    continue
                }
                // Not the expected line, keep it and reset
                skipNext = false
            }

            if line.contains("# OpenClaw node & npm global bin paths") ||
               line.contains("# added by OpenClaw Installer") {
                // Skip this comment line and flag to skip next export line
                skipNext = true
                continue
            }

            filtered.append(line)
        }

        // Remove trailing empty lines that were left by the removal
        while filtered.last == "" && filtered.count > 1 {
            filtered.removeLast()
        }

        let newContent = filtered.joined(separator: "\n")
        if newContent != content {
            try? newContent.write(toFile: profilePath, atomically: true, encoding: .utf8)
        }
    }
}
