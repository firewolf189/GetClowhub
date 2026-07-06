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
let agentSectionContent = slice(
    dashboard,
    from: "private var agentSectionContent: some View",
    to: "// MARK: - Sidebar Bottom Bar"
)
let collapsedAgentsBlock = slice(
    agentSectionContent,
    from: "if !areAgentsCollapsed {",
    to: ".animation(.spring(response: 0.28, dampingFraction: 0.86), value: areAgentsCollapsed)"
)
// Agent session rows now expand/collapse inside SidebarCollapsibleRow.
// Ghosting during collapse is prevented by clipping the animated child
// block and the whole row container while using an identity removal transition.
let sidebarCollapsibleRow = slice(
    dashboard,
    from: "struct SidebarCollapsibleRow<Icon: View, Actions: View, Children: View>: View",
    to: "// MARK: - Pulsing Dot"
)
let collapsibleRowBody = slice(
    sidebarCollapsibleRow,
    from: "struct SidebarCollapsibleRow<Icon: View, Actions: View, Children: View>: View",
    to: "private var rowContent: some View"
)
let expandedChildrenBlock = slice(
    collapsibleRowBody,
    from: "if isExpanded {",
    to: ".animation(Self.expansionAnimation, value: isExpanded)"
)

assertContains(
    expandedChildrenBlock,
    ".transition(Self.childTransition)",
    "session rows should keep a soft insertion transition when expanding"
)
assertNotContains(
    sidebarCollapsibleRow,
    ".transition(.move(edge: .top).combined(with: .opacity))",
    "collapsing agent/project child rows must not move old titles during removal"
)
assertContains(
    sidebarCollapsibleRow,
    ".asymmetric(insertion: .opacity, removal: .identity)",
    "child rows should disappear immediately on collapse while keeping insertion soft"
)
assertContains(
    expandedChildrenBlock,
    ".clipped()",
    "collapsing agent session rows must clip the animated child block so old titles cannot ghost outside the row"
)
assertContains(
    collapsibleRowBody,
    ".animation(Self.expansionAnimation, value: isExpanded)",
    "expansion animation should be driven by the isExpanded state"
)
let afterAnimation = slice(
    collapsibleRowBody,
    from: ".animation(Self.expansionAnimation, value: isExpanded)",
    to: "}"
)
assertContains(
    afterAnimation,
    ".clipped()",
    "the whole collapsible row container must also be clipped during collapse to avoid ghosting"
)
assertContains(
    sidebarCollapsibleRow,
    ".clipped()",
    "collapsible rows should clip animated children during expand/collapse"
)
assertContains(
    collapsedAgentsBlock,
    ".transition(.asymmetric(insertion: .opacity, removal: .identity))",
    "collapsing the Agent section should not move old agent rows during removal"
)
assertContains(
    collapsedAgentsBlock,
    ".clipped()",
    "the whole Agent section list should clip during title-level collapse to avoid ghosting"
)
assertNotContains(
    agentSectionContent,
    ".transition(.move(edge: .top).combined(with: .opacity))",
    "Agent title collapse must not use a moving removal transition that can leave ghosted titles"
)

print("Agent session collapse ghosting checks passed")
