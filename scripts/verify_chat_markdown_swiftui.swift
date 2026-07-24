import Foundation

// Architectural guard: the chat timeline must render markdown with pure
// SwiftUI (MarkdownUI). Platform views (NSTextView / WKWebView) hosted per
// message row were the structural root of five SwiftUI<->AppKit layout
// livelocks (2026-07-21..24) — every row joined the cross-framework layout
// negotiation and any invalidation edge could loop. WKWebView remains ONLY
// for math/LaTeX content, which MarkdownUI cannot render.

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

let renderer = read("OpenClawInstaller/Features/Chat/Markdown/AssistantMessageRenderer.swift")

require(
    renderer.contains("import MarkdownUI"),
    "assistant messages must render via MarkdownUI (pure SwiftUI)"
)
require(
    renderer.contains("case markdownUI"),
    "MarkdownRenderPolicy must have a markdownUI mode as the completed-message default"
)
// Tables no longer force the WKWebView path — MarkdownUI renders GFM tables
// natively, and the webview's async height measurement caused the phantom
// blank-space bug on emoji tables.
require(
    !renderer.contains("containsMarkdownTable(content)\n            || containsMathSyntax"),
    "requiresWebView must not include tables — only math/HTML may use the WKWebView fallback"
)
// The completed-message native path must not go through the NSTextView host.
require(
    renderer.contains("Markdown(") || renderer.contains("Markdown ("),
    "AssistantMessageContentView must build a MarkdownUI Markdown view"
)

print("chat-markdown-swiftui architectural guards hold")
