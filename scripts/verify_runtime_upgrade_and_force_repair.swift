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
let safeRepair = read("OpenClawInstaller/Core/Command/SafeGatewayRepair.swift")
let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")
let buildScript = read("build_dmg.sh")

// --- Runtime upgrade coherence ---
require(
    manifest.contains("\"openclawVersion\": \"2026.7."),
    "bundled core manifest must declare the 2026.7.x core"
)
require(
    manifest.contains("\"supportedNodeRanges\""),
    "manifest must declare supportedNodeRanges — engines.node is a SET of disjoint ranges, and a core refuses to boot outside them"
)
require(
    manifest.contains(">=24.15.0 <25") && manifest.contains(">=25.9.0"),
    "supportedNodeRanges must carry the upper bounds too: Node 25.0–25.8 is newer than the 24.15 floor and STILL rejected, so a floor-only check ships a gateway that cannot start"
)
require(
    coordinator.contains("ensureNodeSatisfiesRequirement(manifest.nodeRuntimeRequirement)"),
    "core upgrade must bring Node into a supported range BEFORE swapping the core (Windows v0.6.31 lesson: core-only upgrade bricks the gateway)"
)
require(
    coordinator.contains("nodeRequirementUnsatisfiable"),
    "if even the bundled Node cannot satisfy the new core, the upgrade must abort while the OLD working core is still in place"
)
require(
    !coordinator.contains("OpenClawVersionComparator.compare(installedNode, minimumNodeVersion)"),
    "the Node check must not regress to a single >= floor comparison"
)
require(
    nodeInstaller.contains("func installBundledNode()"),
    "NodeInstaller must expose the bundled-Node reinstall used by the upgrade path"
)
// Node version must agree across every packaging reference.
let nodeVersion = "v24.18.0"
let diagnostics = read("OpenClawInstaller/Features/Status/DiagnosticService.swift")
let bundledDocs = read("BUNDLED_NODEJS.md")
let releaseDocs = read("RELEASE.md")
for (name, text) in [
    ("NodeInstaller", nodeInstaller),
    ("pbxproj", project),
    ("build_dmg.sh", buildScript),
    ("BUNDLED_NODEJS.md", bundledDocs),
    ("RELEASE.md", releaseDocs),
] {
    require(
        text.contains(nodeVersion),
        "\(name) still references an old bundled Node version (want \(nodeVersion))"
    )
    require(
        !text.contains("v24.14.0"),
        "\(name) still references the retired Node v24.14.0"
    )
}
require(
    diagnostics.contains("BundledRuntimeVersions.nodeJSVersion") &&
        !diagnostics.contains("v24.14.0") &&
        !diagnostics.contains("bundled v24."),
    "diagnostic Node copy must read BundledRuntimeVersions.nodeJSVersion instead of a hardcoded version"
)
require(
    bundledDocs.contains("darwin-x64") &&
        releaseDocs.contains("appcast-cn.xml") &&
        releaseDocs.contains("Core/Install/NodeInstaller.swift"),
    "bundled-runtime docs must describe both Node architectures, dual Sparkle feeds, and the real installer path"
)

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
require(
    safeRepair.contains(#"minimumCoreVersion = "2026.7.1-2""#),
    "safe repair must require the first bundled core with official indefinite deferral"
)
require(
    safeRepair.contains("gateway restart --safe --json")
        && safeRepair.contains("gateway.reload.deferralTimeoutMs 0 --strict-json")
        && safeRepair.contains("session.dmScope"),
    "safe repair must use official validated config commands and official safe restart"
)
require(
    !safeRepair.contains("pkill") && !safeRepair.contains("kill -9"),
    "safe repair must never contain process-purge commands"
)
require(
    repair.contains("repairRequiredGatewaySettings(report: &report)"),
    "the separately confirmed emergency repair must also fix the required session settings"
)
require(
    project.contains("SafeGatewayRepair.swift in Sources"),
    "SafeGatewayRepair.swift must be compiled into the app target"
)

// --- Runtime guard reaches every path that starts a gateway ---
let service = read("OpenClawInstaller/Core/Command/OpenClawService.swift")
require(
    service.contains("repairDedicatedNodeIfUnsupported()"),
    "start() must repair an out-of-range Node before asking the gateway to boot — existence alone is not enough"
)
require(
    service.contains("unsupportedRuntimeComplaint()"),
    "a gateway down because of the Node guard must be able to say so: the guard exits before any gateway-owned log exists"
)
for file in [
    "OpenClawInstaller/Core/Install/NodeRuntimeRequirement.swift",
    "OpenClawInstaller/Core/Command/GatewayFailureReasonParser.swift",
] {
    let name = (file as NSString).lastPathComponent
    require(
        project.contains("\(name) in Sources"),
        "\(name) must be compiled into the app target"
    )
}

print("runtime-upgrade + force-repair guards hold")
