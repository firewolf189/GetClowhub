import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func assertContains(_ haystack: String, _ needle: String, _ message: String) {
    guard haystack.contains(needle) else {
        fatalError(message)
    }
}

func assertNotContains(_ haystack: String, _ needle: String, _ message: String) {
    guard !haystack.contains(needle) else {
        fatalError(message)
    }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")
let dashboardView = slice(dashboard, from: "struct DashboardView: View", to: "// MARK: - Sidebar")
let detailContentView = slice(dashboard, from: "struct DetailContentView: View", to: "// MARK: - Collab Drag Handle")

assertContains(
    dashboardView,
    "} detail: {\n            DashboardWorkspaceSplitView(",
    "root DashboardView should still use the left system NavigationSplitView sidebar and place an AppKit split in detail"
)
assertContains(
    dashboardView,
    "DashboardWorkspaceSplitView(",
    "right Outputs column should be owned by an AppKit split container"
)
assertContains(
    dashboardView,
    "workspaceSidebarPane(width:",
    "DashboardView should pass the unified Outputs pane into the AppKit split container"
)
assertNotContains(
    dashboardView,
    ".inspector(isPresented:",
    "right Outputs column should not use SwiftUI inspector when using the AppKit split approach"
)
assertNotContains(
    dashboardView,
    ".inspectorColumnWidth(",
    "right Outputs sizing should be handled by the AppKit split controller"
)
assertNotContains(
    dashboardView,
    "} content: {",
    "root DashboardView should not keep a three-column NavigationSplitView content column for Outputs"
)
assertNotContains(
    dashboardView,
    "private var workspaceSplitColumn: some View",
    "Outputs should no longer be rendered as a manual trailing NavigationSplitView column"
)
assertContains(
    dashboard,
    "private struct DashboardWorkspaceSplitView<Content: View, Sidebar: View>: NSViewControllerRepresentable",
    "right Outputs column should be bridged through an AppKit split view"
)
assertContains(
    dashboard,
    "private final class DashboardWorkspaceSplitController: NSSplitViewController",
    "right Outputs column should be managed by NSSplitViewController"
)
assertContains(
    dashboard,
    "private let sidebarAnimationDuration: TimeInterval = 0.22",
    "right split and titlebar accessory should share one animation duration"
)
assertContains(
    dashboard,
    "splitView.animator().setPosition",
    "AppKit split should animate the divider position instead of jumping collapsed state"
)
assertContains(
    dashboard,
    "sidebarItem.canCollapse = true",
    "right AppKit split item should be allowed to fully collapse after the divider animation"
)
assertContains(
    dashboard,
    "sidebarItem.isCollapsed = true",
    "right AppKit split item should fully collapse so no empty trailing strip remains"
)
assertContains(
    dashboard,
    "widthConstraint?.animator().constant",
    "right titlebar accessory bridge should update its AppKit width constraint through animation"
)
assertContains(
    dashboard,
    "height: CGFloat = 44",
    "right titlebar accessory should occupy the full toolbar row height"
)
assertContains(
    dashboardView,
    "ToolbarItem(placement: .navigation)",
    "conversation title should move into the window toolbar near the system left-sidebar button"
)
assertNotContains(
    dashboardView,
    "ToolbarItem(placement: .primaryAction)",
    "right Outputs controls should not use the main toolbar primaryAction placement"
)
assertContains(
    dashboardView,
    "DashboardTitlebarAccessoryInstaller(",
    "right Outputs controls should be installed into the window titlebar"
)
assertContains(
    dashboardView,
    "RightOutputsTitlebarAccessory(",
    "right Outputs toggle should be rendered by a titlebar accessory"
)
assertContains(
    dashboard,
    "private struct DashboardTitlebarAccessoryInstaller",
    "DashboardView should keep a narrow AppKit bridge for titlebar-only Outputs controls"
)
assertContains(
    dashboard,
    "window.titlebarAccessoryViewControllers",
    "titlebar accessory bridge should install into the existing window header"
)
assertContains(
    dashboard,
    "private struct RightOutputsTitlebarAccessory",
    "custom Outputs titlebar toggle should live outside the inspector content"
)
assertNotContains(
    dashboard,
    "titlebarAccessoryWidthAdjustment",
    "right titlebar accessory must not share the Outputs pane width metric"
)
assertContains(
    dashboard,
    "private var rightTitlebarAccessoryWidth: CGFloat {\n        guard isChatTabActive else { return 0 }\n        return 44\n    }",
    "right titlebar accessory should stay as a fixed toolbar toggle width"
)
assertContains(
    detailContentView,
    "let workspaceSidebarController: WorkspaceSidebarController",
    "DetailContentView should receive workspace control state from the root shell"
)
assertContains(
    detailContentView,
    ".environment(\\.workspaceSidebarController, workspaceSidebarController)",
    "ChatView should continue receiving the workspace sidebar controller"
)
assertNotContains(
    detailContentView,
    "workspaceSidebarColumn(width:",
    "DetailContentView should not embed the workspace sidebar inside the main content HStack"
)
assertNotContains(
    detailContentView,
    "private var conversationHeader: some View",
    "conversation header should not occupy vertical space inside the main content pane"
)

let workspaceFilePanel = slice(dashboard, from: "private struct WorkspaceFilePanel: View", to: "    private var outputsEmptyState: some View")
assertNotContains(
    workspaceFilePanel,
    "Text(\"Outputs\")",
    "WorkspaceFilePanel should not create its own Outputs header; the title belongs to the existing window header"
)
assertNotContains(
    workspaceFilePanel,
    "Image(systemName: \"tray.full.fill\")",
    "WorkspaceFilePanel should not duplicate the Outputs titlebar icon inside the content column"
)
assertContains(
    dashboard,
    "private func workspaceSidebarPane(width: CGFloat) -> some View",
    "right Outputs header and content should live in one AppKit split pane"
)
let workspaceSidebarPane = slice(dashboard, from: "private func workspaceSidebarPane(width: CGFloat) -> some View", to: "    private func workspaceExpandedSidebar")
assertContains(
    workspaceSidebarPane,
    "WorkspaceOutputsPaneHeader(",
    "right split pane should own the Outputs header row"
)
assertContains(
    workspaceSidebarPane,
    "workspaceExpandedSidebar(width: width)",
    "right split pane should own the Outputs file content"
)

assertNotContains(
    dashboard,
    "private var workspaceInspectorContent: some View",
    "AppKit split mode should not keep a SwiftUI inspector content wrapper"
)
assertNotContains(
    dashboard,
    "WorkspaceInspectorHeader(",
    "right sidebar content should not create its own header row"
)

let rightOutputsTitlebarAccessory = slice(dashboard, from: "private struct RightOutputsTitlebarAccessory: View", to: "// MARK: - Sidebar")
assertNotContains(
    rightOutputsTitlebarAccessory,
    "Text(\"Outputs\")",
    "window titlebar accessory should stay as a fixed toggle, not a second resizing Outputs header"
)
assertContains(
    rightOutputsTitlebarAccessory,
    "Image(systemName: \"sidebar.right\")",
    "Outputs titlebar accessory should use the standard right-sidebar icon"
)
assertContains(
    rightOutputsTitlebarAccessory,
    ".font(.system(size: 18, weight: .medium))",
    "right sidebar titlebar icon should visually match the system left-sidebar toolbar icon size"
)
assertContains(
    rightOutputsTitlebarAccessory,
    ".frame(width: 34, height: 34)",
    "right sidebar titlebar icon should use the same apparent button footprint as the left toolbar icon"
)
assertNotContains(
    rightOutputsTitlebarAccessory,
    "Image(systemName: \"xmark\")",
    "Outputs titlebar accessory should not use a generic close icon for sidebar collapse"
)

assertContains(
    project,
    "MACOSX_DEPLOYMENT_TARGET = 14.0;",
    "macOS deployment target should stay at the current project baseline"
)
assertNotContains(
    project,
    "MACOSX_DEPLOYMENT_TARGET = 13.0;",
    "macOS 13 deployment target should be removed when using SwiftUI inspector"
)

print("Native workspace split source verification passed")
