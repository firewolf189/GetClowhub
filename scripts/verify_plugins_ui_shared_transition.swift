import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let pluginsViewURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("PluginsTabView.swift")

let pluginsView = try String(contentsOf: pluginsViewURL, encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

require(
    pluginsView.contains("@Namespace private var pluginDetailNamespace"),
    "Plugins UI should define a namespace for shared element transitions."
)
require(
    pluginsView.contains("private let pluginDetailAnimation"),
    "Plugins UI should centralize a spring animation for opening and closing details."
)
require(
    pluginsView.contains("withAnimation(pluginDetailAnimation)"),
    "Plugins UI should open and close plugin details with the shared spring animation."
)
require(
    pluginsView.contains(".matchedGeometryEffect(id: \"plugin-card-\\(geometryID)\""),
    "Plugin rows and the detail sheet should share a card geometry id."
)
require(
    pluginsView.contains(".matchedGeometryEffect(id: \"plugin-icon-\\(geometryID)\""),
    "Plugin rows and the detail sheet should share an icon geometry id."
)
require(
    pluginsView.contains(".matchedGeometryEffect(id: \"plugin-title-\\(geometryID)\""),
    "Plugin rows and the detail sheet should share a title geometry id."
)
require(
    pluginsView.contains("namespace: pluginDetailNamespace"),
    "Plugin rows and detail sheets should receive the shared namespace from PluginsTabView."
)
require(
    pluginsView.contains("private var detailBackdropOpacity"),
    "Plugin detail overlay should use an explicit backdrop opacity instead of an invisible click layer."
)
require(
    pluginsView.contains("private var detailCardBackground"),
    "Plugin detail overlay should use an opaque card background so list text does not show through."
)
require(
    !pluginsView.contains(".fill(.regularMaterial)"),
    "Plugin detail overlay should not use regularMaterial because it lets the plugin list show through."
)
require(
    !pluginsView.contains(".opacity(0.001)"),
    "Plugin detail overlay should not use an effectively invisible backdrop."
)

print("Plugins shared transition verification passed")
