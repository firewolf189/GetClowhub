import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ relativePath: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw NSError(domain: "verify_recommended_plugin_bootstrap", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

do {
    let catalogResource = root.appendingPathComponent("OpenClawInstaller/Resources/BundledPluginCatalog")
    try require(FileManager.default.fileExists(atPath: catalogResource.appendingPathComponent(".agents/plugins/marketplace.json").path), "bundled plugin catalog should include marketplace manifest")
    try require(FileManager.default.fileExists(atPath: catalogResource.appendingPathComponent("plugins/context-mode/openclaw.plugin.json").path), "bundled plugin catalog should include recommended plugin files")

    let service = try read("OpenClawInstaller/Services/PluginCatalogService.swift")
    try require(service.contains("bundledCatalogURL"), "PluginCatalogService should expose a bundled catalog URL")
    try require(service.contains("seedBundledCatalogIfNeeded"), "PluginCatalogService should seed the local catalog cache from bundled resources")
    try require(service.contains("BundledPluginCatalog"), "PluginCatalogService should look for the BundledPluginCatalog resource")
    try require(service.contains("fileExists(atPath: cacheURL.path)"), "bundled catalog seeding should only run when the user cache is missing")

    let bootstrapper = try read("OpenClawInstaller/Services/RecommendedPluginBootstrapper.swift")
    try require(bootstrapper.contains("final class RecommendedPluginBootstrapper"), "recommended plugin bootstrapper should exist")
    try require(bootstrapper.contains("getclowhub-recommended-plugins-bootstrap.json"), "recommended plugin bootstrapper should write a marker file")
    try require(bootstrapper.contains("PluginCatalogService.seedBundledCatalogIfNeeded"), "recommended plugin bootstrapper should prepare the local plugin catalog before installing")
    try require(bootstrapper.contains("PluginCatalogService.parseCatalog"), "recommended plugin bootstrapper should read catalog entries through the catalog service")
    try require(bootstrapper.contains("catalog.filter(\\.isRecommended)"), "recommended plugin bootstrapper should install only recommended plugins")
    try require(bootstrapper.contains("PluginListParser.parse"), "recommended plugin bootstrapper should reuse the plugin list parser")
    try require(bootstrapper.contains("openclaw plugins list"), "recommended plugin bootstrapper should inspect installed plugins before installing")
    try require(bootstrapper.contains("PluginCatalogService.installCommand"), "recommended plugin bootstrapper should install missing recommended plugins through the shared OpenClaw install command")
    try require(!bootstrapper.contains("plugins enable"), "recommended plugin bootstrapper should not change enabled plugin state")
    try require(!bootstrapper.contains("plugins disable"), "recommended plugin bootstrapper should not change disabled plugin state")

    let dashboard = try read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
    try require(dashboard.contains("RecommendedPluginBootstrapper"), "DashboardView should hold a recommended plugin bootstrapper")
    try require(dashboard.contains("bootstrapRecommendedPluginsIfNeeded"), "DashboardView should trigger recommended plugin bootstrap when OpenClaw is running")

    let project = try read("OpenClawInstaller.xcodeproj/project.pbxproj")
    try require(project.contains("BundledPluginCatalog in Resources"), "Xcode project should bundle the plugin catalog folder")
    try require(project.contains("RecommendedPluginBootstrapper.swift in Sources"), "Xcode project should compile the recommended plugin bootstrapper")

    print("PASS recommended plugin bootstrap checks")
} catch {
    fputs("FAIL: \(error.localizedDescription)\n", stderr)
    exit(1)
}
