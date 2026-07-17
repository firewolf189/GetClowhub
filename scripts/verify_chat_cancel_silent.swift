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
let chatHelpers = try read("OpenClawInstaller/Features/Chat/ChatHelpers.swift")

let abortBranch = slice(
    chatHelpers,
    from: "case .aborted(let eventRunId, _):",
    to: "case .error(let eventRunId, _, let message):"
)
let cancelChat = slice(
    chatHelpers,
    from: "func cancelChat(_ msgId: UUID)",
    to: "/// Filter out system prompt lines"
)
let chatBubble = slice(
    dashboard,
    from: "struct ChatBubble: View",
    to: "struct InlineUserMessageEditor: View"
)

require(!abortBranch.contains("Task cancelled"), "aborted stream branch should not append cancellation text")
// Streaming progress text now lives in activity events (working header), so
// an aborted turn keeps its transcript via activityEvents and leaves the
// assistant body empty instead of dumping accumulated stream text into it.
require(abortBranch.contains("content: \"\", status: .cancelled"), "aborted stream branch should mark the message cancelled without injecting body text")
require(abortBranch.contains("activityEvents: accumulatedActivityEvents"), "aborted stream branch should preserve the accumulated activity transcript")
require(abortBranch.contains("clearActiveStreamState(msgId)"), "aborted stream branch should clear active draft state")
require(!cancelChat.contains("Task cancelled"), "manual cancel should not append cancellation text")
require(cancelChat.contains("content: msg.content"), "manual cancel should keep existing assistant content")
require(!chatBubble.contains("Text(\"Cancelled\")"), "chat bubble should not render a Cancelled status label")
require(!chatBubble.contains("taskStatus == .cancelled"), "chat bubble should not render a cancelled status row")

print("PASS: silent chat cancellation contracts verified")
