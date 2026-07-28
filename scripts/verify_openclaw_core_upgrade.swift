import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let manifestModelURL = root.appendingPathComponent("OpenClawInstaller/Core/Install/OpenClawCoreManifest.swift")
let coordinatorURL = root.appendingPathComponent("OpenClawInstaller/Core/Update/OpenClawCoreUpgradeCoordinator.swift")
let appURL = root.appendingPathComponent("OpenClawInstaller/App/OpenClawInstallerApp.swift")
let manifestURL = root.appendingPathComponent("OpenClawInstaller/Resources/openclaw-core-version.json")
let releaseURL = root.appendingPathComponent("RELEASE.md")

func read(_ url: URL) -> String {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fputs("FAIL: could not read \(url.path)\n", stderr)
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

let manifestModel = read(manifestModelURL)
let coordinator = read(coordinatorURL)
let app = read(appURL)
let release = read(releaseURL)

let manifestData = try Data(contentsOf: manifestURL)
let manifestJSON = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
require(manifestJSON?["version"] as? Int == 1, "core manifest should include schema version 1")
require((manifestJSON?["openclawVersion"] as? String)?.isEmpty == false, "core manifest should declare openclawVersion")
require(manifestJSON?["bundleName"] as? String == "openclaw-bundle.tar.gz", "core manifest should reference openclaw-bundle.tar.gz")

require(manifestModel.contains("struct OpenClawCoreManifest"), "manifest model should exist")
require(manifestModel.contains("enum OpenClawVersionComparator"), "version comparator should exist")
require(manifestModel.contains("normalizedComponents"), "version comparison should normalize numeric components")
require(manifestModel.contains("isBundledVersionNewer"), "manifest model should expose bundled-version upgrade decision")
require(manifestModel.contains("loadBundled"), "manifest should load from app resources")

require(coordinator.contains("final class OpenClawCoreUpgradeCoordinator"), "core upgrade coordinator should exist")
require(coordinator.contains("@Published var state"), "coordinator should publish upgrade state")
require(coordinator.contains("ensureBundledCoreIsCurrent"), "coordinator should expose startup upgrade entrypoint")
require(coordinator.contains("openclaw gateway stop") || coordinator.contains("gateway stop"), "upgrade should stop the old gateway before swapping core")
require(coordinator.contains(".openclaw/core-upgrade-staging"), "upgrade should extract into a staging directory")
require(coordinator.contains(".openclaw/core-upgrade-backups"), "upgrade should keep rollback backups")
require(coordinator.contains("installedCoreDir"), "upgrade should target the installed openclaw package directory")
require(coordinator.contains("installedBinLink"), "upgrade should target only the installed openclaw bin link")
require(coordinator.contains("verifyStagedCore"), "upgrade should verify staged core before swapping")
require(coordinator.contains("swapStagedOpenClawIntoPlace"), "upgrade should swap only the openclaw package after verification")
require(coordinator.contains("rollback"), "upgrade should roll back on failure")
require(!coordinator.contains("moveItem(at: installDir, to:"), "upgrade must not move the entire ~/.npm-global directory")
require(coordinator.contains("gateway install"), "upgrade should reinstall gateway after core swap")
require(coordinator.contains("openclawService.start()"), "upgrade should restart gateway through OpenClawService")
require(coordinator.contains("doctor --post-upgrade --json") && coordinator.contains("doctor --fix"), "upgrade should try post-upgrade doctor with fallback")

// The steps moved into `performUpgradeBody()`: the public entry point now only
// spawns an unstructured Task so a cancelled caller cannot abort a half-done
// core swap (observed on the 6.10 -> 7.1 upgrade).
require(
    coordinator.contains("let work = Task { await performUpgradeBody(force: force) }"),
    "the upgrade must run in an unstructured Task so caller cancellation cannot abort a half-done swap"
)
let upgradeBlock = block(startingWith: "private func performUpgradeBody", in: coordinator)
let stopIndex = upgradeBlock.range(of: "stopGatewayIfRunning")?.lowerBound
let stageIndex = upgradeBlock.range(of: "extractBundleToStaging")?.lowerBound
let verifyIndex = upgradeBlock.range(of: "verifyStagedCore")?.lowerBound
let swapIndex = upgradeBlock.range(of: "swapStagedOpenClawIntoPlace")?.lowerBound
let installIndex = upgradeBlock.range(of: "installGateway")?.lowerBound
let startIndex = upgradeBlock.range(of: "openclawService.start")?.lowerBound
require(stopIndex != nil && stageIndex != nil && verifyIndex != nil && swapIndex != nil && installIndex != nil && startIndex != nil, "upgrade flow should call all major steps")
// Reordered 2026-07-28: staging and vetting moved AHEAD of the stop, so a core
// that rejects this machine's config never costs the user their gateway.
require(stageIndex! < verifyIndex! && verifyIndex! < stopIndex! && stopIndex! < swapIndex! && swapIndex! < installIndex! && installIndex! < startIndex!, "upgrade flow should stage -> verify -> stop -> swap -> gateway install -> start")

// --- Readiness must come from the GATEWAY, not from launchd ---
// Measured on 192.168.80.76 (2026-07-28): with another process holding
// 127.0.0.1:18789 and [::1]:18789 for the whole window — so the gateway could
// not possibly serve — `launchctl` still reported `state = running` for the
// respawning job, and the upgrade was declared SUCCESSFUL. Every containment
// step (cooldown, rollback, config restore) hangs off the failure branch, so a
// crash-looping gateway silently kept the half-broken core.
require(
    coordinator.contains("private func gatewayIsServing() async -> Bool"),
    "readiness needs a real probe of the gateway, not just the launchd job state"
)
require(
    coordinator.contains("http://127.0.0.1:") && coordinator.contains("gatewayPort()") && coordinator.contains("/health"),
    "the probe should ask the gateway itself on its configured port"
)
require(
    coordinator.contains("return response is HTTPURLResponse"),
    "any HTTP response proves the port is bound and answering — 401/404 count"
)
let readyBlock = block(startingWith: "private func waitForGatewayReady", in: coordinator)
require(
    readyBlock.contains("if await gatewayIsServing()"),
    "the wait loop must poll the real probe"
)
require(
    !readyBlock.contains("openclawService.status == .running"),
    "launchctl state alone must not end the wait — that is what declared a crash-looping gateway ready"
)
let upgradeBody = block(startingWith: "private func performUpgradeBody", in: coordinator)
guard let startRange = upgradeBody.range(of: "openclawService.start()"),
      let waitRange = upgradeBody.range(of: "try await waitForGatewayReady(timeoutSeconds: 300)") else {
    fputs("FAIL: could not locate start/wait in the upgrade body\n", stderr)
    exit(1)
}
require(
    startRange.upperBound < waitRange.lowerBound,
    "the readiness wait must run AFTER start() on every path, including when start() reports success"
)
require(
    coordinator.contains("private static func describeLaunchctl"),
    "launchctl's no-op exit codes (3 = not loaded, 5 = already loaded) must not be logged as failures"
)

// --- An interrupted attempt must be finishable by the NEXT launch ---
// The rollback lives in the running app, so quitting during the five-minute
// readiness wait left a machine on the new core with a dead gateway (field,
// 2026-07-27; reproduced by killing the app mid-swap on 192.168.80.76).
require(
    coordinator.contains("private struct OpenClawCoreUpgradeInflightMarker"),
    "the swap must leave a marker on disk so a lost process does not lose the recovery"
)
require(
    coordinator.contains("writeInflightMarker(target:") && coordinator.contains("clearInflightMarker()"),
    "the marker must be written at the swap and cleared once the attempt resolves"
)
require(
    coordinator.contains("await recoverFromInterruptedUpgradeIfNeeded()"),
    "the next launch must finish an interrupted attempt before looking at versions"
)
let recovery = block(startingWith: "private func recoverFromInterruptedUpgradeIfNeeded", in: coordinator)
require(
    recovery.contains("fileManager.fileExists(atPath: coreBackup.path)"),
    "recovery must key on the BACKUP to know the swap happened — the version probe returns nil in exactly this state"
)
require(
    recovery.contains("var serving = await gatewayIsServing()") && recovery.contains("giving it 60s"),
    "recovery must decide on gateway health, with a grace period so a slow boot is not rolled back"
)

// --- An unknown installed version must not be read as "needs upgrade" ---
// `openclaw --version` comes back nil during cold starts and while the gateway
// is booted out; nil used to compare as older than the bundle, so a machine
// ALREADY on the target version got a full stop-swap-reinstall cycle.
require(
    coordinator.contains("private func installedCoreVersionFromDisk"),
    "the installed version should be read from the package manifest, which does not depend on process state"
)
require(
    coordinator.contains("Cannot determine the installed OpenClaw version; skipping"),
    "with no readable version at all, skip rather than swap blind"
)

// --- Ask the NEW core before committing to it ---
// A machine's config was valid for 2026.3.2 and rejected by 2026.7.1-2 (a
// locally path-installed plugin whose entry "escapes package directory"). The
// upgrade swapped anyway and the gateway crash-looped, so the vetting has to
// happen with the STAGED binary and BEFORE the running gateway is touched.
require(
    coordinator.contains("private func configRejectedByStagedCore"),
    "the staged core must be asked whether it accepts this machine's config"
)
require(
    coordinator.contains("config validate 2>&1 || true"),
    "the verdict comes from the output: `config validate` exits non-zero exactly when the config is invalid, and a throwing runShell made that look like the check could not run"
)
let body = block(startingWith: "private func performUpgradeBody", in: coordinator)
guard let verifyIdx = body.range(of: "verifyStagedCore")?.lowerBound,
      let precheckIdx = body.range(of: "configRejectedByStagedCore")?.lowerBound,
      let stopIdx = body.range(of: "stopGatewayIfRunning")?.lowerBound else {
    fputs("FAIL: could not locate stage/pre-check/stop in the upgrade body\n", stderr)
    exit(1)
}
require(
    verifyIdx < precheckIdx && precheckIdx < stopIdx,
    "stage -> verify -> config pre-check must all precede stopping the gateway, so a core that cannot accept this config costs the user no downtime"
)

require(app.contains("private let coreUpgradeCoordinator: OpenClawCoreUpgradeCoordinator"), "AppServices should keep the core migration helper internal")
require(app.contains("ensureBundledCoreForInstalledOpenClaw"), "App startup should run bundled core migration outside dashboard routing")
require(app.contains("didStartBundledCoreCheck"), "App startup should guard bundled core migration so it only starts once")
require(app.contains("await services.ensureOpenClawCoreIsCurrent()"), "startup routing should run bundled core migration after detecting OpenClaw")
require(!app.contains("coreUpgradeState"), "startup UI should not expose core upgrade state")
require(!app.contains("statusText"), "startup UI should not add a core upgrade status line")
require(!app.contains("coreUpgradeCoordinator: cuc"), "DashboardViewModel should not take a core upgrade coordinator")
require(!app.contains("OpenClaw core upgraded to"), "dashboard UI should not show core upgrade success toasts")

require(release.contains("openclaw-core-version.json"), "release docs should mention the core manifest")
require(release.contains("openclaw --version"), "release docs should require verifying bundled OpenClaw version")

print("OpenClaw core upgrade verification passed")
