#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fputs("FAIL: could not read \(path)\n", stderr)
        exit(1)
    }
    return text
}

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

let dashboard = read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let settingsPanel = read("OpenClawInstaller/Features/Settings/Shortcut/SettingsShortcutPanel.swift")
let settingsMenu = read("OpenClawInstaller/Features/Settings/Shortcut/SettingsShortcutMenu.swift")
let settingsRows = read("OpenClawInstaller/Features/Settings/Shortcut/SettingsShortcutRows.swift")
let settingsStyle = read("OpenClawInstaller/Features/Settings/Shortcut/SettingsShortcutStyle.swift")
let settingsShortcutSource = settingsPanel + settingsMenu + settingsRows + settingsStyle

let bottomBar = slice(
    dashboard,
    from: "private var sidebarBottomBar: some View",
    to: "// MARK: - Agents List"
)

require(
    bottomBar.contains("SettingsShortcutPanelButton(") &&
        !bottomBar.contains("SettingsShortcutPanelHost(") &&
        !bottomBar.contains("SettingsShortcutMenu("),
    "Dashboard sidebar bottom bar should only compose the extracted Settings shortcut button."
)

require(
    !dashboard.contains("private struct SettingsShortcutPanelHost") &&
        !dashboard.contains("private final class SettingsShortcutPanelCoordinator") &&
        !dashboard.contains("private struct SettingsShortcutMenu: View"),
    "Settings shortcut panel internals should be extracted out of DashboardView.swift."
)

require(
    !settingsPanel.contains(".popover(isPresented:"),
    "Settings shortcut should not use SwiftUI popover because it renders the unwanted arrow."
)

let panelHost = slice(
    settingsPanel,
    from: "private struct SettingsShortcutPanelHost",
    to: "private final class SettingsShortcutPanelCoordinator"
)

let panelCoordinator = slice(
    settingsPanel,
    from: "private final class SettingsShortcutPanelCoordinator",
    to: "    private func constrainedPanelHeight(for contentHeight: CGFloat)"
)

require(
    panelHost.contains("NSViewRepresentable") &&
        panelCoordinator.contains("NSPanel(") &&
        panelCoordinator.contains("styleMask: [.borderless, .nonactivatingPanel]") &&
        panelCoordinator.contains("panel.backgroundColor = .clear") &&
        panelCoordinator.contains("panel.appearance = NSAppearance(named: .aqua)") &&
        panelCoordinator.contains("DispatchQueue.main.async"),
    "Settings shortcut panel should use a small AppKit bridge with deferred presentation and a stable light appearance."
)

require(
    panelCoordinator.contains("panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor") &&
        panelCoordinator.contains("panel.contentView?.layer?.masksToBounds = false"),
    "Settings shortcut NSPanel content view must stay transparent so no rectangular host background appears around the rounded card."
)

require(
    panelCoordinator.contains("panelFrame(relativeTo sourceView: NSView)") &&
        panelCoordinator.contains("window.convertToScreen") &&
        panelCoordinator.contains("windowFrameOnScreen") &&
        panelCoordinator.contains("availableHeight") &&
        !panelCoordinator.contains("sidebarMaxX"),
    "Settings shortcut panel should anchor above the Settings button and constrain height inside the app window."
)

let menuBody = slice(
    settingsMenu,
    from: "var body: some View",
    to: "    @ViewBuilder"
)

require(
    menuBody.contains(".background(SettingsShortcutLiquidDropBackground(cornerRadius: SettingsShortcutPanelMetrics.cornerRadius))") &&
        menuBody.contains(".clipShape(SettingsShortcutPanelMetrics.panelShape)") &&
        menuBody.contains(".compositingGroup()") &&
        menuBody.range(of: ".background(SettingsShortcutLiquidDropBackground")!.lowerBound <
            menuBody.range(of: ".clipShape(SettingsShortcutPanelMetrics.panelShape)")!.lowerBound,
    "Settings shortcut glass background must be clipped by the same rounded shape as the content."
)

require(
    settingsStyle.contains("enum SettingsShortcutPanelMetrics") &&
        settingsStyle.contains("static let width: CGFloat = 280") &&
        settingsStyle.contains("static let cornerRadius: CGFloat = 18") &&
        settingsStyle.contains("static let maxHeight: CGFloat = 240"),
    "Settings shortcut panel metrics should centralize the compact rounded glass menu frame."
)

require(
    settingsStyle.contains("RadialGradient") &&
        settingsStyle.contains(".blendMode(.plusLighter)") &&
        settingsStyle.contains(".strokeBorder") &&
        settingsStyle.contains("SettingsShortcutLiquidDropBackground") &&
        settingsStyle.contains(".fill(.ultraThinMaterial)") &&
        settingsStyle.contains("SettingsShortcutColors.glassBase") &&
        settingsStyle.contains("SettingsShortcutColors.glassHighlight") &&
        settingsStyle.contains("SettingsShortcutColors.glassShadow"),
    "Settings shortcut background should use a balanced liquid-glass base, visible border, and soft neutral shadow."
)

require(
    !settingsShortcutSource.contains("Color.black.opacity") &&
        !settingsShortcutSource.contains("controlBackgroundColor") &&
        !settingsShortcutSource.contains("Color.white.opacity(0.82)"),
    "Settings shortcut glass should avoid dark overlays, system control backgrounds, and heavy white overlays that destroy contrast."
)

require(
    settingsStyle.contains("enum SettingsShortcutColors") &&
        settingsStyle.contains("static let primaryText = SwiftUI.Color(red:") &&
        settingsStyle.contains("static let secondaryText = SwiftUI.Color(red:") &&
        settingsStyle.contains("static let tertiaryText = SwiftUI.Color(red:") &&
        settingsMenu.contains(".foregroundStyle(SettingsShortcutColors.primaryText)") &&
        settingsRows.contains("case .normal: return SettingsShortcutColors.primaryText") &&
        settingsRows.contains("SettingsShortcutColors.secondaryText"),
    "Settings shortcut content should set explicit readable foreground colors instead of relying on material vibrancy."
)

print("Settings shortcut panel verification passed")
