#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let selectablePath = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/SelectableMarkdownView.swift")
let dashboardPath = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let appDelegatePath = root.appendingPathComponent("OpenClawInstaller/AppDelegate.swift")

let selectable = try String(contentsOf: selectablePath, encoding: .utf8)
let dashboard = try String(contentsOf: dashboardPath, encoding: .utf8)
let appDelegate = try String(contentsOf: appDelegatePath, encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

require(
    selectable.contains("enum WebViewMarkdownSelectionRegistry"),
    "WKWebView markdown selection should have a registry reachable from global Cmd+C handlers."
)
require(
    selectable.contains("static func markActive(_ webView: ScrollThroughWebView)") &&
        selectable.contains("private static weak var activeWebView"),
    "The registry should remember the active markdown WebView without exposing the WebView type outside the file."
)
require(
    selectable.contains("override var acceptsFirstResponder: Bool { true }") &&
        selectable.contains("override func mouseDown(with event: NSEvent)") &&
        selectable.contains("override func mouseDragged(with event: NSEvent)") &&
        selectable.contains("override func mouseUp(with event: NSEvent)") &&
        selectable.contains("markActiveForCopy()"),
    "The markdown WebView should become the active copy target while the user selects table text."
)
require(
    selectable.contains("func copySelectionOrFallback(allowFallback: Bool, completion: ((Bool) -> Void)? = nil)") &&
        selectable.contains("window.getSelection().toString()") &&
        selectable.contains("allowFallback ? copyFallbackText : \"\""),
    "The WebView copy path should copy the selected table text and only use full-message fallback when allowed."
)
require(
    dashboard.contains("WebViewMarkdownSelectionRegistry.copyActiveSelection()"),
    "ChatView Cmd+C handling should copy selected markdown WebView text after native text selection."
)
require(
    appDelegate.contains("WebViewMarkdownSelectionRegistry.copyActiveSelection()"),
    "The app-level Copy menu command should also route selected markdown WebView text."
)

print("WebView markdown copy bridge verification passed")
