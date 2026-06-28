import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fail(message) }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assistantURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/AssistantMessageRenderer.swift")
let dashboardURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/DashboardView.swift")

let assistant = try String(contentsOf: assistantURL)
let dashboard = try String(contentsOf: dashboardURL)

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
    to: "// MARK: - Native Markdown View"
)
let nativeMarkdown = slice(
    assistant,
    from: "struct NativeMarkdownView: View",
    to: "struct NativeSelectableMarkdownView"
)
let chatBubble = slice(
    dashboard,
    from: "struct ChatBubble: View",
    to: "private struct InlineUserMessageEditor"
)

require(
    !nativeMarkdown.contains(".textSelection(.enabled)"),
    "ordinary native markdown must not use SwiftUI Text.textSelection overlay"
)
require(
    assistantContent.contains("NativeSelectableMarkdownView("),
    "assistant text should remain directly selectable through the native selectable renderer"
)
require(
    !assistantContent.contains("prefersNativeTextSelection"),
    "direct selection should not depend on per-message selection mode state"
)
require(
    chatBubble.contains("NativeSelectableMarkdownView(\n") &&
        chatBubble.contains("parsesMarkdown: false"),
    "user messages should remain directly selectable without SwiftUI Text.textSelection"
)
require(
    !chatBubble.contains("selection.pin.in.out") &&
        !chatBubble.contains("选择文本") &&
        !chatBubble.contains("toggleSelectionMode"),
    "single-message selection mode controls should be removed"
)
require(
    !dashboard.contains("activeNativeTextSelectionMessageId"),
    "dashboard should not keep single-message selection state"
)

print("Direct selectable rendering avoids SwiftUI selection overlay")
