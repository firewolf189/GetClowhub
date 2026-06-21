import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func assertContains(_ haystack: String, _ needle: String, _ message: String) {
    guard haystack.contains(needle) else {
        fatalError(message)
    }
}

func assertNotContains(_ haystack: String, _ needle: String, _ message: String) {
    guard !haystack.contains(needle) else {
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

let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")

let titleToolbar = slice(
    dashboard,
    from: #".toolbar {"#,
    to: #".alert("Error""#
)
let titlePopoverView = slice(
    dashboard,
    from: "private struct SessionTitlePopoverView: View",
    to: "// MARK: - Input Mode Picker"
)
let titleFlyoutOverlay = slice(
    dashboard,
    from: "private var sessionTitleUserMessagesFlyout: some View",
    to: "private func updateSessionTitleHover"
)
let titleFlyoutContent = slice(
    dashboard,
    from: "private struct SessionTitleUserMessagesFlyoutContent: View",
    to: "private struct SessionTitleUserMessageRow: View"
)
let chatView = slice(
    dashboard,
    from: "struct ChatView: View",
    to: "private struct ComposerAgentModelSelector: View"
)
let chatBubble = slice(
    dashboard,
    from: "struct ChatBubble: View",
    to: "// MARK: - Typewriter Text for Streaming"
)

assertContains(
    titleToolbar,
    "SessionTitlePopoverView(",
    "conversation title must use the custom hover popover title view"
)
assertContains(
    titleToolbar,
    "messages: currentSessionUserMessages",
    "conversation title hover control must know whether user messages are available"
)
assertNotContains(
    titleToolbar,
    ".allowsHitTesting(false)",
    "conversation title must be interactive for hover popover behavior"
)

assertContains(
    dashboard,
    "private var currentSessionUserMessages: [ChatMessage]",
    "DashboardView must expose filtered user messages for the active session title popover"
)
assertContains(
    dashboard,
    ".filter { $0.role == .user",
    "title popover message source must filter to user messages only"
)

assertContains(
    titlePopoverView,
    "RoundedRectangle(cornerRadius: 8, style: .continuous)",
    "conversation title must render inside a lightweight rounded rectangle"
)
assertContains(
    titlePopoverView,
    "onHoverChange(hovering)",
    "title hover control must delegate hover state to the root overlay owner"
)
assertNotContains(
    titlePopoverView,
    "Task.sleep(nanoseconds: 300_000_000)",
    "title popover must not keep the old 300ms delayed hover behavior"
)
assertNotContains(
    titlePopoverView,
    ".popover(",
    "title hover UI must not use native popover because toolbar source views flicker"
)
assertContains(
    titleFlyoutOverlay,
    "GeometryReader { proxy in",
    "title user-message flyout must be rendered by a root overlay with geometry conversion"
)
assertContains(
    titleFlyoutOverlay,
    "let panelX = sessionTitleFlyoutX(in: proxy)",
    "title user-message flyout must compute an x position from the title frame"
)
assertContains(
    titleFlyoutOverlay,
    "let panelY = sessionTitleFlyoutY(in: proxy)",
    "title user-message flyout must compute a y position from the title frame"
)
assertContains(
    titleFlyoutOverlay,
    "SessionTitleUserMessagesFlyoutContent(",
    "title user-message list must be rendered as a self-owned flyout, not a native popover"
)
assertContains(
    titleFlyoutOverlay,
    ".offset(x: panelX, y: panelY)",
    "title user-message flyout must be positioned to the right of the title"
)
assertContains(
    titleFlyoutOverlay,
    ".onHover { hovering in",
    "title user-message flyout must keep itself open while pointer is over the panel"
)
assertContains(
    titleFlyoutOverlay,
    "updateSessionTitleFlyoutHover(hovering)",
    "title user-message flyout hover must participate in close scheduling"
)
assertContains(
    titleFlyoutContent,
    "ScrollView",
    "title popover content must be scrollable for long sessions"
)
assertContains(
    titleFlyoutContent,
    "LazyVStack",
    "title popover content must render user messages as a list"
)
assertContains(
    titleFlyoutContent,
    "ForEach(messages) { message in",
    "title popover must preserve message identity for future jump behavior"
)
assertContains(
    titleFlyoutContent,
    "onTapMessage(message)",
    "title popover rows must expose a future message-selection hook"
)
assertContains(
    titleFlyoutOverlay,
    ".frame(width: sessionTitleFlyoutWidth)",
    "title popover must use a stable readable width"
)
assertContains(
    titleFlyoutContent,
    ".frame(maxHeight: 320)",
    "title popover must cap height so long sessions scroll"
)
assertContains(
    dashboard,
    "private func scheduleSessionTitleFlyoutClose()",
    "title user-message flyout must close via a short grace delay instead of on title leave"
)
assertContains(
    dashboard,
    "sessionTitleFlyoutCloseTask?.cancel()",
    "title user-message flyout must cancel pending closes when pointer enters title or panel"
)

assertContains(
    chatView,
    "@State private var highlightedMessageId: UUID?",
    "ChatView must track the message selected from the title popover"
)
assertContains(
    chatView,
    "@State private var highlightedMessageFlashOn = false",
    "ChatView must keep a flashing phase for selected-message emphasis"
)
assertContains(
    chatView,
    "private func jumpToUserMessage(_ messageId: UUID)",
    "ChatView must expose a jump handler for title popover selections"
)
assertContains(
    chatView,
    "chatScrollProxy?.scrollTo(messageId, anchor: .center)",
    "jump handler must scroll the chat timeline to the selected user message"
)
assertContains(
    chatView,
    "triggerUserMessageHighlight(messageId)",
    "jump handler must start selected user message highlighting after scroll"
)
assertContains(
    chatView,
    ".onChange(of: requestedUserMessageJumpId)",
    "ChatView must respond to title popover jump requests from DashboardView"
)
assertContains(
    chatView,
    "for step in 0..<6",
    "selected user message should flash a few times after jumping"
)
assertContains(
    chatView,
    "isJumpHighlighted: highlightedMessageId == message.id && highlightedMessageFlashOn",
    "ChatBubble must receive the transient selected-message highlight state"
)

assertContains(
    chatBubble,
    "let isJumpHighlighted: Bool",
    "ChatBubble must accept an explicit jump-highlight flag"
)
assertContains(
    chatBubble,
    "Color.gray.opacity(0.42)",
    "jump highlight must use a deeper gray background"
)
assertContains(
    chatBubble,
    "isJumpHighlighted ? jumpHighlightBackgroundColor : bubbleBackgroundColor",
    "user bubble background must switch to the deep gray flash color while highlighted"
)

print("Session title user messages popover source verification passed")
