import Foundation

private let dashboardUIRelativePaths = [
    "OpenClawInstaller/Features/Dashboard/DashboardTypography.swift",
    "OpenClawInstaller/Features/Dashboard/DashboardView.swift",
    "OpenClawInstaller/Features/Dashboard/Sidebar/DashboardSidebar.swift",
    "OpenClawInstaller/Features/Chat/Views/ChatView.swift",
    "OpenClawInstaller/Features/Chat/Views/ComposerChrome.swift",
    "OpenClawInstaller/Features/Chat/Views/ChatBubbleViews.swift",
]
private func loadDashboardUI(root: URL) throws -> String {
    try dashboardUIRelativePaths.map { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }.joined(separator: "\n")
}


private func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = try loadDashboardUI(root: root)

guard let dashboardStart = source.range(of: "struct DashboardView: View")?.lowerBound,
      let sidebarStart = source.range(of: "struct SidebarView: View")?.lowerBound else {
    fail("could not find DashboardView and SidebarView declarations")
}

let dashboardSection = String(source[dashboardStart..<sidebarStart])
let sidebarSection = String(source[sidebarStart...])

guard dashboardSection.contains("isGlobalSessionSearchPresented"),
      dashboardSection.contains("globalSessionSearchOverlay") else {
    fail("global search overlay must be owned by DashboardView so it can cover the full split view")
}

guard !sidebarSection.contains("globalSessionSearchOverlay") else {
    fail("global search overlay is still attached to SidebarView and will be clipped to the sidebar column")
}

print("Global search overlay placement verification passed")
