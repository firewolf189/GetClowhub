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

let runtimeState = try read("OpenClawInstaller/Features/Chat/State/ChatRuntimeState.swift")
let streamState = try read("OpenClawInstaller/Features/Chat/Models/ChatStreamState.swift")
let timelineModels = try read("OpenClawInstaller/Features/Chat/Models/ChatTimelineModels.swift")
let dashboard = try read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let chatScrollContent = try slice(
    dashboard,
    from: "private func chatScrollContent(proxy: ScrollViewProxy) -> some View",
    to: "/// Filtered slash commands based on current input"
)

try require(
    streamState.contains("struct ChatActiveStreamState: Equatable"),
    "Active stream state should be a dedicated Equatable value type."
)
try require(
    streamState.contains("let messageId: UUID") &&
        streamState.contains("let visibleDraftText: String") &&
        streamState.contains("let activityEvents: [ChatActivityEvent]"),
    "Active stream state should separate visible draft text and activity events from persisted ChatMessage.content."
)
try require(
    runtimeState.contains("@Published var activeStreamStatesByMessageId: [UUID: ChatActiveStreamState] = [:]"),
    "ChatRuntimeState should own active stream render state separately from persisted chatMessagesByAgent."
)
try require(
    runtimeState.contains("func updateActiveStreamState(") &&
        runtimeState.contains("func clearActiveStreamState("),
    "ChatRuntimeState should expose named APIs for updating and clearing active stream state."
)
try require(
    timelineModels.contains("activeStreamStatesByMessageId: [UUID: ChatActiveStreamState]"),
    "ChatTimelineSnapshot.build should accept active stream state explicitly."
)
try require(
    timelineModels.contains("let activeStreamState = activeStreamStatesByMessageId[message.id]"),
    "Timeline snapshot should overlay the active stream state onto the matching message row by id."
)
try require(
    timelineModels.contains("visibleContent:") &&
        timelineModels.contains("activeStreamState?.visibleDraftText"),
    "Message row model should receive visible content derived from stream draft when present."
)
try require(
    timelineModels.contains("isStreamingDraft: activeStreamState != nil"),
    "Message row model should carry a streaming-draft flag for renderer policy and copy semantics."
)
try require(
    timelineModels.contains("activeStreamState == nil") &&
        timelineModels.contains("loadingRows.append"),
    "Empty loading placeholders should become ThinkingIndicator rows only when there is no visible active draft."
)
try require(
    chatScrollContent.contains("activeStreamStatesByMessageId: chatState.activeStreamStatesByMessageId"),
    "ChatView should pass active stream state into the timeline snapshot instead of mutating persisted messages for draft rendering."
)

print("PASS: chat stream state architecture verified")
