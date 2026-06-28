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

let dashboard = try read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let viewModel = try read("OpenClawInstaller/ViewModels/DashboardViewModel.swift")

let chatMessage = slice(
    viewModel,
    from: "struct ChatMessage: Identifiable, Codable",
    to: "// MARK: - Skill Info"
)
let sendLoop = slice(
    viewModel,
    from: "var accumulatedText = \"\"",
    to: "// Stream ended without a terminal event"
)
let workStatusHeader = slice(
    dashboard,
    from: "private struct WorkStatusHeader: View",
    to: "struct ChatBubble: View"
)
let chatBubble = slice(
    dashboard,
    from: "struct ChatBubble: View",
    to: "struct InlineUserMessageEditor: View"
)

require(chatMessage.contains("let activityEvents: [ChatActivityEvent]"), "ChatMessage should persist activity events")
require(chatMessage.contains("activityEvents: [ChatActivityEvent] = []"), "ChatMessage should default activity events for old sessions")

require(viewModel.contains("struct ChatActivityEvent: Identifiable, Codable, Equatable"), "activity events should be codable model data")
require(viewModel.contains("let details: [String]"), "activity events should retain all structured detail strings")
require(viewModel.contains("case progressUpdate"), "activity events should support model-authored progress updates")
require(viewModel.contains("appendProgressActivityText"), "dashboard should move stream progress text into working activity events")
require(sendLoop.contains("var committedWorkingText = \"\""), "stream loop should track committed working-progress text")
require(sendLoop.contains("Self.visibleAssistantText(") && sendLoop.contains("committedWorkingText: committedWorkingText"), "final assistant body should be separated from committed working progress text")
require(sendLoop.contains("activityEventsForDisplay("), "streaming deltas should preview model progress text in working events")
require(sendLoop.contains("updateMessage(msgId: msgId, content: \"\", status: current.taskStatus"), "streaming progress text should not render as assistant final body")
require(viewModel.contains("private func mergeActivityEvent(_ event: GatewayActivityEvent, into events: inout [ChatActivityEvent])"), "activity events should merge from structured gateway events")
require(viewModel.contains("details: event.detail.map { existing.details + [$0] } ?? existing.details"), "activity merge should append every available detail")
require(viewModel.contains("messagesHaveSameActivityEvents"), "session persistence should compare activity events before skipping writes")
require(viewModel.contains("init(gatewayKind: GatewayActivityEvent.Kind)"), "chat activity kinds should map from gateway activity kinds")
require(!viewModel.contains("enum ChatActivityExtractor"), "activity should not be extracted from assistant response text")
require(!viewModel.contains("summary prompt"), "activity should not build model summary prompts")

require(sendLoop.contains("var accumulatedActivityEvents: [ChatActivityEvent] = []"), "stream loop should keep accumulated activity events")
require(sendLoop.contains("case .activity(let eventRunId, _, let event):"), "stream loop should consume structured gateway activity events")
require(sendLoop.contains("mergeActivityEvent(event, into: &accumulatedActivityEvents)"), "stream loop should merge structured gateway activity events")
require(sendLoop.contains("activityEvents: accumulatedActivityEvents"), "stream updates should attach activity events to the assistant message")

require(workStatusHeader.contains("let activityEvents: [ChatActivityEvent]"), "working header should accept activity events")
require(workStatusHeader.contains("@State private var isExpanded = false"), "working header should be collapsed by default")
require(workStatusHeader.contains("Button {"), "working header chevron should be clickable")
require(workStatusHeader.contains("isExpanded.toggle()"), "working header should toggle activity visibility")
require(workStatusHeader.contains("if isExpanded {"), "working header should hide activity rows while collapsed")
require(workStatusHeader.contains("ActivitySummaryRows(events: activityEvents)"), "working header should render activity rows when expanded")
require(dashboard.contains("private struct ActivitySummaryRows: View"), "dashboard should define activity summary rows")
require(!dashboard.contains("events.prefix(4)"), "activity rows should not cap visible event categories")
require(!dashboard.contains("events.count > 4"), "activity rows should not show a capped more row")
require(dashboard.contains("event.kind == .progressUpdate"), "working header should render progress text as transcript text")
require(dashboard.contains("event.details"), "activity rows should render structured details")
require(chatBubble.contains("WorkStatusHeader(")
        && chatBubble.contains("start: message.timestamp")
        && chatBubble.contains("end: message.completedAt")
        && chatBubble.contains("activityEvents: message.activityEvents"),
        "chat bubble should pass message activities into the header")

print("PASS: chat activity summary contracts verified")
