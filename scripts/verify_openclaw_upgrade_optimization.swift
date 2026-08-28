import Foundation

// Built-in GetClawHub upgrade optimization (2026-08-26):
// migrate leftover 2026.6.x state, gate the swap, kickstart a loaded
// LaunchAgent, and replace Node atomically — all before or instead of
// a destructive gateway stop.

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
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

func block(startingWith signature: String, in text: String) -> String {
    guard let start = text.range(of: signature) else {
        fputs("FAIL: could not find \(signature)\n", stderr)
        exit(1)
    }
    var depth = 0
    var hasEnteredBody = false
    var index = start.lowerBound
    while index < text.endIndex {
        let char = text[index]
        if char == "{" {
            depth += 1
            hasEnteredBody = true
        } else if char == "}" {
            depth -= 1
            if hasEnteredBody && depth == 0 {
                return String(text[start.lowerBound...index])
            }
        }
        index = text.index(after: index)
    }
    fputs("FAIL: could not extract block for \(signature)\n", stderr)
    exit(1)
}

let readiness = read("OpenClawInstaller/Core/Update/OpenClawUpgradeReadiness.swift")
let coordinator = read("OpenClawInstaller/Core/Update/OpenClawCoreUpgradeCoordinator.swift")
let service = read("OpenClawInstaller/Core/Command/OpenClawService.swift")
let executor = read("OpenClawInstaller/Core/Command/CommandExecutor.swift")
let nodeInstaller = read("OpenClawInstaller/Core/Install/NodeInstaller.swift")
let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")

require(
    readiness.contains("enum OpenClawUpgradeReadiness"),
    "upgrade optimization must live in OpenClawUpgradeReadiness"
)
require(
    readiness.contains("func migrateLegacyState"),
    "legacy 2026.6.x state must be migrated in-app"
)
require(
    readiness.contains("update-check.json") && readiness.contains("upgrade-quarantine"),
    "conflicting update-check.json must move to quarantine, not be deleted with SQLite"
)
require(
    readiness.contains("pluginNeedsDisable") && readiness.contains("enabled") && readiness.contains("false"),
    "plugins with TypeScript-only entries must be disabled, not uninstalled"
)
require(
    readiness.contains("Quarantined incomplete plugin package"),
    "broken plugin trees must be moved aside so 2026.7.x cannot repair them during startup migrations"
)
require(
    readiness.contains("writeConfigForStagedGate")
        && readiness.contains("stripDingTalkRejectedKeysFromLiveConfig"),
    "DingTalk extra keys are gated on a copy, then stripped from live config only after backup"
)
require(
    !readiness.contains("minimax-portal-auth") && !readiness.contains("stalePluginIDs"),
    "do not hardcode machine-specific stale plugin ids"
)
require(
    !block(startingWith: "private static func migrateOpenClawJSON", in: readiness).contains("stripRejectedKeys"),
    "migrateLegacyState must not strip DingTalk keys from the still-running gateway config"
)
require(
    readiness.contains("func evaluateGate") && readiness.contains("staged-core pre-check could not run"),
    "an inconclusive pre-check must block the swap"
)
require(
    readiness.contains("refusing to report the gateway ready")
        && readiness.contains("failed post-core payload smoke check")
        && readiness.contains("config is invalid")
        && !readiness.contains("\"requires compiled runtime output\""),
    "the gate must block real startup-migration failures, not a disabled-plugin packaging warning"
)
require(
    !readiness.contains("shared sqlite state already differs")
        && !readiness.contains("left legacy update-check state"),
    "doctor warnings about leftover update-check must not block the swap by phrase match"
)
require(
    readiness.contains("remainingBlockersOnDisk")
        && readiness.contains("update-check.json still present alongside shared SQLite state")
        && readiness.contains("incomplete TypeScript-only plugin still on disk"),
    "leftover update-check and incomplete plugins must block on disk facts after migration"
)
require(
    !readiness.contains("if lower.contains(\"is invalid\")"),
    "generic 'is invalid' matching is too broad — it blocked on 'Config valid' plus later warnings"
)
require(
    readiness.contains("lineMatching"),
    "gate failure reason must come from the matching error line, not the first log line"
)

