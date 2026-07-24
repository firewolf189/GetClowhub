import Foundation

// Guards for the 2026-07 runtime upgrade (openclaw 2026.7.x + Node 24.18) and
// the macOS force-repair feature.

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

let manifest = read("OpenClawInstaller/Resources/openclaw-core-version.json")
let coordinator = read("OpenClawInstaller/Core/Update/OpenClawCoreUpgradeCoordinator.swift")
let nodeInstaller = read("OpenClawInstaller/Core/Install/NodeInstaller.swift")
let repair = read("OpenClawInstaller/Core/Command/OpenClawServiceForceRepair.swift")
let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")
let buildScript = read("build_dmg.sh")

// --- Runtime upgrade coherence ---
require(
    manifest.contains("\"openclawVersion\": \"2026.7."),
    "bundled core manifest must declare the 2026.7.x core"
)
require(
    manifest.contains("\"minimumNodeVersion\""),
    "manifest must declare minimumNodeVersion — 2026.7.x cores refuse to boot on Node < 24.15"
)
require(
    coordinator.contains("ensureNodeSatisfiesRequirement(manifest.minimumNodeVersion)"),
    "core upgrade must raise the Node floor BEFORE swapping the core (Windows v0.6.31 lesson: core-only upgrade bricks the gateway)"
)
require(
    nodeInstaller.contains("func installBundledNode()"),
    "NodeInstaller must expose the bundled-Node reinstall used by the upgrade path"
)
// Node version must agree across every packaging reference.
let nodeVersion = "v24.18.0"
for (name, text) in [("NodeInstaller", nodeInstaller), ("pbxproj", project), ("build_dmg.sh", buildScript)] {
    require(
        text.contains(nodeVersion),
        "\(name) still references an old bundled Node version (want \(nodeVersion))"
    )
    require(
        !text.contains("v24.14.0"),
        "\(name) still references the retired Node v24.14.0"
    )
}

// --- Force repair ---
require(
    repair.contains("func forceRepairGateway()"),
    "OpenClawService must expose forceRepairGateway"
)
require(
    repair.contains("lsof -ti tcp:") && repair.contains("pkill -9 -f 'openclaw.*gateway'"),
    "force repair must purge both the port holder and pattern-matched orphans"
)
require(
    repair.contains(".broken-"),
    "a corrupt config must be quarantined (backed up), never deleted"
)
require(
    project.contains("OpenClawServiceForceRepair.swift in Sources"),
    "OpenClawServiceForceRepair.swift must be compiled into the app target"
)

print("runtime-upgrade + force-repair guards hold")
