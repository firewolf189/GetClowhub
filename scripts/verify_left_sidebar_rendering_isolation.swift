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

let dashboard = read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let viewModel = read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")

let dashboardRoot = slice(dashboard, from: "struct DashboardView: View", to: "// MARK: - Sidebar")
let sidebarView = slice(dashboard, from: "struct SidebarView: View", to: "// MARK: - Pulsing Dot")
let deleteSession = slice(viewModel, from: "func deleteSession(_ sessionId: UUID)", to: "/// Toggle pinned state")

assertContains(
    dashboard,
    "struct DashboardSidebarState: Equatable",
    "left sidebar should receive an equatable render projection instead of the full DashboardViewModel"
)
assertContains(
    dashboard,
    "struct DashboardSidebarActions",
    "left sidebar should receive narrow action closures instead of mutating DashboardViewModel directly"
)
assertContains(
    dashboardRoot,
    "private var sidebarState: DashboardSidebarState",
    "DashboardView should build a narrow sidebar projection at the root boundary"
)
assertContains(
    dashboardRoot,
    "private var sidebarActions: DashboardSidebarActions",
    "DashboardView should route sidebar interactions through narrow closures"
)
assertNotContains(
    dashboardRoot,
    "@State private var expandedAgentIds",
    "agent expansion is sidebar-local UI state and should not live in DashboardView"
)
assertContains(
    dashboardRoot,
    "SidebarView(\n                state: sidebarState,\n                actions: sidebarActions,",
    "DashboardView should pass state/actions into SidebarView instead of the whole model"
)
assertNotContains(
    sidebarView,
    "@ObservedObject var viewModel: DashboardViewModel",
    "SidebarView should not observe the entire DashboardViewModel"
)
assertNotContains(
    sidebarView,
    "@Binding var expandedAgentIds",
    "SidebarView should own agent expansion locally"
)
assertContains(
    sidebarView,
    "@State private var expandedAgentIds: Set<String> = []",
    "SidebarView should keep agent expansion as local UI state"
)
for forbidden in [
    "viewModel.deleteSession(",
    "viewModel.archiveSession(",
    "viewModel.togglePinSession(",
    "viewModel.switchSession(",
    "viewModel.switchSessionGlobally(",
    "viewModel.createNewSession(",
    "viewModel.toggleProjectCollapse(",
    "viewModel.removeProject(",
    "viewModel.openProject("
] {
    assertNotContains(
        sidebarView,
        forbidden,
        "SidebarView should route actions through DashboardSidebarActions, found direct model call: \(forbidden)"
    )
}
assertContains(
    deleteSession,
    "guard wasActive else {",
    "deleting a non-active session should return before promoting or touching chatMessagesByAgent"
)
let nonActiveDeletePath = slice(deleteSession, from: "guard wasActive else {", to: "promoteNextSession")
assertContains(
    nonActiveDeletePath,
    "rebuildSessionsMirror()",
    "non-active delete should refresh only session metadata/sidebar state"
)
assertNotContains(
    nonActiveDeletePath,
    "chatMessagesByAgent",
    "non-active delete should not mutate chatMessagesByAgent"
)
