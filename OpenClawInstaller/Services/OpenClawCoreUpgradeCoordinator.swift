import Combine
import Foundation

enum OpenClawCoreUpgradePhase: Equatable {
    case idle
    case checking
    case upToDate(String)
    case upgrading(String)
    case upgraded(String)
    case failed(String)
    case rolledBack(String)
}

enum OpenClawCoreUpgradeError: LocalizedError {
    case bundleNotFound(String)
    case stagedCoreVerificationFailed(expected: String, actual: String?)
    case installDirectoryMissing(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .bundleNotFound(let name):
            return "Bundled OpenClaw core package not found: \(name)"
        case .stagedCoreVerificationFailed(let expected, let actual):
            return "Staged OpenClaw core verification failed. Expected \(expected), got \(actual ?? "unknown")"
        case .installDirectoryMissing(let path):
            return "OpenClaw install directory is missing: \(path)"
        case .commandFailed(let message):
            return message
        }
    }
}

struct OpenClawCoreUpgradePlan: Equatable {
    let installedVersion: String?
    let targetVersion: String
    let bundleName: String

    var requiresUpgrade: Bool {
        OpenClawCoreManifest(
            version: 1,
            openclawVersion: targetVersion,
            bundleName: bundleName,
            minimumAppVersion: nil,
            releaseNotes: nil
        )
        .isBundledVersionNewer(than: installedVersion)
    }
}

private struct OpenClawCoreSwapBackup {
    let root: URL
    var coreDir: URL?
    var binLink: URL?
}

@MainActor
final class OpenClawCoreUpgradeCoordinator: ObservableObject {
    @Published var state: OpenClawCoreUpgradePhase = .idle
    @Published var progress: Double = 0
    @Published var log: String = ""
    @Published var lastPlan: OpenClawCoreUpgradePlan?

    private let commandExecutor: CommandExecutor
    private let openclawService: OpenClawService
    private let fileManager: FileManager
    private var isRunning = false

    private var homeDir: String {
        fileManager.homeDirectoryForCurrentUser.path
    }

    private var npmGlobalDir: URL {
        URL(fileURLWithPath: homeDir).appendingPathComponent(".npm-global")
    }

    private var npmGlobalNodeModulesDir: URL {
        npmGlobalDir.appendingPathComponent("lib/node_modules")
    }

    private var npmGlobalBinDir: URL {
        npmGlobalDir.appendingPathComponent("bin")
    }

    private var installedCoreDir: URL {
        npmGlobalNodeModulesDir.appendingPathComponent("openclaw")
    }

    private var installedBinLink: URL {
        npmGlobalBinDir.appendingPathComponent("openclaw")
    }

    private var stagingRoot: URL {
        URL(fileURLWithPath: homeDir).appendingPathComponent(".openclaw/core-upgrade-staging")
    }

    private var backupRoot: URL {
        URL(fileURLWithPath: homeDir).appendingPathComponent(".openclaw/core-upgrade-backups")
    }

    private var logFileURL: URL {
        URL(fileURLWithPath: homeDir).appendingPathComponent(".openclaw/core-upgrade.log")
    }

    private var shellPathPrefix: String {
        [
            "\(homeDir)/.openclaw/node/bin",
            "\(homeDir)/.npm-global/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ].joined(separator: ":")
    }

    init(
        commandExecutor: CommandExecutor,
        openclawService: OpenClawService,
        fileManager: FileManager = .default
    ) {
        self.commandExecutor = commandExecutor
        self.openclawService = openclawService
        self.fileManager = fileManager
    }

    func ensureBundledCoreIsCurrent() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        state = .checking
        progress = 0.05
        appendLog("Checking bundled OpenClaw core manifest")

        do {
            guard let manifest = try OpenClawCoreManifest.loadBundled() else {
                appendLog("No bundled OpenClaw core manifest found; skipping core upgrade")
                state = .idle
                progress = 0
                return
            }

            let installedVersion = await installedOpenClawVersion()
            let plan = OpenClawCoreUpgradePlan(
                installedVersion: installedVersion,
                targetVersion: manifest.openclawVersion,
                bundleName: manifest.bundleName
            )
            lastPlan = plan

            guard plan.requiresUpgrade else {
                let version = installedVersion ?? "unknown"
                appendLog("OpenClaw core \(version) is already current for bundled \(manifest.openclawVersion)")
                state = .upToDate(version)
                progress = 1
                return
            }

            state = .upgrading(manifest.openclawVersion)
            appendLog("Upgrading OpenClaw core from \(installedVersion ?? "none") to \(manifest.openclawVersion)")

            let bundleURL = try bundledCoreBundleURL(named: manifest.bundleName)
            try await stopGatewayIfRunning()
            progress = 0.15

            let stagedInstallDir = try await extractBundleToStaging(bundleURL: bundleURL)
            progress = 0.35

            try await verifyStagedCore(at: stagedInstallDir, expectedVersion: manifest.openclawVersion)
            progress = 0.5

            let backup = try swapStagedOpenClawIntoPlace(stagedInstallDir)
            progress = 0.65

            do {
                try await installGateway()
                progress = 0.78
                await runPostUpgradeDoctor()
                progress = 0.86
                try await openclawService.start()
                await openclawService.fetchVersion()
                try removeBackupIfPossible(backup)
                state = .upgraded(manifest.openclawVersion)
                progress = 1
                appendLog("OpenClaw core upgraded to \(manifest.openclawVersion)")
            } catch {
                appendLog("Upgrade failed after swap: \(error.localizedDescription)")
                try await rollback(from: backup)
                state = .rolledBack(error.localizedDescription)
                throw error
            }
        } catch {
            appendLog("Core upgrade failed: \(error.localizedDescription)")
            if case .rolledBack = state {
                return
            }
            state = .failed(error.localizedDescription)
        }
    }

