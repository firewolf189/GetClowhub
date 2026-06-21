import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let pluginsViewURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("PluginsTabView.swift")
let dashboardViewURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("DashboardView.swift")

let pluginsView = try String(contentsOf: pluginsViewURL, encoding: .utf8)
let dashboardView = try String(contentsOf: dashboardViewURL, encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

require(
    dashboardView.contains("@Namespace private var pluginDetailNamespace"),
    "DashboardView should own the plugin detail namespace so the overlay is not constrained by the Plugins scroll view."
)
require(
    dashboardView.contains("@State private var selectedPluginDetailItem: PluginDetailPresentationItem?"),
    "DashboardView should own the selected plugin detail item like it owns selected skill details."
)
require(
    dashboardView.contains("private let pluginDetailAnimation"),
    "DashboardView should centralize the plugin detail spring animation."
)
require(
    dashboardView.contains("withAnimation(pluginDetailAnimation)"),
    "DashboardView should open and close plugin details with the shared spring animation."
)
require(
    dashboardView.contains("onOpenPluginDetail: presentPluginDetail"),
    "DashboardView should route plugin row clicks into the global plugin detail presenter."
)
require(
    dashboardView.contains("if let selectedPluginDetailItem, activeTab == .plugins"),
    "DashboardView should render the plugin detail overlay at the app overlay level."
)
require(
    dashboardView.contains("private func pluginDetailOverlay(for item: PluginDetailPresentationItem)"),
    "DashboardView should implement the plugin detail overlay beside the skill detail overlay."
)
require(
    dashboardView.contains("PluginCatalogDetailSheet("),
    "DashboardView should host the plugin detail sheet."
)
require(
    dashboardView.contains(".background(.regularMaterial)") || dashboardView.contains(".fill(.regularMaterial)"),
    "Plugin detail overlay should match the Skills detail material background."
)
require(
    pluginsView.contains("let pluginDetailNamespace: Namespace.ID"),
    "PluginsTabView should receive the shared namespace from DashboardView."
)
require(
    pluginsView.contains("let onOpenPluginDetail: (PluginDetailPresentationItem) -> Void"),
    "PluginsTabView should emit detail presentation items instead of owning the overlay."
)
require(
    pluginsView.contains(".matchedGeometryEffect(id: \"plugin-card-\\(geometryID)\""),
    "Plugin rows and the detail sheet should share a card geometry id."
)
require(
    dashboardView.contains(".matchedGeometryEffect(\n                            id: \"plugin-card-\\(item.id)\""),
    "The global plugin detail overlay should provide the card geometry destination."
)
require(
    !pluginsView.contains("plugin-icon-\\(geometryID)"),
    "Plugin icon should not use matchedGeometryEffect because it leaves a visible ghost inside the detail sheet."
)
require(
    !pluginsView.contains("plugin-title-\\(geometryID)"),
    "Plugin title should not use matchedGeometryEffect because the Skills sheet keeps title layout local to the sheet."
)
require(
    pluginsView.contains("namespace: pluginDetailNamespace"),
    "Plugin rows should receive the shared namespace from DashboardView."
)
require(
    !dashboardView.contains("Color(NSColor.windowBackgroundColor).opacity"),
    "Plugin detail overlay should not add an extra translucent color layer over the Skills-style material card."
)
require(
    !pluginsView.contains("@State private var selectedDetailItem"),
    "PluginsTabView should not own selected detail state."
)
require(
    !pluginsView.contains("private var detailOverlay"),
    "PluginsTabView should not render the plugin detail overlay inside the scroll view."
)
require(
    !pluginsView.contains("detailBackdropOpacity"),
    "PluginsTabView should not carry overlay backdrop styling."
)

print("Plugins shared transition verification passed")
