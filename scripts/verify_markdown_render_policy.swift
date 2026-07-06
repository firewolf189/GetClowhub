import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboardURL = root.appendingPathComponent("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let rendererURL = root.appendingPathComponent("OpenClawInstaller/Features/Chat/Markdown/AssistantMessageRenderer.swift")
let selectableURL = root.appendingPathComponent("OpenClawInstaller/Features/Chat/Markdown/SelectableMarkdownView.swift")
let markdownHTMLURL = root.appendingPathComponent("OpenClawInstaller/Features/Chat/Markdown/MarkdownHTML.swift")
let helpURL = root.appendingPathComponent("OpenClawInstaller/Features/Help/Views/HelpAssistantWindow.swift")
let timelineModelsURL = root.appendingPathComponent("OpenClawInstaller/Features/Chat/Models/ChatTimelineModels.swift")

guard let timelineModels = try? String(contentsOf: timelineModelsURL, encoding: .utf8) else {
    fputs("FAIL: unable to read ChatTimelineModels.swift\n", stderr)
    exit(1)
}
guard let dashboard = try? String(contentsOf: dashboardURL, encoding: .utf8) else {
    fatalError("Could not read DashboardView.swift")
}
guard let renderer = try? String(contentsOf: rendererURL, encoding: .utf8) else {
    fatalError("Could not read AssistantMessageRenderer.swift")
}
guard let selectable = try? String(contentsOf: selectableURL, encoding: .utf8) else {
    fatalError("Could not read SelectableMarkdownView.swift")
}
guard let markdownHTML = try? String(contentsOf: markdownHTMLURL, encoding: .utf8) else {
    fatalError("Could not read MarkdownHTML.swift")
}
guard let help = try? String(contentsOf: helpURL, encoding: .utf8) else {
    fatalError("Could not read HelpAssistantWindow.swift")
}

func expectContains(_ source: String, _ needle: String, _ message: String) {
    guard source.contains(needle) else {
        fatalError(message)
    }
}

func expectHelpContains(_ needle: String, _ message: String) {
    guard help.contains(needle) else {
        fatalError(message)
    }
}

expectContains(
    renderer,
    "enum MarkdownRenderPolicy",
    "Markdown rendering decisions should live in one policy type"
)
expectContains(
    renderer,
    "if isStreaming { return .native }",
    "Streaming complex Markdown should stay on the native renderer"
)
expectContains(
    renderer,
    "return requiresWebView(content) ? .webView : .native",
    "Completed complex Markdown should still upgrade to WKWebView"
)
expectContains(
    renderer,
    "static let heightUpdateThreshold: CGFloat = 4",
    "Measured WebView height should not write back for tiny changes"
)
expectContains(
    selectable,
    "MarkdownRenderPolicy.shouldApplyMeasuredHeight",
    "Height writeback should use the shared threshold policy"
)
expectContains(
    markdownHTML,
    "font-size: 14px; color:",
    "Rich markdown body text should use the same 14px size as normal message text"
)
expectContains(
    markdownHTML,
    "th, td { border: 1px solid \\(borderColor); padding: 5px 10px; text-align: left; font-size: 14px; line-height: 1.55; }",
    "Rich markdown table cells should match normal message text size"
)
expectContains(
    renderer,
    "static let recentRichMessageLimit = 6",
    "Only a bounded number of recent complex messages should use WKWebView"
)
expectContains(
    renderer,
    "recentRichMessageIds(in messages: [ChatMessage]) -> Set<UUID>",
    "WKWebView eligibility should be calculated from the full message list"
)
expectContains(
    timelineModels,
    "let richMarkdownMessageIds = MarkdownRenderPolicy.recentRichMessageIds(in: messages)",
    "Chat timeline snapshot should compute recent rich-message eligibility once before layout"
)
expectContains(
    timelineModels,
    "allowsRichMarkdown: richMarkdownMessageIds.contains(message.id)",
    "Each chat row model should receive explicit WKWebView eligibility"
)
expectContains(
    dashboard,
    "@State private var isRichMarkdownActivated = false",
    "Older complex messages should support manual WKWebView activation"
)
expectContains(
    dashboard,
    "message.allowsRichMarkdown || isRichMarkdownActivated",
    "Manual activation should temporarily allow WKWebView for an older message"
)
expectContains(
    renderer,
    "struct AssistantMessageContentView: View",
    "Assistant message renderer should be reusable outside DashboardView.swift"
)
expectHelpContains(
    "AssistantMessageContentView(content: message.content, isStreaming: false)",
    "Help assistant final replies should use the shared markdown renderer"
)

print("Markdown render policy verification passed")
