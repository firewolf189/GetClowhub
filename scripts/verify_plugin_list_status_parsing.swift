import Foundation

// `swift` interprets a single file, but this guard exercises real app logic.
// Compile the app source(s) plus the embedded driver via swiftc and run it.

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appSources = [
    "OpenClawInstaller/Services/PluginListParser.swift",
    "OpenClawInstaller/Models/PluginInfo.swift",
]

let driverSource = #"""
import Foundation

@main
struct VerifyPluginListStatusParsing {
    static func main() {
        let newFormatOutput = """
        Plugins (57/80 enabled)

        ┌──────────────┬──────────┬──────────┬──────────┬────────────────────────────────────┬───────────┐
        │ Name         │ ID       │ Format   │ Status   │ Source                             │ Version   │
        ├──────────────┼──────────┼──────────┼──────────┼────────────────────────────────────┼───────────┤
        │ Context Mode │ context- │ openclaw │ enabled  │ global:context-mode/index.js       │ v1.0.168  │
        │              │ mode     │          │          │                                    │           │
        │ Disabled One │ disabled │ openclaw │ disabled │ global:disabled-one/index.js       │ v1.0.0    │
        └──────────────┴──────────┴──────────┴──────────┴────────────────────────────────────┴───────────┘
        """

        let oldFormatOutput = """
        ┌──────────────┬──────────┬──────────┬────────────────────────────────────┬───────────┐
        │ Name         │ ID       │ Status   │ Source                             │ Version   │
        ├──────────────┼──────────┼──────────┼────────────────────────────────────┼───────────┤
        │ Loaded One   │ loaded   │ loaded   │ global:loaded-one/index.js         │ v1.0.0    │
        │ Disabled One │ disabled │ disabled │ global:disabled-one/index.js       │ v1.0.0    │
        └──────────────┴──────────┴──────────┴────────────────────────────────────┴───────────┘
        """

        let newPlugins = PluginListParser.parse(output: newFormatOutput)
        let contextMode = newPlugins.first { $0.pluginId == "context-mode" }
        let disabledNew = newPlugins.first { $0.pluginId == "disabled" }

        expect(contextMode?.enabled == true, "new format enabled status should parse as enabled")
        expect(contextMode?.source == "global:context-mode/index.js", "new format source should not be shifted into status")
        expect(contextMode?.version == "v1.0.168", "new format version should parse from version column")
        expect(disabledNew?.enabled == false, "new format disabled status should parse as disabled")

        let oldPlugins = PluginListParser.parse(output: oldFormatOutput)
        let loadedOld = oldPlugins.first { $0.pluginId == "loaded" }
        let disabledOld = oldPlugins.first { $0.pluginId == "disabled" }

        expect(loadedOld?.enabled == true, "old format loaded status should remain enabled")
        expect(disabledOld?.enabled == false, "old format disabled status should remain disabled")

        print("Plugin list status parsing verification passed")
    }

    @discardableResult
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) -> Bool {
        if condition() {
            return true
        }
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

"""#

let fm = FileManager.default
let workDir = fm.temporaryDirectory
    .appendingPathComponent("verify_plugin_list_status_parsing-\(UUID().uuidString)")
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
    fputs("FAIL: app sources + verify_plugin_list_status_parsing driver no longer compile\n", stderr)
    try? fm.removeItem(at: workDir)
    exit(1)
}
let status = run([binaryURL.path])
try? fm.removeItem(at: workDir)
exit(status)
