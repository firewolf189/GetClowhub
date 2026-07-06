import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboardURL = root.appendingPathComponent("OpenClawInstaller/Features/Dashboard/DashboardView.swift")

guard let dashboard = try? String(contentsOf: dashboardURL, encoding: .utf8) else {
    fatalError("Could not read DashboardView.swift")
}

func assertContains(_ haystack: String, _ needle: String, _ message: String) {
    guard haystack.contains(needle) else {
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

let sidebarRowContent = slice(
    dashboard,
    from: "private func sidebarRowContent",
    to: "// MARK: - Sessions Section Content"
)

let agentSidebarRow = slice(
    dashboard,
    from: "private func agentSidebarRow",
    to: "private func agentRowWithContextMenu"
)

let collapsibleRowContent = slice(
    dashboard,
    from: "struct SidebarCollapsibleRow",
    to: "private var chevron: some View"
)

assertContains(
    sidebarRowContent,
    ".frame(maxWidth: .infinity, alignment: .leading)",
    "Shared sidebar row content should expand before its background is applied"
)

assertContains(
    agentSidebarRow,
    "return SidebarCollapsibleRow(",
    "Agent sidebar rows should render through the shared collapsible row"
)

assertContains(
    collapsibleRowContent,
    ".frame(maxWidth: .infinity, alignment: .leading)",
    "Shared collapsible row content should use the same full-width background frame"
)

guard let frameRange = collapsibleRowContent.range(of: ".frame(maxWidth: .infinity, alignment: .leading)"),
      collapsibleRowContent[frameRange.upperBound...].contains(".background(") else {
    fatalError("Collapsible row should expand to full width before its background is applied")
}

print("Sidebar row width verification passed")
