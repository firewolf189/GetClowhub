import Foundation

// This guard exercises the real OutputsSidebarLayoutMetrics app logic. `swift`
// can only interpret a single file, so we compile the app source together with
// an embedded behavioral driver via swiftc and run the result.

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appSources = [
    "OpenClawInstaller/Views/Dashboard/OutputsSidebarLayoutMetrics.swift",
]

let driverSource = #"""
import CoreGraphics

@main
struct VerifyOutputsSidebarLayout {
    static func main() {
        let metrics = OutputsSidebarLayoutMetrics()

        assertEqual(
            metrics.collapsedWidth,
            0,
            "closed sidebar reserves no trailing strip width"
        )
        assertEqual(
            metrics.sidebarWidth(isExpanded: false, hasEditor: false, availableWidth: 1200),
            0,
            "closed sidebar reserves no trailing strip width"
        )
        assertEqual(
            metrics.sidebarWidth(isExpanded: true, hasEditor: false, availableWidth: 1200),
            metrics.browserWidth,
            "expanded sidebar shows the workspace browser width"
        )
        assertEqual(
            metrics.sidebarWidth(isExpanded: true, hasEditor: true, availableWidth: 1600),
            metrics.browserWidth + metrics.editorWidth,
            "expanded sidebar includes editor width when a file is open"
        )
        assertEqual(
            metrics.sidebarWidth(isExpanded: true, hasEditor: false, availableWidth: 760),
            0,
            "narrow windows close Outputs without leaving a trailing strip"
        )
        assertEqual(
            metrics.chatColumnWidth(for: 1400),
            metrics.chatColumnMaxWidth,
            "wide chat stages keep a stable maximum column width"
        )
        assertEqual(
            metrics.chatColumnWidth(for: 600),
            600,
            "narrow chat stages use the available width"
        )
        print("OutputsSidebarLayoutMetrics verification passed")
    }

    private static func assertEqual(
        _ actual: CGFloat,
        _ expected: CGFloat,
        _ message: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard abs(actual - expected) < 0.001 else {
            fatalError("\(message): expected \(expected), got \(actual)", file: file, line: line)
        }
    }
}
"""#

let fm = FileManager.default
let workDir = fm.temporaryDirectory
    .appendingPathComponent("verify_outputs_sidebar_layout-\(UUID().uuidString)")
try! fm.createDirectory(at: workDir, withIntermediateDirectories: true)
let driverURL = workDir.appendingPathComponent("driver.swift")
try! driverSource.write(to: driverURL, atomically: true, encoding: .utf8)
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
compileArgs += [driverURL.path, "-o", binaryURL.path]
if run(compileArgs) != 0 {
    fputs("FAIL: OutputsSidebarLayoutMetrics app source + verification driver no longer compile\n", stderr)
    try? fm.removeItem(at: workDir)
    exit(1)
}
let status = run([binaryURL.path])
try? fm.removeItem(at: workDir)
exit(status)
