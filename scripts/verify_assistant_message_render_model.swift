#!/usr/bin/env swift

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


let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboardURL = root.appendingPathComponent("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let rendererURL = root.appendingPathComponent("OpenClawInstaller/Features/Chat/Markdown/AssistantMessageRenderer.swift")
let selectableURL = root.appendingPathComponent("OpenClawInstaller/Features/Chat/Markdown/SelectableMarkdownView.swift")
let markdownHTMLURL = root.appendingPathComponent("OpenClawInstaller/Features/Chat/Markdown/MarkdownHTML.swift")
let dashboard = try loadDashboardUI(root: root)
let renderer = (try? String(contentsOf: rendererURL, encoding: .utf8)) ?? ""
let selectable = (try? String(contentsOf: selectableURL, encoding: .utf8)) ?? ""
let markdownHTML = (try? String(contentsOf: markdownHTMLURL, encoding: .utf8)) ?? ""

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

func slice(_ source: String, from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start) else {
        return ""
    }
    if end == "***END***" {
        return String(source[startRange.lowerBound..<source.endIndex])
    }
    guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        return ""
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

let renderModel = slice(
    renderer,
    from: "private struct MessageRenderModel",
    to: "struct AssistantMessageContentView: View"
)
let assistantView = slice(
    renderer,
    from: "struct AssistantMessageContentView: View",
    to: "// MARK: - Native"
)
let chatView = slice(
    dashboard,
    from: "struct ChatView: View",
    to: "// MARK: - Chat Bubble"
)
let chatBubble = slice(
    dashboard,
    from: "struct ChatBubble: View",
    to: "struct InlineUserMessageEditor"
)
let nativeBridge = slice(
    renderer,
    from: "struct NativeSelectableMarkdownView: NSViewRepresentable",
    to: "***END***"
)
let markdownWebView = slice(
    selectable,
    from: "private struct _MarkdownWebView: NSViewRepresentable",
    to: "***END***"
)

require(dashboard.contains("AssistantMessageContentView("), "DashboardView should still compose assistant content")
require(!dashboard.contains("private struct MessageRenderModel"), "MessageRenderModel should be split out of DashboardView")
require(!dashboard.contains("struct NativeSelectableMarkdownView: NSViewRepresentable"), "NSTextView bridge should be split out of DashboardView")
require(!dashboard.contains("struct SelectableMarkdownView: View"), "WKWebView fallback should be split out of DashboardView")
require(!dashboard.contains("enum MarkdownHTML"), "MarkdownHTML conversion should be split out of DashboardView")
require(!renderer.isEmpty, "AssistantMessageRenderer.swift should exist")
require(!selectable.isEmpty, "SelectableMarkdownView.swift should exist")
require(!markdownHTML.isEmpty, "MarkdownHTML.swift should exist")
require(markdownHTML.contains("enum MarkdownHTML"), "MarkdownHTML.swift should own MarkdownHTML")

require(!renderModel.isEmpty, "assistant messages should be parsed through MessageRenderModel")
require(renderModel.contains("enum Renderer"), "MessageRenderModel should expose a renderer enum")
require(!renderModel.contains("A2UI"), "release renderer should not reference A2UI")
require(!renderModel.contains("a2ui"), "release renderer should not contain A2UI render cases")
// The MarkdownUI refactor split the old single `nativeText` case into the
// cheap streaming renderer and the full SwiftUI Markdown renderer.
require(renderModel.contains("case plainText"), "streaming/plain rendering should be its own render-model case")
require(renderModel.contains("case markdownUI"), "settled Markdown should render through the MarkdownUI case")
require(renderModel.contains("case webViewFallback"), "WKWebView fallback should be one render-model case")
require(renderModel.contains("let isStreaming: Bool"), "MessageRenderModel should carry streaming state into the renderer")
require(renderModel.contains("static func build(content: String, isStreaming: Bool, allowsRichMarkdown: Bool) -> MessageRenderModel"), "MessageRenderModel should own render decisions")
require(renderModel.contains("MarkdownRenderPolicy.mode("), "MarkdownRenderPolicy should be consumed by the render model")
require(renderModel.contains("for: content"), "MessageRenderModel should pass content to MarkdownRenderPolicy")
require(renderModel.contains("isStreaming: isStreaming"), "MessageRenderModel should pass streaming state to MarkdownRenderPolicy")
require(renderModel.contains("allowsWebView: allowsRichMarkdown"), "MessageRenderModel should pass rich-markdown eligibility to MarkdownRenderPolicy")

require(assistantView.contains("let renderModel = MessageRenderModel.build("), "AssistantMessageContentView should build one render model")
require(assistantView.contains("switch renderModel.renderer"), "AssistantMessageContentView should switch on the render model")
// NativeSelectableMarkdownView was replaced by MarkdownUI (2026-07-25); text
// selection is now a modifier on the SwiftUI view instead of an NSTextView.
require(assistantView.contains("Markdown("), "ordinary assistant content should render through MarkdownUI")
require(assistantView.contains(".textSelection(.enabled)"), "assistant content must stay selectable")
require(assistantView.contains("case .plainText"), "AssistantMessageContentView should route streaming/plain text separately")
require(assistantView.contains("case .markdownUI"), "AssistantMessageContentView should route settled Markdown separately")
// The streaming path no longer goes through an NSTextView bridge at all — it
// renders `Text(verbatim:)`, which cannot parse Markdown by construction.
require(assistantView.contains("Text(verbatim: renderModel.content)"), "streaming content should render verbatim, with no Markdown parsing")
require(!assistantView.contains("prefersNativeTextSelection"), "direct text selection should not depend on a single-message selection mode")
require(!assistantView.contains("Markdown(content)"), "assistant rendering should not directly use scattered Markdown(content)")

// The NSTextView bridge that used to live here was DELETED on 2026-07-26 (it
// was the livelock's per-row AppKit host, and unused after the MarkdownUI
// refactor). Its replacement is the single-Text cross-block selection path,
// contracted in verify_direct_selection_without_swiftui_overlay.swift.
require(nativeBridge.isEmpty, "the NSTextView selection bridge should stay deleted")
require(!renderer.contains("NSViewRepresentable"), "no message renderer may host an AppKit view")
require(renderer.contains("struct CrossBlockSelectableMessageText"), "cross-block selection should be a pure-SwiftUI single Text")

require(!chatView.contains("@State private var activeNativeTextSelectionMessageId: UUID?"), "ChatView should not hold single-message selection mode state")
require(!chatView.contains("activeNativeTextSelectionMessageId:"), "ChatView should not pass single-message selection state into ChatBubble")
require(!chatView.contains("setActiveNativeTextSelectionMessageId"), "ChatView should not centralize a removed single-message selection mode")
require(!chatBubble.contains("@State private var isSelectionModeEnabled"), "ChatBubble should not keep independent per-row selection mode state")
require(!chatBubble.contains("let activeNativeTextSelectionMessageId: UUID?"), "ChatBubble should not receive single-message selection state")
require(!chatBubble.contains("var onSetActiveNativeTextSelectionMessageId: (UUID?) -> Void"), "ChatBubble should not request single-message selection mode changes")
require(!chatBubble.contains("private var isSelectionModeEnabled: Bool"), "ChatBubble should not derive a removed selection mode")
require(!chatBubble.contains("prefersNativeTextSelection:"), "ChatBubble should not pass selection mode into assistant renderer")
require(!renderer.contains("A2UICardView("), "release assistant renderer should not render A2UI cards")
require(!renderer.contains("logRenderMode(\"a2ui\")"), "release assistant renderer should not log A2UI render mode")

require(!markdownWebView.contains("window.webkit.messageHandlers.rendered.postMessage"), "WebView fallback should not need a JS postMessage just to mark readiness")
require(!markdownWebView.contains("config.userContentController.add(context.coordinator, name: \"rendered\")"), "WebView fallback should not register a rendered message handler")

print("PASS: assistant message render model and native selectable bridge verified")
