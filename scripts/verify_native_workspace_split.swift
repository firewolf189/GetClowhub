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
let dashboardView = slice(dashboard, from: "struct DashboardView: View", to: "// MARK: - Sidebar")
let detailContentView = slice(dashboard, from: "struct DetailContentView: View", to: "// MARK: - Collab Drag Handle")

assertContains(
    dashboardView,
    "} content: {\n            DetailContentView(",
    "root DashboardView should use a three-column NavigationSplitView content column for the main pane"
)
assertContains(
    dashboardView,
    "} detail: {\n            workspaceSplitColumn",
    "root DashboardView should render the workspace as the trailing NavigationSplitView detail column"
)
assertContains(
    dashboardView,
    "private var workspaceSplitColumn: some View",
    "workspace trailing column should be owned by DashboardView instead of DetailContentView"
)
assertContains(
    dashboardView,
    "ToolbarItem(placement: .navigation)",
    "conversation title should move into the window toolbar near the system left-sidebar button"
)
assertContains(
    dashboardView,
    ".allowsHitTesting(false)",
    "conversation title should render as plain non-interactive titlebar text without a toolbar hover pill"
)
assertNotContains(
    dashboardView,
    "ToolbarItem(placement: .primaryAction)",
    "workspace toggle should not live in the global toolbar because macOS places it beside the conversation title"
)
assertContains(
    dashboardView,
    "DashboardTitlebarAccessoryInstaller(",
    "workspace titlebar controls should be installed as a trailing titlebar accessory"
)
assertContains(
    dashboardView,
    "RightOutputsTitlebarAccessory(",
    "workspace titlebar accessory should render the right-column Outputs controls"
)
assertContains(
    dashboard,
    "private struct DashboardTitlebarAccessoryInstaller<Accessory: View>: NSViewRepresentable",
    "right-column header controls should use a narrow AppKit titlebar bridge"
)
assertContains(
    dashboard,
    "window.titlebarAccessoryViewControllers",
    "titlebar accessory bridge should install into the existing window header"
)
assertContains(
    dashboard,
    ".frame(maxHeight: .infinity)",
    "right-column divider should be rendered in the titlebar accessory so it visually continues the split boundary"
)
assertContains(
    dashboardView,
    "Self.workspaceLayoutMetrics.titlebarAccessoryWidthAdjustment",
    "right-column titlebar accessory should compensate for the system split column's visible width"
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

print("Native workspace split source verification passed")
