import Foundation

// Compiles the real GatewayFailureReasonParser and runs its cases.
//
// Why this exists: a gateway that exits because of the core's Node version guard
// used to produce no user-visible reason at all — the guard's sentence matched
// none of the parser's markers, and the LaunchAgent sends stderr to /dev/null on
// some cores, so "网关启动失败" was all the user got.

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appSources = [
    "OpenClawInstaller/Core/Command/GatewayFailureReasonParser.swift",
]
let testSource = "Tests/GatewayFailureReasonParserTests.swift"

let fm = FileManager.default
let workDir = fm.temporaryDirectory
    .appendingPathComponent("verify_gateway_failure_reason_parser-\(UUID().uuidString)")
try! fm.createDirectory(at: workDir, withIntermediateDirectories: true)
let binaryURL = workDir.appendingPathComponent("verify")

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
compileArgs += [repoRoot.appendingPathComponent(testSource).path, "-o", binaryURL.path]
if run(compileArgs) != 0 {
    fputs("FAIL: GatewayFailureReasonParser + its tests no longer compile\n", stderr)
    try? fm.removeItem(at: workDir)
    exit(1)
}
let status = run([binaryURL.path])
try? fm.removeItem(at: workDir)
exit(status)
