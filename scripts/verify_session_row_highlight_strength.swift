import Foundation

private let dashboardUIRelativePaths = [
    "OpenClawInstaller/Features/Dashboard/DashboardTypography.swift",
    "OpenClawInstaller/Features/Dashboard/DashboardView.swift",
    "OpenClawInstaller/Features/Dashboard/Sidebar/DashboardSidebar.swift",
    "OpenClawInstaller/Features/Chat/Views/ChatView.swift",
    "OpenClawInstaller/Features/Chat/Views/ComposerChrome.swift",
    "OpenClawInstaller/Features/Chat/Views/ChatBubbleViews.swift",
    "OpenClawInstaller/Features/Agents/Views/AgentSettingsPanel.swift",
    "OpenClawInstaller/Features/Dashboard/TerminalPanel.swift",
    "OpenClawInstaller/Features/Sessions/Views/SessionDetailsPanel.swift",
]
private func loadDashboardUI(root: URL) throws -> String {
    try dashboardUIRelativePaths.map { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }.joined(separator: "\n")
}


let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboardURL = root.appendingPathComponent("OpenClawInstaller/Features/Dashboard/DashboardView.swift")

guard let dashboard = try? loadDashboardUI(root: root) else {
    fatalError("Could not read DashboardView.swift")
}

guard let start = dashboard.range(of: "private func sessionRowHighlightColor"),
      let end = dashboard[start.upperBound...].range(of: "private func cancelSessionDeleteConfirmation") else {
    fatalError("Could not locate sessionRowHighlightColor")
}

let helper = String(dashboard[start.lowerBound..<end.lowerBound])

func require(_ needle: String, _ message: String) {
    guard helper.contains(needle) else {
        fatalError(message)
    }
}

require(
    "SwiftUI.Color.primary.opacity(isDark ? 0.16 : 0.11)",
    "active session rows should use a clearly visible gray highlight"
)
require(
    "SwiftUI.Color.primary.opacity(isDark ? 0.11 : 0.07)",
    "hovered session rows should use a visible gray highlight"
)

print("OK: session row highlight strength verified")
