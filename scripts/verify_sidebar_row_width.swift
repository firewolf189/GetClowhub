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
    to: "private func sidebarItemHighlightColor"
)

assertContains(
    sidebarRowContent,
    ".frame(maxWidth: .infinity, alignment: .leading)",
    "Shared sidebar row content should expand before its background is applied"
)

assertContains(
    agentSidebarRow,
    ".frame(maxWidth: .infinity, alignment: .leading)",
    "Agent sidebar rows should use the same full-width background frame"
)

print("Sidebar row width verification passed")
