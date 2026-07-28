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
            minimumNodeVersion: nil,
            releaseNotes: nil
        )
        .isBundledVersionNewer(than: installedVersion)
    }
}

private struct OpenClawCoreSwapBackup {
    let root: URL
    var coreDir: URL?
    var binLink: URL?
    /// Pre-upgrade config. The new core stamps `openclaw.json` with its own
    /// version, and the OLD binary then REFUSES to (re)install its service
    /// ("Refusing to install or rewrite the gateway service because this
    /// OpenClaw binary is older than the config last written by ..."). Rolling
    /// the core back without the config leaves the machine unable to repair
    /// itself — observed in the field on 2026-07-27.
    var configFile: URL?
}

/// Remembers a failed target so the next launch does not immediately retry.
///
/// Without this the upgrade re-ran on the very next trigger: on 2026-07-27 a
/// user's failed 6.10 -> 7.1-2 attempt rolled back at 16:36:38, a second
/// attempt started at 16:36:52, and it killed the gateway that had just
/// recovered. `isRunning` only prevents OVERLAP; the two startup entry points
/// (ContentView.onAppear and determineInitialView) still fire sequentially.
private struct OpenClawCoreUpgradeFailureMemory: Codable {
    var targetVersion: String
    var appVersion: String
    var failureCount: Int
    var lastFailure: Date

    /// A failed target is retried once the cooldown expires, and immediately if
    /// the app itself was updated (a new app version means a new attempt is
    /// worth making even if the previous one failed).
    func blocksRetry(target: String, appVersion currentAppVersion: String, now: Date, cooldown: TimeInterval) -> Bool {
        guard targetVersion == target, appVersion == currentAppVersion else { return false }
        return now.timeIntervalSince(lastFailure) < cooldown
    }
}

/// Written to disk BEFORE the core is swapped and removed once the attempt
/// resolves (success or rollback).
///
/// The rollback lives inside the running app, so anything that ends the process
/// between the swap and the readiness verdict — user quits the app during the
/// five-minute wait, crash, logout, shutdown — takes the recovery with it and
/// leaves the machine on the new core with a gateway that never came up.
/// Observed in the field on 2026-07-27: the app went away mid-wait and the box
/// sat half-upgraded until someone noticed. A file survives that; the next
/// launch reads it and finishes the job.
private struct OpenClawCoreUpgradeInflightMarker: Codable {
    var targetVersion: String
    var backupRoot: String
    var startedAt: Date
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
    /// At most ONE automatic attempt per app launch, even across the two
    /// startup entry points.
    private var didAttemptThisLaunch = false

    private static let failureMemoryKey = "openclawCoreUpgradeFailure"
    /// A day: long enough that a user hitting a broken plugin is not put
    /// through a five-minute gateway outage on every launch, short enough that
    /// a transient failure resolves itself by tomorrow.
    private static let failureCooldown: TimeInterval = 24 * 60 * 60
    private static let launchAgentLabel = "ai.openclaw.gateway"

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

    private var configFileURL: URL {
        URL(fileURLWithPath: homeDir).appendingPathComponent(".openclaw/openclaw.json")
    }

