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
struct VerifySuperpowersPluginCatalog {
    static func main() throws {
        // Fixture catalog: the guard exercises PluginCatalogService's real
        // parsing of a recommended plugin without depending on the mutable
        // machine-local catalog clone in ~/.openclaw (whose data drifts).
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("catalog-fixture-\(UUID().uuidString)")
        let pluginDir = root.appendingPathComponent("plugins/superpowers")
        try fm.createDirectory(at: pluginDir.appendingPathComponent("assets"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let manifest = """
        {"id": "superpowers", "name": "Superpowers", "displayName": "Superpowers", "description": "Planning workflows", "version": "6.1.0", "recommended": true, "icon": "./assets/superpowers-small.svg", "category": "Developer Tools"}
        """
        try manifest.write(to: pluginDir.appendingPathComponent("openclaw.plugin.json"), atomically: true, encoding: .utf8)

        // recommended-status lives in the marketplace index, not the plugin manifest
        let marketplaceDir = root.appendingPathComponent(".agents/plugins")
        try fm.createDirectory(at: marketplaceDir, withIntermediateDirectories: true)
        let marketplace = """
        {"plugins": [{"id": "superpowers", "name": "superpowers", "path": "plugins/superpowers", "recommended": true, "order": 1}]}
        """
        try marketplace.write(to: marketplaceDir.appendingPathComponent("marketplace.json"), atomically: true, encoding: .utf8)
        try "svg".write(to: pluginDir.appendingPathComponent("assets/superpowers-small.svg"), atomically: true, encoding: .utf8)
        try "adapter".write(to: pluginDir.appendingPathComponent("openclaw.adapter.js"), atomically: true, encoding: .utf8)
        let packageManifest = """
        {"name": "superpowers", "version": "6.1.0", "openclaw": {"extensions": ["./openclaw.adapter.js"]}}
        """
        try packageManifest.write(to: pluginDir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let items = try PluginCatalogService.parseCatalog(rootURL: root)
        expect(items.count == 1, "fixture catalog should parse exactly one plugin item")
        guard let item = items.first else { return }

        expect(item.source == .recommend, "recommended:true manifests should map to the .recommend catalog section")
        expect(item.displayName == "Superpowers", "displayName should parse from the manifest")
        expect(item.version == "6.1.0", "version should parse from the manifest")
        expect(item.isOpenClawInstallable, "a plugin with an openclaw adapter should be OpenClaw installable")
        expect(item.iconURL?.lastPathComponent == "superpowers-small.svg", "relative icon paths should resolve to the plugin's asset")
        expect(item.relativePath == "plugins/superpowers", "relativePath should point at the plugin directory")

        print("Superpowers plugin catalog verification passed")
    }

    @discardableResult
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) -> Bool {
        if condition() { return true }
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

"""#

let fm = FileManager.default
let workDir = fm.temporaryDirectory
    .appendingPathComponent("verify_superpowers_plugin_catalog-\(UUID().uuidString)")
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
    fputs("FAIL: app sources + verify_superpowers_plugin_catalog driver no longer compile\n", stderr)
    try? fm.removeItem(at: workDir)
    exit(1)
}
let status = run([binaryURL.path])
try? fm.removeItem(at: workDir)
exit(status)
