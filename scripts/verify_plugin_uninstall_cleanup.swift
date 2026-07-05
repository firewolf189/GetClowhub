import Foundation

// `swift` interprets a single file, but this guard exercises real app logic.
// Compile the app source(s) plus the embedded driver via swiftc and run it.

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appSources = [
    "OpenClawInstaller/Services/PluginCatalogService.swift",
    "OpenClawInstaller/Models/PluginCatalogItem.swift",
    "OpenClawInstaller/Services/I18nService.swift",
    "OpenClawInstaller/Services/LanguageManager.swift",
    "OpenClawInstaller/Models/MarketplaceAgent.swift",
    "OpenClawInstaller/Models/SkillCatalogItem.swift",
]

let driverSource = #"""
import Foundation

@main
struct VerifyPluginUninstallCleanup {
    static func main() throws {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("openclaw-plugin-uninstall-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: rootURL) }

        let pluginURL = rootURL.appendingPathComponent("linear")
        let siblingURL = rootURL.appendingPathComponent("google-calendar")
        try fileManager.createDirectory(at: pluginURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: siblingURL, withIntermediateDirectories: true)
        try "runtime".write(to: pluginURL.appendingPathComponent("openclaw.adapter.js"), atomically: true, encoding: .utf8)

        let resolvedURL = PluginUninstallCleanup.globalInstallURL(
            pluginID: "linear",
            source: "global:linear/openclaw.adapter.js",
            extensionsRoot: rootURL
        )
        expect(resolvedURL?.standardizedFileURL.path == pluginURL.standardizedFileURL.path, "should resolve global plugin install directory")

        let stockURL = PluginUninstallCleanup.globalInstallURL(
            pluginID: "linear",
            source: "stock:linear/openclaw.adapter.js",
            extensionsRoot: rootURL
        )
        expect(stockURL == nil, "should not resolve stock plugins for uninstall cleanup")

        let traversalURL = PluginUninstallCleanup.globalInstallURL(
            pluginID: "linear",
            source: "global:../linear/openclaw.adapter.js",
            extensionsRoot: rootURL
        )
        expect(traversalURL == nil, "should reject paths outside the global extensions root")

        let removedURL = try PluginUninstallCleanup.removeGlobalInstallDirectory(
            pluginID: "linear",
            source: "global:linear/openclaw.adapter.js",
            extensionsRoot: rootURL
        )
        expect(removedURL?.standardizedFileURL.path == pluginURL.standardizedFileURL.path, "should report removed directory")
        expect(!fileManager.fileExists(atPath: pluginURL.path), "should remove the global plugin directory")
        expect(fileManager.fileExists(atPath: siblingURL.path), "should not remove sibling plugin directories")

        print("Plugin uninstall cleanup verification passed")
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
    .appendingPathComponent("verify_plugin_uninstall_cleanup-\(UUID().uuidString)")
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
    fputs("FAIL: app sources + verify_plugin_uninstall_cleanup driver no longer compile\n", stderr)
    try? fm.removeItem(at: workDir)
    exit(1)
}
let status = run([binaryURL.path])
try? fm.removeItem(at: workDir)
exit(status)
