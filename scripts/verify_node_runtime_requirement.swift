import Foundation

// Compiles the real NodeRuntimeRequirement against the real comparator and runs
// the range-semantics cases in Tests/NodeRuntimeRequirementTests.swift.
//
// Why this exists: the gateway's launcher exits(1) on an unsupported Node before
// binding a port, and its `engines` field is a set of disjoint ranges, not a
// floor. Modelling it as a floor lets Node 25.0–25.8 through and produces an
// upgrade that reports success and leaves the user without a gateway.

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appSources = [
    "OpenClawInstaller/Core/Install/NodeRuntimeRequirement.swift",
    "OpenClawInstaller/Core/Install/OpenClawCoreManifest.swift",
]
let testSource = "Tests/NodeRuntimeRequirementTests.swift"

let fm = FileManager.default
let workDir = fm.temporaryDirectory
    .appendingPathComponent("verify_node_runtime_requirement-\(UUID().uuidString)")
try! fm.createDirectory(at: workDir, withIntermediateDirectories: true)
let binaryURL = workDir.appendingPathComponent("verify")

// NodeInstaller carries BundledRuntimeVersions but drags in Combine/UI-adjacent
// dependencies, so the pinned bundled version is mirrored here from the single
// source of truth and asserted to match.
let installer = try! String(
    contentsOf: repoRoot.appendingPathComponent("OpenClawInstaller/Core/Install/NodeInstaller.swift"),
    encoding: .utf8
)
guard let versionRange = installer.range(of: #"nodeJSVersion = "v[0-9.]+""#, options: .regularExpression),
      let quoted = installer[versionRange].range(of: #"v[0-9.]+"#, options: .regularExpression) else {
    fputs("FAIL: could not read BundledRuntimeVersions.nodeJSVersion from NodeInstaller.swift\n", stderr)
    exit(1)
}
let bundledNodeVersion = String(installer[versionRange][quoted])

let shimURL = workDir.appendingPathComponent("shim.swift")
try! """
// Mirrored from OpenClawInstaller/Core/Install/NodeInstaller.swift at verify time.
enum BundledRuntimeVersions {
    static let nodeJSVersion = "\(bundledNodeVersion)"
}
""".write(to: shimURL, atomically: true, encoding: .utf8)

@discardableResult
func run(_ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    do { try process.run() } catch {
        fputs("FAIL: could not launch \(arguments[0]): \(error)\n", stderr)
        exit(1)
    }
    process.waitUntilExit()
    return process.terminationStatus
}

var compileArgs = ["swiftc"]
compileArgs += appSources.map { repoRoot.appendingPathComponent($0).path }
compileArgs += [
    repoRoot.appendingPathComponent(testSource).path,
    shimURL.path,
    "-o", binaryURL.path,
]
if run(compileArgs) != 0 {
    fputs("FAIL: NodeRuntimeRequirement + its tests no longer compile\n", stderr)
    try? fm.removeItem(at: workDir)
    exit(1)
}
let status = run([binaryURL.path])
try? fm.removeItem(at: workDir)
exit(status)
