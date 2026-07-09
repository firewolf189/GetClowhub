#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboardURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Features")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("DashboardView.swift")
let accessoryURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Features")
    .appendingPathComponent("Workspace")
    .appendingPathComponent("Views")
    .appendingPathComponent("Inspector")
    .appendingPathComponent("RightInspectorTitlebarAccessory.swift")

let dashboard = try String(contentsOf: dashboardURL, encoding: .utf8)
let rightInspectorTitlebarAccessory = try String(contentsOf: accessoryURL, encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fputs("FAIL: could not slice source between \(start) and \(end)\n", stderr)
        exit(1)
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let bodySource = slice(
    dashboard,
    from: "var body: some View",
    to: ".onAppear {"
)
let presentationRoot = slice(
    dashboard,
    from: "private var presentationRoot: some View",
    to: "private var appWorkspace: some View"
)
let openSettingsSource = slice(
    dashboard,
    from: "private func openSettingsSection",
    to: "private func preloadSettingsShortcutData"
)
let accessoryCoordinator = slice(
    rightInspectorTitlebarAccessory,
    from: "final class RightInspectorTitlebarAccessoryCoordinator",
    to: "struct RightInspectorTitlebarAccessory: View"
)
let accessoryUpdate = slice(
    accessoryCoordinator,
    from: "func update(",
    to: "func remove()"
)

require(
    dashboard.contains("private enum DashboardPresentationMode: Equatable") &&
        dashboard.contains("case app") &&
        dashboard.contains("case settings(SettingsPageSection)") &&
        dashboard.contains("var isSettingsPresented: Bool"),
    "Dashboard should model Settings as a top-level presentation route, not a loose boolean overlay."
)
require(
    dashboard.contains("private struct DashboardChromePolicy: Equatable") &&
        dashboard.contains("let showsTitlebarAccessory: Bool") &&
        dashboard.contains("let showsSessionToolbarTitle: Bool") &&
        dashboard.contains("let allowsAppOverlays: Bool") &&
        dashboard.contains("init(presentationMode: DashboardPresentationMode, isChatTabActive: Bool)"),
    "Dashboard chrome visibility should be centralized in one policy object."
)
require(
    dashboard.contains("@State private var presentationMode: DashboardPresentationMode = .app") &&
        !dashboard.contains("@State private var isSettingsPagePresented") &&
        !dashboard.contains("@State private var selectedSettingsSection"),
    "Dashboard should have one presentation state instead of separate Settings boolean and selected section state."
)
require(
    bodySource.contains("presentationRoot") &&
        !bodySource.contains("ZStack {\n            appWorkspace") &&
        presentationRoot.contains("if presentationMode.isSettingsPresented") &&
        presentationRoot.contains("SettingsShellView(") &&
        presentationRoot.contains("selectedSection: settingsSectionBinding") &&
        presentationRoot.contains("} else {\n            appWorkspace") &&
        bodySource.contains("isVisible: chromePolicy.showsTitlebarAccessory") &&
        bodySource.contains("RightInspectorTitlebarAccessoryInstaller(") &&
        bodySource.contains("if chromePolicy.showsSessionToolbarTitle") &&
        bodySource.contains("if chromePolicy.allowsAppOverlays"),
    "Dashboard should switch between Settings and app workspace as sibling presentation roots, so the app NavigationSplitView/sidebar chrome is not mounted behind Settings."
)
require(
    openSettingsSource.contains("presentationMode = .settings(section)") &&
        openSettingsSource.contains("presentationMode = .app") &&
        !openSettingsSource.contains("viewModel.selectedTab = .config") &&
        !openSettingsSource.contains("isSettingsPagePresented = true"),
    "Settings open/close should switch the presentation route, not the main sidebar tab or a boolean."
)
require(
    accessoryUpdate.contains("guard let targetWindow else { return }") &&
        !accessoryUpdate.contains("guard isVisible, let targetWindow else") &&
        accessoryUpdate.contains("applyVisibility(") &&
        accessoryUpdate.contains("targetWidth = isVisible ? max(width, 44) : 0") &&
        accessoryUpdate.contains("hostingController.view.isHidden = !isVisible"),
    "Titlebar accessory should remain installed while Settings is shown and only hide/collapse its view."
)
require(
    accessoryCoordinator.contains("func remove()") &&
        rightInspectorTitlebarAccessory.contains("static func dismantleNSView(_ nsView: NSView, coordinator: RightInspectorTitlebarAccessoryCoordinator)") &&
        rightInspectorTitlebarAccessory.contains("coordinator.remove()"),
    "Titlebar accessory removal should be reserved for representable teardown/window changes."
)

print("Settings presentation shell verification passed")
