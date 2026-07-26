import Foundation

// Text selection in the chat, after two architectural reversals — read the
// history before "fixing" this file:
//
//   1. Originally each message hosted an NSTextView (`NativeSelectableMarkdownView`)
//      so a drag selected directly and spanned blocks. That per-row AppKit host
//      is what fed the SwiftUI<->AppKit AutoLayout livelock (five freezes,
//      2026-07-21..24), so it was removed.
//   2. MarkdownUI replaced it. Rendering is now pure SwiftUI, but MarkdownUI
//      draws each block as its own view and `.textSelection` cannot span
//      sibling views — dragging from a paragraph into a list selected only the
//      paragraph (verified 2026-07-26).
//   3. Fix: an opt-in per-message mode that collapses the whole message into
//      ONE `Text`, which restores continuous cross-block selection without
//      re-introducing an AppKit host.
//
// So this file guards two things at once: selection must reach across blocks,
// and it must not do so by hosting a platform view per message.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fail(message) }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assistantURL = root.appendingPathComponent("OpenClawInstaller/Features/Chat/Markdown/AssistantMessageRenderer.swift")
let dashboardURL = root.appendingPathComponent("OpenClawInstaller/Features/Dashboard/DashboardView.swift")

let assistant = try String(contentsOf: assistantURL, encoding: .utf8)
let dashboard = try String(contentsOf: dashboardURL, encoding: .utf8)

func slice(_ text: String, from start: String, to end: String) -> String {
    guard let startRange = text.range(of: start),
          let endRange = text[startRange.upperBound...].range(of: end) else {
        fail("could not slice source from \(start) to \(end)")
    }
    return String(text[startRange.lowerBound..<endRange.lowerBound])
}

let assistantContent = slice(
    assistant,
    from: "struct AssistantMessageContentView: View",
    to: "// MARK: - Cross-Block Selectable Message"
)
let crossBlock = slice(
    assistant,
    from: "struct CrossBlockSelectableMessageText: View",
    to: "// MARK: - Native Markdown View"
)
let chatBubble = slice(
    dashboard,
    from: "struct ChatBubble: View",
    to: "private struct InlineUserMessageEditor"
)

// --- No platform view may host message text (the livelock) ---
require(
    !assistant.contains("NSViewRepresentable"),
    "message text must not be hosted in an AppKit view — that is the SwiftUI<->AppKit layout livelock"
)
require(
    !assistant.contains("NativeSelectableMarkdownView"),
    "the deleted NSTextView bridge must not come back; use CrossBlockSelectableMessageText"
)

// --- Cross-block selection must exist and be a single Text ---
require(!crossBlock.isEmpty, "CrossBlockSelectableMessageText should exist")
require(
    crossBlock.contains("Text(attributedContent)") && crossBlock.contains(".textSelection(.enabled)"),
    "cross-block selection works by rendering the whole message as ONE selectable Text"
)
require(
    crossBlock.contains("interpretedSyntax: .inlineOnlyPreservingWhitespace"),
    "block-level markdown parsing would split the message back into sibling views"
)
require(
    crossBlock.contains("strippingCodeFences"),
    "``` fences must be stripped before inline parsing, or fenced code collapses onto one line and copying loses the line breaks"
)
require(
    assistantContent.contains("prefersFullMessageSelection") && assistantContent.contains("CrossBlockSelectableMessageText("),
    "AssistantMessageContentView should route to the cross-block renderer when asked"
)

// --- The mode is opt-in per bubble, and must stay OUT of shared state ---
require(
    chatBubble.contains("@State private var prefersFullMessageSelection = false"),
    "the selection mode should be local bubble state so toggling it re-renders one row, not the whole timeline"
)
require(
    chatBubble.contains("prefersFullMessageSelection.toggle()"),
    "the user needs an affordance to enter/leave cross-block selection"
)
require(
    !dashboard.contains("activeNativeTextSelectionMessageId"),
    "dashboard should not keep per-message selection state (it invalidates the memoized timeline snapshot)"
)

// --- Ordinary reading paths stay selectable ---
require(
    assistantContent.contains(".textSelection(.enabled)"),
    "rendered assistant text must stay selectable (within a block) without entering the mode"
)
require(
    chatBubble.contains("Text(verbatim: message.content)") && chatBubble.contains(".textSelection(.enabled)"),
    "user messages are one Text already — they must stay natively selectable"
)

print("direct-selection guards hold: cross-block selection without an AppKit host")
