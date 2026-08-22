import Foundation

/// Canonical dashboard UI sources after the Chat/Sidebar split.
/// Verify scripts cannot import this file when run as `swift scripts/verify_*.swift`;
/// copy the path list or join the same files. `verify_dashboard_ui_loader.swift`
/// fails any dashboard-UI contract that still reads only DashboardView.swift.
enum VerifyDashboardUI {
    static let relativePaths = [
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

    static func load(root: URL) throws -> String {
        try relativePaths
            .map { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
    }
}
