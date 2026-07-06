#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let dashboard = read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let assistantRenderer = read("OpenClawInstaller/Features/Chat/Markdown/AssistantMessageRenderer.swift")
let selectableMarkdown = read("OpenClawInstaller/Features/Chat/Markdown/SelectableMarkdownView.swift")
let appDelegate = read("OpenClawInstaller/App/AppDelegate.swift")

let chatView = slice(
    dashboard,
    from: "struct ChatView: View",
    to: "private struct ComposerInputCardBoundsKey"
)
let messageCountHandler = slice(
    dashboard,
    from: ".onChange(of: viewModel.chatMessages.count)",
    to: "} else {"
)
let sessionScrollHelper = slice(
    dashboard,
    from: "private func scheduleSessionSwitchScrollToBottom",
    to: "private func beginRenderObservationForCurrentSession"
)
let appDelegateCopy = slice(
    appDelegate,
    from: "@objc func copy(_ sender: Any?)",
    to: "func applicationWillTerminate"
)

require(
    dashboard.contains("private enum ChatAutoScrollMode") &&
        dashboard.contains("case followingBottom") &&
        dashboard.contains("case userDetached") &&
        dashboard.contains("case sessionJumping"),
    "Chat scroll should use an explicit auto-scroll intent state machine."
)
require(
    chatView.contains("@State private var chatAutoScrollMode: ChatAutoScrollMode = .followingBottom"),
    "ChatView should store auto-scroll intent as ChatAutoScrollMode."
)
require(
    !chatView.contains("autoScrollDisableTimer") &&
        !dashboard.contains("Timer.scheduledTimer(withTimeInterval: 3.0"),
    "User-detached scrolling must not auto-resume from a fixed timer."
)
require(
    dashboard.contains("private struct ChatScrollIntentObserver: NSViewRepresentable") &&
        chatView.contains("ChatScrollIntentObserver("),
    "Chat scroll should observe the underlying NSScrollView for bottom reattachment."
)
require(
    messageCountHandler.contains("shouldFollowChatBottom"),
    "New messages should auto-scroll only while the user is following the bottom."
)
require(
    sessionScrollHelper.contains("scheduledBottomScrollGeneration") &&
        sessionScrollHelper.contains("scrollToBottomIfAllowed") &&
        sessionScrollHelper.contains("chatAutoScrollMode != .userDetached"),
    "Delayed session-switch scrolls should be cancellable when the user scrolls away."
)
require(
    assistantRenderer.contains("fullTextCopyFallback") &&
        assistantRenderer.contains("copyTextToPasteboard(fullTextCopyFallback)"),
    "Native selectable messages should copy the whole message when Cmd+C has no selection."
)
require(
    assistantRenderer.contains("override func performKeyEquivalent(with event: NSEvent) -> Bool") &&
        assistantRenderer.contains("override func keyDown(with event: NSEvent)") &&
        assistantRenderer.contains("isCommandCopyEvent") &&
        assistantRenderer.contains("copy(nil)"),
    "Native selectable messages should handle Cmd+C directly instead of relying only on responder-chain menu routing."
)
require(
    assistantRenderer.contains("override func mouseDragged(with event: NSEvent)") &&
        assistantRenderer.contains("override func mouseUp(with event: NSEvent)") &&
        assistantRenderer.contains("markActiveForCopy()") &&
        assistantRenderer.contains("window?.makeFirstResponder(self)") &&
        assistantRenderer.contains("enum NativeSelectableTextSelectionRegistry") &&
        assistantRenderer.contains("static weak var activeTextView") &&
        assistantRenderer.contains("copyActiveSelection()"),
    "Native selectable messages should keep first responder ownership while selecting text."
)
require(
    appDelegate.contains("@objc func copy(_ sender: Any?)") &&
        appDelegate.contains("NativeSelectableTextSelectionRegistry.copySelectedTextFromFirstResponder(sender)") &&
        appDelegate.contains("NativeSelectableTextSelectionRegistry.copyActiveSelection()"),
    "AppDelegate should copy only a non-empty first-responder selection before falling back to the active assistant selection."
)
require(
    !appDelegateCopy.contains("tryToPerform(#selector(NSText.copy(_:))"),
    "AppDelegate.copy must not re-enter the copy responder chain after it becomes the fallback target."
)
require(
    chatView.contains("handleCopyShortcut(event)") &&
        chatView.contains("private func handleCopyShortcut(_ event: NSEvent) -> Bool") &&
        chatView.contains("NativeSelectableTextSelectionRegistry.copySelectedTextFromFirstResponder(nil)") &&
        chatView.contains("NativeSelectableTextSelectionRegistry.copyActiveSelection()"),
    "ChatView should route Cmd+C to a real first-responder selection before composer shortcuts run."
)
require(
    assistantRenderer.contains("copySelectedTextFromFirstResponder") &&
        assistantRenderer.contains("NSApp.keyWindow?.firstResponder as? NSTextView") &&
        assistantRenderer.contains("selectedRanges.contains") &&
        assistantRenderer.contains("rangeValue.length > 0"),
    "Keyboard copy routing should not treat an empty text-field selection as handled."
)
require(
    selectableMarkdown.contains("copyFallbackText") &&
        selectableMarkdown.contains("override func performKeyEquivalent(with event: NSEvent) -> Bool") &&
        selectableMarkdown.contains("window.getSelection().toString()"),
    "WebView markdown messages should fall back to copying the whole message on Cmd+C."
)

print("Chat auto-follow and keyboard copy verification passed")