    private var inflightMarkerURL: URL {
        URL(fileURLWithPath: homeDir).appendingPathComponent(".openclaw/core-upgrade-inflight.json")
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

    /// `force` bypasses the per-launch guard and the failure cooldown — for a
    /// user-initiated repair, where the user is watching and has presumably
    /// fixed whatever blocked the last attempt.
    func ensureBundledCoreIsCurrent(force: Bool = false) async {
        // Decouple the upgrade from the CALLER's task: one entry point is a
        // view-bound `.task(id:)`, and mid-upgrade the gateway restart can
        // change view identity — SwiftUI then cancels that task, which used
        // to abort a half-done core swap with CancellationError (observed on
        // the 6.10 -> 7.1 upgrade). An unstructured Task does not inherit
        // cancellation, so the swap always runs to completion or rollback.
        let work = Task { await performUpgradeBody(force: force) }
        await work.value
    }

    private func performUpgradeBody(force: Bool) async {
        guard !isRunning else { return }
        if !force {
            guard !didAttemptThisLaunch else {
                appendLog("Skipping core upgrade: already attempted once this launch")
                return
            }
        }
        isRunning = true
        didAttemptThisLaunch = true
        defer { isRunning = false }

        state = .checking
        progress = 0.05
        // An attempt that never got to write its verdict must be finished here,
        // before anything else looks at versions.
        await recoverFromInterruptedUpgradeIfNeeded()
        appendLog("Checking bundled OpenClaw core manifest")

        do {
            guard let manifest = try OpenClawCoreManifest.loadBundled() else {
                appendLog("No bundled OpenClaw core manifest found; skipping core upgrade")
                state = .idle
                progress = 0
                return
            }

            let installedVersion = await installedOpenClawVersion()
            // Neither the manifest on disk nor the CLI could say what is
            // installed. Upgrading on that basis means swapping the core (and
            // dropping the gateway for minutes) without knowing whether there is
            // anything to gain — so leave the machine alone and say why.
            guard installedVersion != nil else {
                appendLog("Cannot determine the installed OpenClaw version; skipping the core upgrade rather than swapping blind")
                state = .idle
                progress = 0
                return
            }
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

            if !force, let memory = loadFailureMemory(),
               memory.blocksRetry(
                   target: manifest.openclawVersion,
                   appVersion: Self.currentAppVersion,
                   now: Date(),
                   cooldown: Self.failureCooldown
               ) {
                // Retrying a target that just failed costs the user another
                // five-minute gateway outage and, worse, tears down a gateway
                // that the previous rollback had just brought back.
                appendLog("Skipping core upgrade to \(manifest.openclawVersion): it failed \(memory.failureCount)x, last at \(memory.lastFailure). Use force repair to retry now.")
                state = .failed("Upgrade to \(manifest.openclawVersion) failed previously; not retrying yet")
                progress = 0
                return
            }

            state = .upgrading(manifest.openclawVersion)
            appendLog("Upgrading OpenClaw core from \(installedVersion ?? "none") to \(manifest.openclawVersion)")

            // Node floor FIRST: the new core's `engines` may reject the
            // currently installed Node (2026.7.x needs >= 24.15). Swapping the
            // core without upgrading Node bricks the gateway for existing
            // users — the exact failure the Windows client hit in v0.6.31.
            try await ensureNodeSatisfiesRequirement(manifest.minimumNodeVersion)

            let bundleURL = try bundledCoreBundleURL(named: manifest.bundleName)
            try await stopGatewayIfRunning()
            progress = 0.15

            let stagedInstallDir = try await extractBundleToStaging(bundleURL: bundleURL)
            progress = 0.35

            try await verifyStagedCore(at: stagedInstallDir, expectedVersion: manifest.openclawVersion)
            progress = 0.5

            let backup = try swapStagedOpenClawIntoPlace(stagedInstallDir)
            writeInflightMarker(target: manifest.openclawVersion, backupRoot: backup.root)
            progress = 0.65

            do {
                try await installGateway()
                progress = 0.78
                await runPostUpgradeDoctor()
                progress = 0.86
                do {
                    try await openclawService.start()
                } catch {
                    // 2026.7.x first boot migrates the session store
                    // (JSON -> SQLite) before binding the port; on real
                    // profiles that overshoots start()'s ~28s window and the
                    // upgrade used to roll back a perfectly healthy gateway.
                    // install --force above already relaunched it — just give
                    // it a longer grace to come up.
                    appendLog("Gateway start window elapsed; extending wait for first-boot migration")
                }
                // Whether or not start() reported success, the upgrade is only
                // real once the gateway ANSWERS. start()/checkStatus() lean on
                // `launchctl`, which reports `state = running` for a job that
                // spawns, fails to bind and gets respawned — so a crash-looping
                // gateway used to be declared a successful upgrade and the
                // rollback below never ran (measured on 192.168.80.76: the port
                // was held by another process for the whole window and the
                // upgrade still "succeeded").
                try await waitForGatewayReady(timeoutSeconds: 300)
                await openclawService.fetchVersion()
                clearInflightMarker()
                try removeBackupIfPossible(backup)
                clearFailureMemory()
                state = .upgraded(manifest.openclawVersion)
                progress = 1
                appendLog("OpenClaw core upgraded to \(manifest.openclawVersion)")
            } catch {
                appendLog("Upgrade failed after swap: \(error.localizedDescription)")
                recordFailure(target: manifest.openclawVersion)
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

    // MARK: - Failure memory

    private static var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private func loadFailureMemory() -> OpenClawCoreUpgradeFailureMemory? {
        guard let data = UserDefaults.standard.data(forKey: Self.failureMemoryKey) else { return nil }
        return try? JSONDecoder().decode(OpenClawCoreUpgradeFailureMemory.self, from: data)
    }

    private func recordFailure(target: String) {
        let previous = loadFailureMemory()
        let sameTarget = previous?.targetVersion == target
        let memory = OpenClawCoreUpgradeFailureMemory(
            targetVersion: target,
            appVersion: Self.currentAppVersion,
            failureCount: (sameTarget ? (previous?.failureCount ?? 0) : 0) + 1,
            lastFailure: Date()
        )
        if let data = try? JSONEncoder().encode(memory) {
            UserDefaults.standard.set(data, forKey: Self.failureMemoryKey)
        }
        appendLog("Recorded upgrade failure #\(memory.failureCount) for \(target); auto-retry paused for 24h")
    }

    private func clearFailureMemory() {
        UserDefaults.standard.removeObject(forKey: Self.failureMemoryKey)
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

    /// Installed version, read from DISK first.
    ///
    /// `openclaw --version` is unreliable exactly when this matters: it comes
    /// back nil during a cold start, while the gateway is booted out, or right
    /// after an interrupted attempt (measured repeatedly on 2026-07-28). A nil
    /// used to mean "older than the bundle" — so a machine ALREADY on the target
    /// version got a full stop-swap-reinstall cycle, i.e. a needless gateway
    /// outage. The package manifest is authoritative and does not care what the
    /// process state is.
    private func installedOpenClawVersion() async -> String? {
        if let version = installedCoreVersionFromDisk() {
            return version
        }
        guard let raw = await commandExecutor.getCommandVersion("openclaw", versionArg: "--version")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return nil
        }
        return OpenClawVersionComparator.extractVersionString(raw)
    }

    private func installedCoreVersionFromDisk() -> String? {
        let packageJSON = installedCoreDir.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: packageJSON),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = root["version"] as? String,
              !version.isEmpty else {
            return nil
        }
        return version
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
        await holdDownLaunchAgent()
    }

    /// Boot the LaunchAgent OUT for the duration of the swap.
    ///
    /// `gateway stop` stops the process, but the agent stays loaded with
    /// KeepAlive, so launchd relaunches it every ~10s — straight into the new
    /// core's first-boot migration, which then reports
    /// "startup migrations are already running for this state directory".
    /// Each respawn re-takes the lock the previous one is still holding, and
    /// the whole 300s ready-window is consumed by that self-inflicted race
    /// (observed in the field on 2026-07-27: 13 launchd runs, ~every 10-11s).
    ///
    /// `gateway install --force` at the end of the upgrade re-creates and
    /// re-loads the agent, and the rollback path re-loads it too, so this is
    /// never left booted out.
    private func holdDownLaunchAgent() async {
        let output = try? await runShell(
            "launchctl bootout gui/$(id -u)/\(Self.launchAgentLabel) 2>&1 || true",
            timeout: 20
        )
        appendLog("Held LaunchAgent down for the swap: \(Self.describeLaunchctl(output, quietCode: 3, quietMeaning: "already unloaded"))")
    }

    /// launchctl reports the two no-op outcomes as errors: booting out a job
    /// that is not loaded returns 3 (`No such process`) and bootstrapping one
    /// that already is returns 5 (`Input/output error`). Both are the expected
    /// path here — `gateway stop` usually unloaded it already, and
    /// `gateway install --force` usually loaded it back — so logging the raw
    /// text made a healthy upgrade read like it was failing.
    private static func describeLaunchctl(_ output: String?, quietCode: Int, quietMeaning: String) -> String {
        let text = output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty { return "ok" }
        if text.contains(": \(quietCode):") { return quietMeaning }
        return text
    }

    /// Re-load the agent after a rollback that could not reinstall it.
    private func reloadLaunchAgentIfNeeded() async {
        let plist = "\(homeDir)/Library/LaunchAgents/\(Self.launchAgentLabel).plist"
        guard fileManager.fileExists(atPath: plist) else { return }
        let output = try? await runShell(
            "launchctl bootstrap gui/$(id -u) '\(plist)' 2>&1 || launchctl load -w '\(plist)' 2>&1 || true",
            timeout: 20
        )
        appendLog("Re-loaded LaunchAgent: \(Self.describeLaunchctl(output, quietCode: 5, quietMeaning: "already loaded"))")
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
        var backup = OpenClawCoreSwapBackup(root: transactionBackupRoot, coreDir: nil, binLink: nil, configFile: nil)

        // COPY (not move) the config: the upgrade must not disturb the live
        // one, we only need a copy to restore if the new core stamps it and
        // then fails.
        if fileManager.fileExists(atPath: configFileURL.path) {
            let configBackupURL = transactionBackupRoot.appendingPathComponent("openclaw.json")
            try? fileManager.copyItem(at: configFileURL, to: configBackupURL)
            if fileManager.fileExists(atPath: configBackupURL.path) {
                backup.configFile = configBackupURL
            }
        }

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

    /// Poll until the gateway reports running. Used as the extended grace
    /// after a core swap when the regular start window was not enough (e.g.
    /// first-boot store migrations on major core upgrades).
    private func waitForGatewayReady(timeoutSeconds: Int) async throws {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            if await gatewayIsServing() {
                appendLog("Gateway answered on port \(gatewayPort())")
                return
            }
        }
        throw OpenClawCoreUpgradeError.commandFailed(
            "gateway did not answer on port \(gatewayPort()) within \(timeoutSeconds)s after core swap"
        )
    }

    /// Does the gateway actually SERVE?
    ///
    /// `launchctl` only knows whether launchd has a job: a gateway that spawns,
    /// fails to bind (port taken, invalid config, EX_CONFIG) and gets respawned
    /// every ~10s still reports `state = running`. Readiness therefore has to
    /// come from the gateway itself — any HTTP response counts, including 401
    /// or 404: it proves the process bound the port and is talking.
    private func gatewayIsServing() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(gatewayPort())/health") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return response is HTTPURLResponse
        } catch {
            return false
        }
    }

    /// Port from the user's config; the gateway's own default otherwise.
    private func gatewayPort() -> Int {
        let configURL = URL(fileURLWithPath: "\(homeDir)/.openclaw/openclaw.json")
        guard let data = try? Data(contentsOf: configURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let gateway = root["gateway"] as? [String: Any],
              let port = gateway["port"] as? Int else {
            return 18789
        }
        return port
    }

    /// Reinstall the app-bundled Node.js when the installed one is older than
    /// the core's engines floor. No-op when no floor is declared or the
    /// installed Node already satisfies it.
    private func ensureNodeSatisfiesRequirement(_ minimumNodeVersion: String?) async throws {
        guard let minimumNodeVersion, !minimumNodeVersion.isEmpty else { return }
        let nodePath = "\(homeDir)/.openclaw/node/bin/node"
        var installedNode: String?
        if fileManager.isExecutableFile(atPath: nodePath),
           let out = try? await runShell("'\(nodePath)' --version", timeout: 10) {
            installedNode = out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let installedNode,
           OpenClawVersionComparator.compare(installedNode, minimumNodeVersion) != .orderedAscending {
            appendLog("Node \(installedNode) satisfies required >= \(minimumNodeVersion)")
            return
        }
        appendLog("Node \(installedNode ?? "missing") is below required \(minimumNodeVersion); installing bundled Node")
        let installer = NodeInstaller(commandExecutor: commandExecutor)
        try await installer.installBundledNode()
        appendLog("Bundled Node installed")
    }

    private func installGateway() async throws {
        appendLog("Reinstalling OpenClaw gateway with upgraded core")
        let nodePath = "\(homeDir)/.openclaw/node/bin/node"
        let openclawPath = installedBinLink.path
        // --force: after the core swap the LaunchAgent is still loaded from
        // the previous install, and a plain `gateway install` just prints
        // "already loaded — reinstall with --force" WITHOUT starting anything.
        // The subsequent health wait then times out and the whole upgrade
        // rolls back (observed live on the 6.10 -> 7.1 upgrade).
        let command: String
        if fileManager.isExecutableFile(atPath: nodePath) {
            command = "'\(nodePath)' '\(openclawPath)' gateway install --force 2>&1"
        } else {
            command = "'\(openclawPath)' gateway install --force 2>&1"
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

    private func writeInflightMarker(target: String, backupRoot: URL) {
        let marker = OpenClawCoreUpgradeInflightMarker(
            targetVersion: target,
            backupRoot: backupRoot.path,
            startedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(marker) else { return }
        try? data.write(to: inflightMarkerURL, options: .atomic)
    }

    private func clearInflightMarker() {
        try? fileManager.removeItem(at: inflightMarkerURL)
    }

    /// Finish an attempt whose app died between the core swap and the verdict.
    ///
    /// Three states are possible, and only one of them warrants a rollback —
    /// blindly restoring the backup would undo a perfectly good upgrade whose
    /// marker simply outlived it:
    ///
    ///   installed == target, gateway answers  -> it worked; just tidy up
    ///   installed == target, gateway silent   -> half-upgraded; roll back
    ///   installed != target                   -> swap never landed; tidy up
    private func recoverFromInterruptedUpgradeIfNeeded() async {
        guard let data = try? Data(contentsOf: inflightMarkerURL),
              let marker = try? JSONDecoder().decode(OpenClawCoreUpgradeInflightMarker.self, from: data) else {
            return
        }
        appendLog("Found an interrupted upgrade to \(marker.targetVersion) started at \(marker.startedAt)")

        // The version probe is NOT the signal: right after an interrupted
        // attempt it comes back nil (measured — a cold `openclaw --version`
        // while the gateway is booted out), and treating that as "the swap
        // never landed" walked straight past a half-upgraded machine. What
        // proves the swap happened is the backup: the old core is only moved
        // aside when the new one goes in.
        let backupRoot = URL(fileURLWithPath: marker.backupRoot)
        let coreBackup = backupRoot.appendingPathComponent("openclaw")
        guard fileManager.fileExists(atPath: coreBackup.path) else {
            appendLog("No backup at \(marker.backupRoot); nothing to finish, clearing marker")
            clearInflightMarker()
            return
        }

        // Health decides, with a grace period: the app may be launching right
        // after a reboot, where the gateway simply has not come up yet, and
        // rolling back a healthy upgrade would be worse than the bug.
        var serving = await gatewayIsServing()
        if !serving {
            appendLog("Gateway silent; giving it 60s before deciding the interrupted upgrade failed")
            let deadline = Date().addingTimeInterval(60)
            while !serving, Date() < deadline {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                serving = await gatewayIsServing()
            }
        }

        if serving {
            appendLog("Interrupted upgrade to \(marker.targetVersion) is healthy after all; clearing marker")
            clearFailureMemory()
            clearInflightMarker()
            return
        }

        appendLog("Rolling back the interrupted upgrade to \(marker.targetVersion)")
        recordFailure(target: marker.targetVersion)
        let binBackup = backupRoot.appendingPathComponent("openclaw-bin")
        let configBackup = backupRoot.appendingPathComponent("openclaw.json")
        let backup = OpenClawCoreSwapBackup(
            root: backupRoot,
            coreDir: coreBackup,
            binLink: itemExistsIncludingSymlink(at: binBackup) ? binBackup : nil,
            configFile: fileManager.fileExists(atPath: configBackup.path) ? configBackup : nil
        )
        try? await rollback(from: backup)
        state = .rolledBack("interrupted upgrade to \(marker.targetVersion)")
    }

    private func rollback(from backup: OpenClawCoreSwapBackup) async throws {
        appendLog("Rolling back OpenClaw core from backup")
        restoreOpenClawFiles(from: backup)
        openclawService.resolvedOpenclawPath = nil

        // Restore the config BEFORE reinstalling the service. The new core
        // stamps `openclaw.json` with its own version, and the restored older
        // binary then refuses to touch its own service:
        //   "Refusing to install or rewrite the gateway service because this
        //    OpenClaw binary (2026.6.10) is older than the config last written
        //    by OpenClaw 2026.7.1-2."
        // Field report 2026-07-27: that machine only recovered because its
        // LaunchAgent happened to still be loaded.
        restoreConfigIfNeeded(from: backup)

        try? await installGateway()
        // installGateway may still be refused (e.g. no config backup existed);
        // make sure the agent is loaded either way, since the swap booted it out.
        await reloadLaunchAgentIfNeeded()
        try? await openclawService.start()
        clearInflightMarker()
    }

    private func restoreConfigIfNeeded(from backup: OpenClawCoreSwapBackup) {
        guard let configBackup = backup.configFile,
              fileManager.fileExists(atPath: configBackup.path) else {
            appendLog("No config backup to restore")
            return
        }
        // Keep what the failed upgrade wrote, for diagnosis.
        let failedCopy = backup.root.appendingPathComponent("openclaw.json.upgrade-failed")
        if fileManager.fileExists(atPath: configFileURL.path) {
            try? fileManager.removeItem(at: failedCopy)
            try? fileManager.copyItem(at: configFileURL, to: failedCopy)
            try? fileManager.removeItem(at: configFileURL)
        }
        do {
            try fileManager.copyItem(at: configBackup, to: configFileURL)
            appendLog("Restored pre-upgrade config (the new core's copy kept at \(failedCopy.lastPathComponent))")
        } catch {
            appendLog("Config restore failed: \(error.localizedDescription)")
        }
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
