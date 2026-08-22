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


func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fail(message) }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = try loadDashboardUI(root: root)

require(
    !source.contains("ChatScrollContentMetricsKey") &&
        !source.contains("ChatScrollViewportHeightKey"),
    "chat scroll should not continuously publish geometry preference metrics"
)
require(
    !source.contains("updateChatScrollMetricsIfNeeded(") &&
        !source.contains("updateChatScrollViewportHeightIfNeeded("),
    "chat scroll should not write geometry metrics back into @State"
)
require(
    !source.contains("chatScrollOffset") &&
        !source.contains("chatScrollViewportHeight") &&
        !source.contains("chatScrollContentHeight"),
    "chat scroll offset/height state should be removed with the preference metrics"
)
// The custom transient scroll indicator was intentionally removed in the
// chat-surface extraction (native scrollbars now provide feedback);
// verify_chat_scroll_metrics_guard.swift asserts its absence.

print("Chat scroll geometry feedback loop is reduced")