    private func bundledCoreBundleURL(named bundleName: String) throws -> URL {
        guard let resourcePath = Bundle.main.resourcePath else {
            throw OpenClawCoreUpgradeError.bundleNotFound(bundleName)
        }
        let url = URL(fileURLWithPath: resourcePath).appendingPathComponent(bundleName)
        guard fileManager.fileExists(atPath: url.path) else {
            throw OpenClawCoreUpgradeError.bundleNotFound(bundleName)
        }
        return url
    }

    private func installedOpenClawVersion() async -> String? {
        guard let raw = await commandExecutor.getCommandVersion("openclaw", versionArg: "--version")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return nil
        }
        return OpenClawVersionComparator.extractVersionString(raw)
    }

    private func stopGatewayIfRunning() async throws {
        appendLog("Stopping old OpenClaw gateway before core swap")
        do {
            try await openclawService.stop()
        } catch {
            appendLog("Gateway stop via service returned: \(error.localizedDescription)")
            let output = try? await runShell("openclaw gateway stop 2>&1", timeout: 20)
            appendLog("Fallback gateway stop output: \(output ?? "(no output)")")
        }
    }

    private func extractBundleToStaging(bundleURL: URL) async throws -> URL {
        appendLog("Extracting bundled core to staging")
        try prepareEmptyDirectory(stagingRoot)
        let stagedInstallDir = stagingRoot.appendingPathComponent("npm-global")
        try fileManager.createDirectory(at: stagedInstallDir, withIntermediateDirectories: true)

        _ = try? await commandExecutor.execute(
            "/usr/bin/xattr",
            args: ["-d", "com.apple.quarantine", bundleURL.path],
            withSudo: false
        )

        let command = "tar -xzf '\(bundleURL.path)' -C '\(stagedInstallDir.path)' 2>&1"
        let output = try await commandExecutor.execute(
            "/bin/bash",
            args: ["-c", command],
            withSudo: false
        )
        if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog(output)
        }

        let coreDir = stagedInstallDir.appendingPathComponent("lib/node_modules/openclaw")
        _ = try? await commandExecutor.execute(
            "/bin/bash",
            args: ["-c", "xattr -cr '\(coreDir.path)' 2>&1"],
            withSudo: false
        )

        let mjs = coreDir.appendingPathComponent("openclaw.mjs")
        if fileManager.fileExists(atPath: mjs.path) {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mjs.path)
        }

        let binDir = stagedInstallDir.appendingPathComponent("bin")
        if !fileManager.fileExists(atPath: binDir.path) {
            try fileManager.createDirectory(at: binDir, withIntermediateDirectories: true)
        }
        let binLink = binDir.appendingPathComponent("openclaw")
        try? fileManager.removeItem(at: binLink)
        try fileManager.createSymbolicLink(
            atPath: binLink.path,
            withDestinationPath: "../lib/node_modules/openclaw/openclaw.mjs"
        )

        return stagedInstallDir
    }

    private func verifyStagedCore(at stagedInstallDir: URL, expectedVersion: String) async throws {
        let openclawPath = stagedInstallDir.appendingPathComponent("bin/openclaw")
        guard fileManager.isExecutableFile(atPath: openclawPath.path) else {
            throw OpenClawCoreUpgradeError.stagedCoreVerificationFailed(expected: expectedVersion, actual: nil)
        }

        let output = try await commandExecutor.execute(
            "/bin/zsh",
            args: [
                "-l",
                "-c",
                "PATH='\(shellPathPrefix)'; export PATH; '\(openclawPath.path)' --version 2>&1"
            ],
            withSudo: false
        )
        let actual = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let actualVersion = actual.map(OpenClawVersionComparator.extractVersionString)
        guard let actualVersion,
              OpenClawVersionComparator.compare(actualVersion, expectedVersion) == .orderedSame else {
            throw OpenClawCoreUpgradeError.stagedCoreVerificationFailed(expected: expectedVersion, actual: actual)
        }
        appendLog("Verified staged OpenClaw core \(actualVersion)")
    }

    private func swapStagedOpenClawIntoPlace(_ stagedInstallDir: URL) throws -> OpenClawCoreSwapBackup {
        appendLog("Swapping staged OpenClaw core into \(installedCoreDir.path)")

        let stagedCoreDir = stagedInstallDir.appendingPathComponent("lib/node_modules/openclaw")
        let stagedBinLink = stagedInstallDir.appendingPathComponent("bin/openclaw")
        guard fileManager.fileExists(atPath: stagedCoreDir.path),
              itemExistsIncludingSymlink(at: stagedBinLink) else {
            throw OpenClawCoreUpgradeError.installDirectoryMissing(stagedInstallDir.path)
        }

        try fileManager.createDirectory(at: npmGlobalNodeModulesDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: npmGlobalBinDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let transactionBackupRoot = backupRoot.appendingPathComponent("openclaw-\(timestamp)")
        try fileManager.createDirectory(at: transactionBackupRoot, withIntermediateDirectories: true)

        let coreBackupURL = transactionBackupRoot.appendingPathComponent("openclaw")
        let binBackupURL = transactionBackupRoot.appendingPathComponent("openclaw-bin")
        var backup = OpenClawCoreSwapBackup(root: transactionBackupRoot, coreDir: nil, binLink: nil)

        if itemExistsIncludingSymlink(at: installedCoreDir) {
            try fileManager.moveItem(at: installedCoreDir, to: coreBackupURL)
            backup.coreDir = coreBackupURL
        }

        if itemExistsIncludingSymlink(at: installedBinLink) {
            try fileManager.moveItem(at: installedBinLink, to: binBackupURL)
            backup.binLink = binBackupURL
        }

        do {
            try fileManager.moveItem(at: stagedCoreDir, to: installedCoreDir)
            try fileManager.moveItem(at: stagedBinLink, to: installedBinLink)
            openclawService.resolvedOpenclawPath = nil
            return backup
        } catch {
            restoreOpenClawFiles(from: backup)
            throw error
        }
    }

    private func installGateway() async throws {
        appendLog("Reinstalling OpenClaw gateway with upgraded core")
        let nodePath = "\(homeDir)/.openclaw/node/bin/node"
        let openclawPath = installedBinLink.path
        let command: String
        if fileManager.isExecutableFile(atPath: nodePath) {
            command = "'\(nodePath)' '\(openclawPath)' gateway install 2>&1"
        } else {
            command = "'\(openclawPath)' gateway install 2>&1"
        }
        let output = try await runShell(command, timeout: 45)
        appendLog("Gateway install output: \(output.isEmpty ? "(no output)" : output)")
    }

    private func runPostUpgradeDoctor() async {
        appendLog("Running OpenClaw post-upgrade doctor")
        if let output = try? await runShell("openclaw doctor --post-upgrade --json 2>&1", timeout: 45),
           !output.lowercased().contains("unknown option"),
           !output.lowercased().contains("unknown command") {
            appendLog("Post-upgrade doctor output: \(output.isEmpty ? "(no output)" : output)")
            return
        }

        if let fallback = try? await runShell("openclaw doctor --fix 2>&1", timeout: 45) {
            appendLog("Doctor fallback output: \(fallback.isEmpty ? "(no output)" : fallback)")
        }
    }

    private func rollback(from backup: OpenClawCoreSwapBackup) async throws {
        appendLog("Rolling back OpenClaw core from backup")
        restoreOpenClawFiles(from: backup)
        openclawService.resolvedOpenclawPath = nil
        try? await installGateway()
        try? await openclawService.start()
    }

    private func restoreOpenClawFiles(from backup: OpenClawCoreSwapBackup) {
        try? removeItemIncludingSymlink(at: installedCoreDir)
        try? removeItemIncludingSymlink(at: installedBinLink)

        if let coreDir = backup.coreDir, itemExistsIncludingSymlink(at: coreDir) {
            try? fileManager.createDirectory(at: npmGlobalNodeModulesDir, withIntermediateDirectories: true)
            try? fileManager.moveItem(at: coreDir, to: installedCoreDir)
        }

        if let binLink = backup.binLink, itemExistsIncludingSymlink(at: binLink) {
            try? fileManager.createDirectory(at: npmGlobalBinDir, withIntermediateDirectories: true)
            try? fileManager.moveItem(at: binLink, to: installedBinLink)
        }
    }

    private func removeBackupIfPossible(_ backup: OpenClawCoreSwapBackup) throws {
        if itemExistsIncludingSymlink(at: backup.root) {
            try fileManager.removeItem(at: backup.root)
        }
    }

    private func prepareEmptyDirectory(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func runShell(_ command: String, timeout: TimeInterval) async throws -> String {
        let script = "PATH='\(shellPathPrefix):$PATH'; export PATH; \(command)"
        let output = try await commandExecutor.execute(
            "/bin/zsh",
            args: ["-l", "-c", script],
            withSudo: false
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func itemExistsIncludingSymlink(at url: URL) -> Bool {
        if fileManager.fileExists(atPath: url.path) {
            return true
        }
        return (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private func removeItemIncludingSymlink(at url: URL) throws {
        if itemExistsIncludingSymlink(at: url) {
            try fileManager.removeItem(at: url)
        }
    }

    private func appendLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(message)\n"
        log += line
        if let data = line.data(using: .utf8) {
            try? fileManager.createDirectory(
                at: logFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: logFileURL.path),
               let handle = try? FileHandle(forWritingTo: logFileURL) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }
}
