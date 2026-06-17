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
let dashboardRoot = slice(
    dashboard,
    from: "struct DashboardView: View",
    to: "// MARK: - Sidebar"
)
let sidebarBody = slice(
    dashboard,
    from: "var body: some View {",
    to: "// MARK: - Sidebar Top Header"
)
let agentSection = slice(
    dashboard,
    from: "private var agentSectionContent: some View",
    to: "// MARK: - Sidebar Bottom Bar"
)

assertContains(
    agentSection,
    "onRequestCreateAgent()",
    "Agent section header plus must request the root create-agent overlay"
)
assertContains(
    dashboardRoot,
    "isCreateAgentOverlayPresented",
    "Dashboard root must own create-agent overlay presentation state"
)
assertContains(
    dashboardRoot,
    "createAgentOverlay",
    "Dashboard root must host the create-agent overlay"
)
assertContains(
    dashboardRoot,
    "Color.black.opacity(isDark ?",
    "create-agent overlay must provide a transparent/dim outside-click layer"
)
assertContains(
    dashboardRoot,
    "dismissCreateAgentOverlay()",
    "clicking outside the create-agent panel must dismiss it"
)
assertContains(
    dashboardRoot,
    "CreateAgentSheet(",
    "create-agent overlay must present CreateAgentSheet"
)
assertContains(
    dashboardRoot,
    "viewModel.loadAvailableAgents()",
    "create-agent callback must refresh the dashboard agent list"
)
assertContains(
    dashboardRoot,
    "viewModel.selectedAgentId = agentId",
    "create-agent callback must select the newly created agent"
)
assertContains(
    dashboardRoot,
    "viewModel.selectedTab = .chat",
    "create-agent callback must switch the detail pane to chat"
)
assertContains(
    dashboardRoot,
    "expandedAgentIds.insert(agentId)",
    "create-agent callback must expand the newly created agent sessions"
)
assertNotContains(
    sidebarBody,
    #".sheet(isPresented: $showCreateAgentSheet)"#,
    "active SidebarView body must not use a system sheet for create-agent"
)

print("Agent sidebar create overlay verification passed")
