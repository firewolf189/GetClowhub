import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboardURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/DashboardView.swift")

guard let dashboard = try? String(contentsOf: dashboardURL, encoding: .utf8) else {
    fatalError("Could not read DashboardView.swift")
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

func slice(_ haystack: String, from start: String, toAny ends: [String]) -> String {
    guard let startRange = haystack.range(of: start) else {
        fatalError("Could not find slice start \(start)")
    }

    for end in ends {
        if let endRange = haystack[startRange.upperBound...].range(of: end) {
            return String(haystack[startRange.lowerBound..<endRange.lowerBound])
        }
    }

    fatalError("Could not slice source from \(start) to any expected end")
}

let sidebarView = slice(
    dashboard,
    from: "struct SidebarView: View",
    to: "struct SidebarCollapsibleRow"
)

let mainList = slice(
    sidebarView,
    from: "private var sidebarMainList: some View",
    to: "private func navRow"
)

let navRow = slice(
    sidebarView,
    from: "private func navRow",
    to: "private func sidebarRowContent"
)

let agentRow = slice(
    sidebarView,
    from: "private func agentSidebarRow",
    toAny: [
        "private func sidebarItemHighlightColor",
        "private func sidebarAgentHighlightColor"
    ]
)

assertContains(sidebarView, "@State private var hoveredSidebarTab", "Sidebar nav rows should track hover state")
assertContains(sidebarView, "@State private var hoveredSidebarAction", "Special sidebar actions should track hover state")
assertContains(sidebarView, "private enum SidebarChromeAction", "Special sidebar actions should use a typed hover key")
assertContains(sidebarView, "private func sidebarItemHighlightColor", "Sidebar highlight color should be shared")
assertNotContains(sidebarView, "sidebarAgentHighlightColor", "Agent-only highlight helper should be replaced by a shared helper")

assertContains(navRow, "sidebarItemHighlightColor(", "navRow should use the shared highlight helper")
assertContains(navRow, "hoveredSidebarTab == tab", "navRow should apply hover state")
assertContains(navRow, ".onHover", "navRow should update hover state")

assertContains(agentRow, "sidebarItemHighlightColor(", "Agent rows should use the shared highlight helper")

assertContains(mainList, "hoveredSidebarAction == .newChat", "New chat should apply hover state")
assertContains(mainList, "hoveredSidebarAction == .searchChats", "Search chats should apply hover state")
assertContains(mainList, "sidebarItemHighlightColor(", "Special sidebar actions should use the shared highlight helper")

print("Sidebar unified highlight verification passed")
