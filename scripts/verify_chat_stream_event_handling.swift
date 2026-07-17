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

let helpers = try read("OpenClawInstaller/Features/Chat/ChatHelpers.swift")
let viewModel = try read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")
let renderer = try read("OpenClawInstaller/Features/Chat/Markdown/AssistantMessageRenderer.swift")

let mainStreamLoop = try slice(
    helpers,
    from: "streamLoop: for await event in eventStream",
    to: "// Stream ended without a terminal event"
)
let deltaCase = try slice(
    mainStreamLoop,
    from: "case .delta(let eventRunId, let eventSessionKey, let text):",
    to: "case .final_(let eventRunId, let eventSessionKey, let text):"
)
let finalCase = try slice(
    mainStreamLoop,
    from: "case .final_(let eventRunId, let eventSessionKey, let text):",
    to: "case .aborted(let eventRunId, _):"
)
let cleanup = try slice(
    viewModel,
    from: "func clearTaskTracking(_ msgId: UUID)",
    to: "func cancelTasks(inSession sessionId: UUID)"
)
let markdownPolicy = try slice(
    renderer,
    from: "static func mode(for content: String, isStreaming: Bool, allowsWebView: Bool = true) -> MarkdownRenderMode",
    to: "static func shouldApplyMeasuredHeight"
)
let assistantView = try slice(
    renderer,
    from: "struct AssistantMessageContentView: View",
    to: "// MARK: - Native Markdown View"
)

try require(
    deltaCase.contains("updateActiveStreamState("),
    "Delta events should update active stream draft state."
)
try require(
    helpers.contains("var lastUpdateTime = Date.distantPast"),
    "The first text delta should render immediately before later updates are throttled."
)
try require(
    deltaCase.contains("visibleDraftText: Self.visibleAssistantText("),
    "Delta events should expose visible draft text after removing committed working text."
)
try require(
    !deltaCase.contains("updateMessage(msgId: msgId, content: \"\""),
    "Delta events should not hide assistant draft content by writing an empty message body."
)
try require(
    !deltaCase.contains("updateMessage(msgId: msgId, content: accumulatedText") &&
        !deltaCase.contains("updateMessage(msgId: msgId, content: text"),
    "Delta events should not write raw accumulated provider text into persisted ChatMessage.content."
)
try require(
    finalCase.contains("clearActiveStreamState(msgId)") &&
        finalCase.contains("updateMessage(msgId: msgId, content: finalText, status: .completed"),
    "Final events should clear draft state and then write the final persisted assistant body."
)
try require(
    cleanup.contains("clearActiveStreamState(msgId)"),
    "Task cleanup should clear active stream state for completed, cancelled, timed-out, and failed tasks."
)
try require(
    markdownPolicy.contains("if isStreaming { return .native }"),
    "Streaming rows should stay on the native renderer and never mount WKWebView."
)
try require(
    assistantView.contains("parsesMarkdown: !renderModel.isStreaming"),
    "Streaming rows should render visible draft as plain/native text without markdown parsing."
)

print("PASS: chat stream event handling verified")
