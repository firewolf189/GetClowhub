import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboardURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let assistantRendererURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/AssistantMessageRenderer.swift")
let markdownHTMLURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/MarkdownHTML.swift")

guard let dashboard = try? String(contentsOf: dashboardURL, encoding: .utf8) else {
    fatalError("Could not read DashboardView.swift")
}

guard let assistantRenderer = try? String(contentsOf: assistantRendererURL, encoding: .utf8) else {
    fatalError("Could not read AssistantMessageRenderer.swift")
}

guard let markdownHTML = try? String(contentsOf: markdownHTMLURL, encoding: .utf8) else {
    fatalError("Could not read MarkdownHTML.swift")
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

let typography = slice(
    dashboard,
    from: "enum DashboardTypography",
    to: "enum DashboardSidebarMetrics"
)

guard typography.contains("static let message = Font.system(size: 14, weight: .regular)") else {
    fatalError("Assistant message text should use 14pt regular system typography")
}

guard typography.contains("static let userMessage = Font.system(size: 14, weight: .regular)") else {
    fatalError("User message text should match assistant message typography")
}

guard markdownHTML.contains("font-size: 14px; color:") else {
    fatalError("WebView assistant message body text should match the 14pt chat message size")
}

guard !markdownHTML.contains("font-size: 15px; color:") else {
    fatalError("WebView assistant message body text must not be larger than user messages")
}

assertContains(
    assistantRenderer,
    "return requiresWebView(content) ? .webView : .native",
    "Complex Markdown such as tables should still upgrade to WKWebView"
)

guard assistantRenderer.contains("fontSize: CGFloat = 14") &&
        assistantRenderer.contains("NSFont.systemFont(ofSize: fontSize)") &&
        assistantRenderer.contains("fontSize: 14") else {
    fatalError("Native direct-selection renderer should match the 14pt chat message size")
}

print("Chat typography verification passed")
