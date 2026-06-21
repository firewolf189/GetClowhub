#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboard = try String(
    contentsOf: root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/DashboardView.swift"),
    encoding: .utf8
)
let smoothScrollView = try String(
    contentsOf: root.appendingPathComponent("OpenClawInstaller/Views/Shared/SmoothScrollView.swift"),
    encoding: .utf8
)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

func slice(_ source: String, from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        return ""
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

let chatView = slice(
    dashboard,
    from: "struct ChatView: View",
    to: "// MARK: - Chat Bubble"
)
let timelineSurface = slice(
    dashboard,
    from: "private var timelineChatSurface: some View",
    to: "private func composerArea"
)
let scrollContent = slice(
    dashboard,
    from: "private func chatScrollContent(proxy: ScrollViewProxy) -> some View",
    to: "/// Filtered slash commands"
)
let selectableMarkdown = slice(
    dashboard,
    from: "struct SelectableMarkdownView: View",
    to: "/// WKWebView subclass"
)
let markdownWebView = slice(
    dashboard,
    from: "private struct _MarkdownWebView: NSViewRepresentable",
    to: "// MARK: - Markdown"
)

require(chatView.contains("@State private var showChatScrollIndicator = false"), "chat view should own custom scroll indicator visibility")
require(chatView.contains("@State private var chatScrollIndicatorHideTask"), "chat view should debounce scroll indicator hide")
require(chatView.contains("@State private var chatScrollOffset"), "chat view should track scroll offset")
require(chatView.contains("@State private var chatScrollViewportHeight"), "chat view should track viewport height")
require(chatView.contains("@State private var chatScrollContentHeight"), "chat view should track content height")

require(timelineSurface.contains("chatScrollIndicator"), "timeline surface should overlay the custom scroll indicator")
require(chatView.contains("private var chatScrollIndicator: some View"), "chat view should define a custom scroll indicator")
require(chatView.contains("let indicatorHeight: CGFloat = 38"), "custom scroll indicator should be about 1cm tall")
require(chatView.contains(".frame(width: 3, height: indicatorHeight)"), "custom scroll indicator should be narrow and fixed height")
require(chatView.contains("showTransientChatScrollIndicator()"), "scroll wheel handling should show the custom indicator")
require(chatView.contains("chatScrollIndicatorHideTask"), "scroll wheel handling should schedule indicator hide")

require(scrollContent.contains("ScrollView(showsIndicators: false)"), "native chat scroll indicators should be hidden")
require(scrollContent.contains(".coordinateSpace(name: \"chatScrollSpace\")"), "chat scroll view should expose a named coordinate space")
require(scrollContent.contains("ChatScrollContentMetricsKey"), "chat scroll content should publish offset/content metrics")
require(scrollContent.contains("ChatScrollViewportHeightKey"), "chat scroll view should publish viewport height")

require(dashboard.contains("private struct ChatScrollContentMetrics: Equatable"), "chat scroll metrics value should exist")
require(dashboard.contains("private struct ChatScrollContentMetricsKey: PreferenceKey"), "content metrics preference key should exist")
require(dashboard.contains("private struct ChatScrollViewportHeightKey: PreferenceKey"), "viewport height preference key should exist")

require(smoothScrollView.contains("struct SmoothScrollView<Content: View>: View"), "shared SmoothScrollView component should exist")
require(smoothScrollView.contains("ScrollView(axes, showsIndicators: false)"), "SmoothScrollView should hide native scroll indicators")
require(smoothScrollView.contains("let indicatorHeight: CGFloat = 38"), "SmoothScrollView should use the standard 38pt indicator height")
require(smoothScrollView.contains(".frame(width: 3, height: indicatorHeight)"), "SmoothScrollView indicator should use the standard 3pt width")
require(smoothScrollView.contains("indicatorHideTask"), "SmoothScrollView should debounce indicator hiding")
require(smoothScrollView.contains("SmoothScrollContentMetricsKey"), "SmoothScrollView should own reusable scroll metrics preference keys")

require(selectableMarkdown.contains("@State private var pendingWebViewReadyTask: DispatchWorkItem?"), "selectable markdown should debounce WebView readiness")
require(selectableMarkdown.contains("markWebViewReadyAfterPaint()"), "selectable markdown should wait before removing fallback")
require(selectableMarkdown.contains("pendingWebViewReadyTask?.cancel()"), "selectable markdown should cancel stale ready tasks")
require(!selectableMarkdown.contains("withAnimation(.easeInOut(duration: 0.12)) {\n                            isWebViewReady = true"), "fallback should not be removed directly inside onRendered")

require(markdownWebView.contains("notifyRenderedAfterPaint(webView: webView)"), "WKWebView should notify readiness after browser paint")
require(markdownWebView.contains("requestAnimationFrame"), "WKWebView readiness should wait for paint frames")
require(markdownWebView.contains("window.webkit.messageHandlers.rendered.postMessage"), "WKWebView should use a script message after paint")
require(markdownWebView.contains("config.userContentController.add(context.coordinator, name: \"rendered\")"), "WKWebView should register rendered script handler")
require(!markdownWebView.contains("onRendered?()\n            // Cache height"), "height measurement should not mark the WebView ready before paint")

print("PASS: chat custom scroll indicator and WKWebView paint-ready contracts verified")
