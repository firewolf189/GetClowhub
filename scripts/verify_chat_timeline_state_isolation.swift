#!/usr/bin/env swift

import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) throws -> String {
    let url = root.appendingPathComponent(path)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CheckFailure(description: "Missing expected file: \(path)")
    }
    return try String(contentsOf: url, encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw CheckFailure(description: message)
    }
}

func slice(_ source: String, from start: String, to end: String) throws -> String {
    guard let startRange = source.range(of: start) else {
        throw CheckFailure(description: "Could not find slice start: \(start)")
    }
    if end == "***END***" {
        return String(source[startRange.lowerBound..<source.endIndex])
    }
    guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        throw CheckFailure(description: "Could not find slice end: \(end)")
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

let dashboard = try read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let timeline = try read("OpenClawInstaller/Features/Chat/Views/ChatTimelineSurface.swift")
let models = try read("OpenClawInstaller/Features/Chat/Models/ChatTimelineModels.swift")
let helpers = try read("OpenClawInstaller/Features/Chat/ChatHelpers.swift")
let chatViewModel = try read("OpenClawInstaller/Features/Chat/ViewModels/ChatViewModel.swift")
let dashboardViewModel = try read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")

let chatBubble = try slice(
    dashboard,
    from: "struct ChatBubble: View",
    to: "private struct InlineUserMessageEditor: View"
)
let chatScrollContent = try slice(
    dashboard,
    from: "private func chatScrollContent(proxy: ScrollViewProxy) -> some View",
    to: "/// Filtered slash commands based on current input"
)

try require(
    models.contains("struct ChatTimelineSnapshot: Equatable"),
    "ChatTimelineSnapshot should be an Equatable value boundary between chat state and SwiftUI timeline rendering."
)
try require(
    models.contains("struct ChatMessageRowModel: Identifiable, Equatable"),
    "ChatMessageRowModel should be the stable Equatable input for normal message rows."
)
try require(
    models.contains("struct ChatLoadingRowModel: Identifiable, Equatable"),
    "ChatLoadingRowModel should isolate loading indicator input from full ChatMessage values."
)
try require(
    models.contains("static func build(") &&
        models.contains("messages: [ChatMessage]") &&
        models.contains("highlightedMessageId: UUID?") &&
        models.contains("highlightedMessageFlashOn: Bool"),
    "ChatTimelineSnapshot should own conversion from persisted ChatMessage values to render rows."
)
try require(
    models.contains("MarkdownRenderPolicy.recentRichMessageIds(in: messages)"),
    "Rich markdown eligibility should be computed once while building the snapshot, not inside the timeline body."
)
try require(
    models.contains("loadingRows.append("),
    "Loading rows should be precomputed by the snapshot builder, not by filtering inside body."
)
try require(
    models.contains("runStatesByMessageId: [UUID: ChatRunPresentationState]") &&
        models.contains("let runState = runStatesByMessageId[message.id]") &&
        models.contains("runState: runState"),
    "The snapshot should project one immutable run presentation state per row before SwiftUI layout."
)

try require(
    !timeline.contains("let messages: [ChatMessage]"),
    "ChatTimelineSurface should not accept the complete persisted [ChatMessage] array directly."
)
try require(
    timeline.contains("let snapshot: ChatTimelineSnapshot"),
    "ChatTimelineSurface should accept a precomputed ChatTimelineSnapshot."
)
try require(
    !timeline.contains("@ObservedObject var taskState: TaskActivityState"),
    "ChatTimelineSurface should not observe the global task registry from the list render path."
)
try require(
    !timeline.contains("MarkdownRenderPolicy.recentRichMessageIds(in: messages)"),
    "ChatTimelineSurface.body should not scan all messages to compute rich markdown ids."
)
try require(
    !timeline.contains("ForEach(messages"),
    "ChatTimelineSurface.body should not ForEach over persisted ChatMessage values."
)
try require(
    !timeline.contains("messages.filter"),
    "ChatTimelineSurface.body should not filter messages during layout."
)
try require(
    timeline.contains("ForEach(snapshot.messageRows") &&
        timeline.contains("ForEach(snapshot.loadingRows"),
    "ChatTimelineSurface should render precomputed message and loading rows."
)

try require(
    chatScrollContent.contains("let timelineSnapshot = ChatTimelineSnapshot.build("),
    "ChatView should build a timeline snapshot before composing ChatTimelineSurface."
)
try require(
    chatScrollContent.contains("snapshot: timelineSnapshot"),
    "ChatView should pass the snapshot into ChatTimelineSurface."
)

try require(
    !chatBubble.contains("let message: ChatMessage\n") &&
        !chatBubble.contains("let message: ChatMessage\r\n"),
    "ChatBubble should not hold the complete persisted ChatMessage value as its primary render input."
)
try require(
    chatBubble.contains("let message: ChatMessageRowModel"),
    "ChatBubble should render from ChatMessageRowModel."
)
try require(
    !chatBubble.contains("((ChatMessage, String) -> Void)") &&
        !chatBubble.contains("((ChatMessage) -> Void)"),
    "ChatBubble action callbacks should not pass full ChatMessage values back up the tree."
)
try require(
    chatBubble.contains("var onConfirmEditResend: ((UUID, String) -> Void)?") &&
        chatBubble.contains("var onCancel: ((UUID) -> Void)?"),
    "ChatBubble should route actions by stable message id."
)

try require(
    helpers.contains("updateMessageIfChanged("),
    "Chat message updates should pass through an equality/identity-aware helper instead of always rewriting arrays."
)
try require(
    helpers.contains("guard messages[idx] != newMsg else { return }"),
    "updateMessage should skip no-op writes so @Published does not emit when row data is unchanged."
)
try require(
    !chatViewModel.contains(": ObservableObject") &&
        !chatViewModel.contains("objectWillChange") &&
        !dashboardViewModel.contains("chatViewModel.objectWillChange"),
    "Streaming and run-state publications must stop at their directly observed surfaces instead of invalidating DashboardViewModel."
)

print("PASS: chat timeline state isolation structure verified")
