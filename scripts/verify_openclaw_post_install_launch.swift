import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appSources = [
    "OpenClawInstaller/Core/Update/OpenClawPostInstallLaunch.swift",
]
let testSource = "Tests/OpenClawPostInstallLaunchTests.swift"

let fm = FileManager.default
let workDir = fm.temporaryDirectory
    .appendingPathComponent("verify_openclaw_post_install_launch-\(UUID().uuidString)")
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
    fputs("FAIL: OpenClawPostInstallLaunch + its tests no longer compile\n", stderr)
    try? fm.removeItem(at: workDir)
    exit(1)
}
let status = run([binaryURL.path])
try? fm.removeItem(at: workDir)
exit(status)
