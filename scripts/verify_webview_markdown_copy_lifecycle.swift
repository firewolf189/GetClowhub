#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let selectablePath = root.appendingPathComponent("OpenClawInstaller/Features/Chat/Markdown/SelectableMarkdownView.swift")
let dashboardPath = root.appendingPathComponent("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let appDelegatePath = root.appendingPathComponent("OpenClawInstaller/App/AppDelegate.swift")

let selectable = try String(contentsOf: selectablePath, encoding: .utf8)
let dashboard = try String(contentsOf: dashboardPath, encoding: .utf8)
let appDelegate = try String(contentsOf: appDelegatePath, encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(_ text: String, from start: String, to end: String) -> String {
    guard let startRange = text.range(of: start),
          let endRange = text.range(of: end, range: startRange.upperBound..<text.endIndex) else {
        return ""
    }
    return String(text[startRange.lowerBound..<endRange.lowerBound])
}

let scrollThroughWebView = slice(
    selectable,
    from: "private class ScrollThroughWebView: WKWebView",
    to: "enum WebViewMarkdownSelectionRegistry"
)
let registry = slice(
    selectable,
    from: "enum WebViewMarkdownSelectionRegistry",
    to: "private struct _MarkdownWebView"
)
let representable = slice(
    selectable,
    from: "private struct _MarkdownWebView: NSViewRepresentable",
    to: "func updateNSView"
)
let prepareForReuse = slice(
    scrollThroughWebView,
    from: "func prepareForReuseOrDismantle()",
    to: "private func markActiveForCopy()"
)
let clearSelectionAfterCopy = slice(
    selectable,
    from: "private func clearSelectionAfterCopy()",
    to: "enum WebViewMarkdownSelectionRegistry"
)

require(
    scrollThroughWebView.contains("func copySelectionOrFallback(allowFallback: Bool, completion: ((Bool) -> Void)? = nil)") &&
        scrollThroughWebView.contains("completion?(false)") &&
        scrollThroughWebView.contains("completion?(true)"),
    "WebView copy should report whether it actually copied selected or fallback text."
)
require(
    clearSelectionAfterCopy.contains("window.getSelection().removeAllRanges()"),
    "WebView copy should clear the live WebKit selection after copying to reduce active selection render work."
)
require(
    !prepareForReuse.contains("clearSelectionAfterCopy()") &&
        !prepareForReuse.contains("evaluateJavaScript"),
    "Dismantling markdown WebViews should not evaluate JavaScript while SwiftUI is recycling the row."
)
require(
    scrollThroughWebView.contains("func prepareForReuseOrDismantle()") &&
        scrollThroughWebView.contains("resizeWorkItem?.cancel()") &&
        scrollThroughWebView.contains("stopLoading()") &&
        scrollThroughWebView.contains("navigationDelegate = nil"),
    "Dismantled markdown WebViews should cancel delayed work, stop loading, and detach delegates."
)
require(
    registry.contains("static func clearIfActive(_ webView: ScrollThroughWebView)") &&
        registry.contains("activeWebView === webView") &&
        registry.contains("activeWebView = nil"),
    "The active WebView registry should release a dismantled WebView identity."
)
require(
    registry.contains("static func copyActiveSelection() -> Bool") &&
        registry.contains("activeWebView.copySelectionOrFallback(allowFallback: false"),
    "Global Cmd+C should only copy real WebView selections, not full message fallback."
)
require(
    representable.contains("static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator)") &&
        representable.contains("WebViewMarkdownSelectionRegistry.clearIfActive(webView)") &&
        representable.contains("webView.prepareForReuseOrDismantle()"),
    "NSViewRepresentable dismantle should clean markdown WebView lifecycle state."
)
require(
    dashboard.contains("WebViewMarkdownSelectionRegistry.copyActiveSelection()"),
    "Dashboard Cmd+C fallback should route to selected WebView text only."
)
require(
    appDelegate.contains("WebViewMarkdownSelectionRegistry.copyActiveSelection()"),
    "App-level Copy should route to selected WebView text only."
)

print("WebView markdown copy lifecycle verification passed")
