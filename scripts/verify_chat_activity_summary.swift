#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

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

let dashboard = try read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let viewModel = try read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")
let chatHelpers = try read("OpenClawInstaller/Features/Chat/ChatHelpers.swift")
let chatMessageModel = try read("OpenClawInstaller/Features/Chat/Models/ChatMessage.swift")
let activityModel = try read("OpenClawInstaller/Features/Chat/Models/ChatActivityEvent.swift")

let chatMessage = slice(
    chatMessageModel,
    from: "struct ChatMessage: Identifiable, Codable",
    to: "enum ChatRole"
)
let sendLoop = slice(
    chatHelpers,
    from: "var accumulatedText = \"\"",
    to: "// Stream ended without a terminal event"
)
// WorkStatusHeader (and ActivitySummaryRows) were extracted into their own file.
let workStatusHeader = try read("OpenClawInstaller/Features/Chat/Views/WorkStatusHeader.swift")
let chatBubble = slice(
    dashboard,
    from: "struct ChatBubble: View",
    to: "private struct InlineUserMessageEditor: View"
)

require(chatMessage.contains("let activityEvents: [ChatActivityEvent]"), "ChatMessage should persist activity events")
require(chatMessage.contains("activityEvents: [ChatActivityEvent] = []"), "ChatMessage should default activity events for old sessions")

require(activityModel.contains("struct ChatActivityEvent: Identifiable, Codable, Equatable"), "activity events should be codable model data")
require(activityModel.contains("let details: [String]"), "activity events should retain all structured detail strings")
require(activityModel.contains("case progressUpdate"), "activity events should support model-authored progress updates")
require(chatHelpers.contains("appendProgressActivityText"), "dashboard should move stream progress text into working activity events")
require(sendLoop.contains("var committedWorkingText = \"\""), "stream loop should track committed working-progress text")
require(sendLoop.contains("Self.visibleAssistantText(") && sendLoop.contains("committedWorkingText: committedWorkingText"), "final assistant body should be separated from committed working progress text")
require(sendLoop.contains("activityEventsForDisplay("), "streaming deltas should preview model progress text in working events")
require(sendLoop.contains("updateActiveStreamState("), "streaming progress text should update active draft state instead of persisted assistant final body")
require(!sendLoop.contains("updateMessage(msgId: msgId, content: accumulatedText"), "streaming progress text should not persist raw accumulated provider text as assistant final body")
require(chatHelpers.contains("private func mergeActivityEvent(_ event: GatewayActivityEvent, into events: inout [ChatActivityEvent])"), "activity events should merge from structured gateway events")
require(chatHelpers.contains("details: event.detail.map { existing.details + [$0] } ?? existing.details"), "activity merge should append every available detail")
require(viewModel.contains("messagesHaveSameActivityEvents"), "session persistence should compare activity events before skipping writes")
require(activityModel.contains("init(gatewayKind: GatewayActivityEvent.Kind)"), "chat activity kinds should map from gateway activity kinds")
require(!chatHelpers.contains("enum ChatActivityExtractor"), "activity should not be extracted from assistant response text")
require(!chatHelpers.contains("summary prompt"), "activity should not build model summary prompts")

require(sendLoop.contains("var accumulatedActivityEvents: [ChatActivityEvent] = []"), "stream loop should keep accumulated activity events")
require(sendLoop.contains("case .activity(let eventRunId, _, let event):"), "stream loop should consume structured gateway activity events")
require(sendLoop.contains("mergeActivityEvent(event, into: &accumulatedActivityEvents)"), "stream loop should merge structured gateway activity events")
require(sendLoop.contains("activityEvents: accumulatedActivityEvents"), "stream terminal updates should attach activity events to the assistant message")
require(sendLoop.contains("activityEvents: displayEvents"), "streaming draft updates should attach activity events to active stream state")

require(workStatusHeader.contains("let activityEvents: [ChatActivityEvent]"), "working header should accept activity events")
require(workStatusHeader.contains("@State private var isExpanded = false"), "working header should be collapsed by default")
require(workStatusHeader.contains("Button {"), "working header chevron should be clickable")
require(workStatusHeader.contains("isExpanded.toggle()"), "working header should toggle activity visibility")
require(workStatusHeader.contains("if isExpanded {"), "working header should hide activity rows while collapsed")
require(workStatusHeader.contains("ActivitySummaryRows(events: activityEvents)"), "working header should render activity rows when expanded")
require(workStatusHeader.contains("private struct ActivitySummaryRows: View"), "activity summary rows should be defined alongside the working header")
require(!workStatusHeader.contains("events.prefix(4)"), "activity rows should not cap visible event categories")
require(!workStatusHeader.contains("events.count > 4"), "activity rows should not show a capped more row")
require(workStatusHeader.contains("event.kind == .progressUpdate"), "working header should render progress text as transcript text")
require(workStatusHeader.contains("event.details"), "activity rows should render structured details")
require(workStatusHeader.contains("@State private var expandedDetailKeys: Set<String> = []"), "activity detail rows should keep local disclosure state")
require(workStatusHeader.contains("private struct ActivitySummaryRow: View"), "activity rows with details should have a dedicated collapsible row view")
require(workStatusHeader.contains("private var disclosureKey: String { event.kind.rawValue }"), "activity detail disclosure state should use a stable kind key")
require(workStatusHeader.contains("Image(systemName: \"chevron.right\")"), "activity rows with details should expose a disclosure chevron")
require(workStatusHeader.contains("if hasDetails && isExpanded"), "activity details should render only after row disclosure")
require(chatBubble.contains("WorkStatusHeader(")
        && chatBubble.contains("start: message.timestamp")
        && chatBubble.contains("end: message.completedAt")
        && chatBubble.contains("activityEvents: message.activityEvents"),
        "chat bubble should pass message activities into the header")

print("PASS: chat activity summary contracts verified")
