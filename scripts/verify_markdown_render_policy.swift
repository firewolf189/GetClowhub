import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboardURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let helpURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/HelpAssistantWindow.swift")

guard let dashboard = try? String(contentsOf: dashboardURL, encoding: .utf8) else {
    fatalError("Could not read DashboardView.swift")
}
guard let help = try? String(contentsOf: helpURL, encoding: .utf8) else {
    fatalError("Could not read HelpAssistantWindow.swift")
}

func expectContains(_ needle: String, _ message: String) {
    guard dashboard.contains(needle) else {
        fatalError(message)
    }
}

func expectHelpContains(_ needle: String, _ message: String) {
    guard help.contains(needle) else {
        fatalError(message)
    }
}

expectContains(
    "private enum MarkdownRenderPolicy",
    "Markdown rendering decisions should live in one policy type"
)
expectContains(
    "if isStreaming { return .native }",
    "Streaming complex Markdown should stay on the native renderer"
)
expectContains(
    "return requiresWebView(content) ? .webView : .native",
    "Completed complex Markdown should still upgrade to WKWebView"
)
expectContains(
    "static let heightUpdateThreshold: CGFloat = 4",
    "Measured WebView height should not write back for tiny changes"
)
expectContains(
    "MarkdownRenderPolicy.shouldApplyMeasuredHeight",
    "Height writeback should use the shared threshold policy"
)
expectContains(
    "font-size: 15px; color:",
    "Rich markdown body text should use the same 15px size as normal message text"
)
expectContains(
    "th, td { border: 1px solid \\(borderColor); padding: 5px 10px; text-align: left; font-size: 15px; line-height: 1.55; }",
    "Rich markdown table cells should match normal message text size"
)
expectContains(
    "static let recentRichMessageLimit = 6",
    "Only a bounded number of recent complex messages should use WKWebView"
)
expectContains(
    "recentRichMessageIds(in messages: [ChatMessage]) -> Set<UUID>",
    "WKWebView eligibility should be calculated from the full message list"
)
expectContains(
    "let richMarkdownMessageIds = MarkdownRenderPolicy.recentRichMessageIds(in: viewModel.chatMessages)",
    "Chat list should compute recent rich-message eligibility once per list render"
)
expectContains(
    "allowsRichMarkdown: richMarkdownMessageIds.contains(message.id)",
    "Each chat bubble should receive explicit WKWebView eligibility"
)
expectContains(
    "@State private var isRichMarkdownActivated = false",
    "Older complex messages should support manual WKWebView activation"
)
expectContains(
    "allowsRichMarkdown || isRichMarkdownActivated",
    "Manual activation should temporarily allow WKWebView for an older message"
)
expectContains(
    "struct AssistantMessageContentView: View",
    "Assistant message renderer should be reusable outside DashboardView.swift"
)
expectHelpContains(
    "AssistantMessageContentView(content: message.content, isStreaming: false)",
    "Help assistant final replies should use the shared markdown renderer"
)

print("Markdown render policy verification passed")
