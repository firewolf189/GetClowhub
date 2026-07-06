import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ relativePath: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw NSError(domain: "verify_plugin_refresh_and_shared_shimmer", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

do {
    let service = try read("OpenClawInstaller/Features/Plugins/Services/PluginCatalogService.swift")
    try require(service.contains("git -C \\(cachePath) pull --ff-only"), "plugin catalog refresh should use fast-forward pull for existing caches")
    try require(!service.contains("reset --hard"), "plugin catalog refresh should not force reset local catalog cache")
    try require(!service.contains("clean -fd"), "plugin catalog refresh should not clean local catalog cache files")

    let sharedPath = "OpenClawInstaller/DesignSystem/Components/ShimmeringStatusText.swift"
    let shared = try read(sharedPath)
    try require(shared.contains("struct ShimmeringStatusText: View"), "shared shimmer component should exist in Views/Shared")
    try require(shared.contains("LinearGradient"), "shared shimmer component should implement the moving highlight")
    try require(shared.contains("repeatForever"), "shared shimmer component should animate continuously")

    let workStatus = try read("OpenClawInstaller/Features/Chat/Views/WorkStatusHeader.swift")
    try require(workStatus.contains("ShimmeringStatusText("), "WorkStatusHeader should reuse the shared shimmer component")
    try require(!workStatus.contains("private struct ShimmeringWorkStatusText"), "WorkStatusHeader should not keep a private duplicate shimmer component")

    let pluginsView = try read("OpenClawInstaller/Features/Plugins/Views/PluginsTabView.swift")
    try require(pluginsView.contains("ShimmeringStatusText("), "Plugins installing state should reuse the shared shimmer component")
    try require(pluginsView.contains("catalog.action.installing"), "Plugins installing state should keep localized installing text")

    let project = try read("OpenClawInstaller.xcodeproj/project.pbxproj")
    try require(project.contains("ShimmeringStatusText.swift in Sources"), "Xcode project should compile the shared shimmer component")
    try require(project.contains("ShimmeringStatusText.swift"), "Xcode project should list the shared shimmer file")

    print("PASS plugin refresh sync and shared shimmer checks")
} catch {
    fputs("FAIL: \(error.localizedDescription)\n", stderr)
    exit(1)
}
