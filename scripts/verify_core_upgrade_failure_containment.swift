import Foundation

// Guards the three containment rules added after the 2026-07-27 field failure,
// where a user's 6.10 -> 7.1-2 upgrade turned a broken third-party plugin into
// a 13-minute gateway outage.
//
// What happened (from ~/.openclaw/core-upgrade.log + gateway.log on that box):
//   16:30:26 upgrade starts; the new core's startup migration refuses to report
//            ready because `openclaw-web-search` ships a TS entry with no
//            compiled output (post-core payload smoke check).
//   16:34:25 launchd (KeepAlive) keeps respawning the gateway every ~10s, each
//            respawn hitting "startup migrations are already running for this
//            state directory" — the self-inflicted race that ate the 300s wait.
//   16:36:23 rollback to 6.10; 16:36:36 the old gateway is READY again.
//   16:36:52 the client STARTS THE UPGRADE AGAIN and kills it at 16:36:55.
//   16:42:51 after the second rollback the 6.10 binary refuses to reinstall its
//            own service, because the config was stamped by 2026.7.1-2.
//
// Rule 4 (do not roll back once migrations have started) was deliberately NOT
// adopted; this file covers 1-3 only.

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
        fputs("FAIL: could not read \(path)\n", stderr)
        exit(1)
    }
    return text
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let coordinator = read("OpenClawInstaller/Core/Update/OpenClawCoreUpgradeCoordinator.swift")

// --- 1. A failed target must not be retried immediately ---
require(
    coordinator.contains("private var didAttemptThisLaunch = false"),
    "at most one automatic attempt per launch — the two startup entry points fire sequentially and `isRunning` only prevents overlap"
)
require(
    coordinator.contains("struct OpenClawCoreUpgradeFailureMemory"),
    "a failed target must be remembered across launches"
)
require(
    coordinator.contains("func blocksRetry(target: String, appVersion currentAppVersion: String, now: Date, cooldown: TimeInterval) -> Bool"),
    "the cooldown decision should be a pure, testable function"
)
require(
    coordinator.contains("guard targetVersion == target, appVersion == currentAppVersion else { return false }"),
    "a NEW app version (or a new target) must be allowed to retry immediately"
)
require(
    coordinator.contains("recordFailure(target: manifest.openclawVersion)"),
    "the post-swap failure path must record the failure before rolling back"
)
require(
    coordinator.contains("clearFailureMemory()"),
    "a successful upgrade must clear the memory"
)
require(
    coordinator.contains("func ensureBundledCoreIsCurrent(force: Bool = false)"),
    "a user-initiated repair must be able to bypass the cooldown"
)

// --- 2. launchd must be held down across the swap ---
require(
    coordinator.contains("launchctl bootout gui/$(id -u)/\\(Self.launchAgentLabel)"),
    "the LaunchAgent must be booted out for the swap, or KeepAlive respawns race the first-boot migration"
)
require(
    coordinator.contains("await holdDownLaunchAgent()"),
    "stopGatewayIfRunning must hold the agent down, not just stop the process"
)
require(
    coordinator.contains("func reloadLaunchAgentIfNeeded()") && coordinator.contains("await reloadLaunchAgentIfNeeded()"),
    "the rollback path must re-load the agent it booted out, even when the service reinstall is refused"
)

// --- 3. Rollback must restore the config, before reinstalling the service ---
require(
    coordinator.contains("var configFile: URL?"),
    "the swap backup must include the pre-upgrade config"
)
require(
    coordinator.contains("try? fileManager.copyItem(at: configFileURL, to: configBackupURL)"),
    "the config must be COPIED, so the upgrade never disturbs the live file"
)
guard let restoreIndex = coordinator.range(of: "restoreConfigIfNeeded(from: backup)")?.lowerBound,
      let installIndex = coordinator.range(of: "try? await installGateway()\n        // installGateway may still be refused")?.lowerBound else {
    fputs("FAIL: rollback no longer restores the config before reinstalling the service\n", stderr)
    exit(1)
}
require(
    restoreIndex < installIndex,
    "restore the config BEFORE reinstalling: an older binary refuses to rewrite a service whose config was stamped by a newer one"
)
require(
    coordinator.contains("openclaw.json.upgrade-failed"),
    "keep what the failed upgrade wrote, for diagnosis"
)

print("core upgrade failure containment guards hold")
