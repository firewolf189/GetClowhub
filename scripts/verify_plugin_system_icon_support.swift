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
struct VerifyPluginSystemIconSupport {
    static func main() throws {
        let projectURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let catalogURL = URL(fileURLWithPath: NSString("~/.openclaw/getclowhub-plugins-catalog").expandingTildeInPath)

        let itemModel = try read(projectURL.appendingPathComponent("OpenClawInstaller/Models/PluginCatalogItem.swift"))
        expect(itemModel.contains("let systemIconName: String?"), "PluginCatalogItem should store a system icon name")

        let catalogService = try read(projectURL.appendingPathComponent("OpenClawInstaller/Services/PluginCatalogService.swift"))
        expect(catalogService.contains("let systemIcon: String?"), "OpenClawPluginManifest should decode systemIcon")
        expect(catalogService.contains("systemIconName:"), "PluginCatalogService should pass systemIcon into PluginCatalogItem")
        expect(catalogService.contains("forKey: .systemIcon"), "OpenClawPluginManifest should read the systemIcon JSON key")

        let pluginsView = try read(projectURL.appendingPathComponent("OpenClawInstaller/Views/Dashboard/Plugins/PluginsTabView.swift"))
        expect(pluginsView.contains("systemIconName: item.systemIconName"), "catalog rows should pass systemIconName to PluginCatalogIcon")
        expect(pluginsView.contains("systemIconName: catalogItem?.systemIconName"), "installed rows should pass catalog systemIconName to PluginCatalogIcon")
        expect(pluginsView.contains("Image(systemName: systemIconName)"), "PluginCatalogIcon should render SF Symbols before file icons")

        // Behavioral check with a fixture manifest instead of asserting the
        // mutable machine-local catalog clone: a manifest declaring both
        // systemIcon and a file icon must surface systemIconName while
        // still resolving the SVG for older app versions.
        let fm = FileManager.default
        let fixtureRoot = fm.temporaryDirectory.appendingPathComponent("icon-fixture-\(UUID().uuidString)")
        let fixturePlugin = fixtureRoot.appendingPathComponent("plugins/context-mode")
        try fm.createDirectory(at: fixturePlugin.appendingPathComponent("assets"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: fixtureRoot) }
        let fixtureManifest = """
        {"id": "context-mode", "name": "Context Mode", "description": "d", "version": "1.0.0", "systemIcon": "rectangle.compress.vertical", "icon": "./assets/context-mode.svg"}
        """
        try fixtureManifest.write(to: fixturePlugin.appendingPathComponent("openclaw.plugin.json"), atomically: true, encoding: .utf8)
        try "svg".write(to: fixturePlugin.appendingPathComponent("assets/context-mode.svg"), atomically: true, encoding: .utf8)
        let fixtureItems = try PluginCatalogService.parseCatalog(rootURL: fixtureRoot)
        guard let fixtureItem = fixtureItems.first else {
            expect(false, "fixture catalog with systemIcon manifest should parse")
            return
        }
        expect(fixtureItem.systemIconName == "rectangle.compress.vertical", "systemIcon manifests should surface systemIconName on the catalog item")
        expect(fixtureItem.iconURL?.lastPathComponent == "context-mode.svg", "manifests with both icons should still resolve the SVG for older app versions")

        print("Plugin system icon support verification passed")
    }

    private static func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
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
    .appendingPathComponent("verify_plugin_system_icon_support-\(UUID().uuidString)")
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
    fputs("FAIL: app sources + verify_plugin_system_icon_support driver no longer compile\n", stderr)
    try? fm.removeItem(at: workDir)
    exit(1)
}
let status = run([binaryURL.path])
try? fm.removeItem(at: workDir)
exit(status)
