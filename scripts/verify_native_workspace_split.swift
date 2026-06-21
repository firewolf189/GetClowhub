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
    "workspaceExpandedSidebar(width:",
    "DashboardView should pass the Outputs surface into the AppKit split container"
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
    "sidebarItem.animator().isCollapsed = !isSidebarExpanded",
    "AppKit split should own the right sidebar collapse animation"
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
    "right Outputs title and controls should be rendered by a titlebar accessory"
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
    "custom Outputs titlebar controls should live outside the inspector content"
)
assertContains(
    dashboard,
    "titlebarAccessoryWidthAdjustment",
    "right titlebar accessory width should share the Outputs layout metric contract"
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
assertContains(
    rightOutputsTitlebarAccessory,
    "Text(\"Outputs\")",
    "expanded Outputs title should live in the window titlebar accessory"
)
assertContains(
    rightOutputsTitlebarAccessory,
    "Image(systemName: \"sidebar.right\")",
    "Outputs titlebar accessory should use the standard right-sidebar icon"
)
assertContains(
    rightOutputsTitlebarAccessory,
    ".font(.system(size: 16, weight: .medium))",
    "right sidebar titlebar icon should visually match the system left-sidebar toolbar icon size"
)
assertContains(
    rightOutputsTitlebarAccessory,
    ".frame(width: 32, height: 32)",
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