let body = block(startingWith: "private func performUpgradeBody", in: coordinator)
require(
    body.contains("migrateLegacyState") && body.contains("evaluateGate") && body.contains("stopGatewayIfRunning"),
    "startup upgrade must migrate and gate before stopping the gateway"
)
guard let migrateIdx = body.range(of: "migrateLegacyState")?.lowerBound,
      let gateIdx = body.range(of: "evaluateGate")?.lowerBound,
      let stopIdx = body.range(of: "stopGatewayIfRunning")?.lowerBound else {
    fputs("FAIL: missing migrate/gate/stop in performUpgradeBody\n", stderr)
    exit(1)
}
require(migrateIdx < gateIdx && gateIdx < stopIdx, "migrate -> gate -> stop, never stop first")
require(
    body.contains("remainingBlockersOnDisk"),
    "disk leftovers after migration must block before stop"
)
guard let diskIdx = body.range(of: "remainingBlockersOnDisk")?.lowerBound else {
    fputs("FAIL: missing remainingBlockersOnDisk in performUpgradeBody\n", stderr)
    exit(1)
}
require(gateIdx < diskIdx && diskIdx < stopIdx, "phrase gate -> disk leftover check -> stop")
require(
    coordinator.contains("Files rolled back, service did not recover"),
    "rollback must say when the restored gateway did not come back"
)
require(
    coordinator.contains("upgrade gate blocked"),
    "a blocked gate must fail the attempt without swapping"
)

require(
    service.contains("gateway install --force"),
    "missing LaunchAgent still uses install --force"
)
require(
    service.contains("gateway restart") && service.contains("isLaunchAgentInstalled"),
    "a present LaunchAgent must restart/kickstart instead of rewriting with --force"
)
require(
    service.contains("post-install wait") || service.contains("during post-install wait"),
    "start() must wait for first-boot migrations before restarting an already-loaded agent"
)
let startBlock = block(startingWith: "func start() async throws", in: service)
guard let waitIdx = startBlock.range(of: "waiting before kickstart")?.lowerBound,
      let restartIdx = startBlock.range(of: "gateway restart")?.lowerBound,
      let forceIdx = startBlock.range(of: "gateway install --force")?.lowerBound else {
    fputs("FAIL: start() is missing wait/restart/--force ordering\n", stderr)
    exit(1)
}
require(
    waitIdx < restartIdx && restartIdx < forceIdx,
    "daily start: wait -> restart for a loaded agent; --force only if the plist is missing"
)
require(
    service.contains("Gateway already serving; skip reinstall"),
    "an already-healthy gateway must not be reinstalled"
)
require(
    service.contains("Start already in flight"),
    "parallel Start Service clicks must not launch concurrent installs"
)
require(
    service.contains("preferredOpenclawInvocationPath"),
    "service lookup must prefer the on-disk core module over which openclaw"
)
require(
    executor.contains("preferredOpenclawInvocationPath"),
    "CommandExecutor must use the same preferred openclaw path"
)

require(
    nodeInstaller.contains(".staging-") && nodeInstaller.contains(".bak-") && nodeInstaller.contains("mv \""),
    "Node must extract to staging and atomically replace ~/.openclaw/node"
)
require(
    !nodeInstaller.contains("tar -xzf \"\\(tarPath.path)\" -C \"\\(targetDir)\" --strip-components=1"),
    "Node must not overlay-extract onto the live ~/.openclaw/node tree"
)

require(
    project.contains("OpenClawUpgradeReadiness.swift in Sources"),
    "OpenClawUpgradeReadiness.swift must be compiled into the app"
)

print("openclaw upgrade optimization guards hold")
