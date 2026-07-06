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

let upgradeBlock = block(startingWith: "func ensureBundledCoreIsCurrent", in: coordinator)
let stopIndex = upgradeBlock.range(of: "stopGatewayIfRunning")?.lowerBound
let stageIndex = upgradeBlock.range(of: "extractBundleToStaging")?.lowerBound
let verifyIndex = upgradeBlock.range(of: "verifyStagedCore")?.lowerBound
let swapIndex = upgradeBlock.range(of: "swapStagedOpenClawIntoPlace")?.lowerBound
let installIndex = upgradeBlock.range(of: "installGateway")?.lowerBound
let startIndex = upgradeBlock.range(of: "openclawService.start")?.lowerBound
require(stopIndex != nil && stageIndex != nil && verifyIndex != nil && swapIndex != nil && installIndex != nil && startIndex != nil, "upgrade flow should call all major steps")
require(stopIndex! < stageIndex! && stageIndex! < verifyIndex! && verifyIndex! < swapIndex! && swapIndex! < installIndex! && installIndex! < startIndex!, "upgrade flow should stop -> stage -> verify -> swap -> gateway install -> start")

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
