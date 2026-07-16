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
let messageModel = try read("OpenClawInstaller/Features/Chat/Models/ChatMessage.swift")
let viewModel = try read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")
let reconciliation = try read("OpenClawInstaller/Features/Chat/State/ChatRunReconciliation.swift")

let sendChatMessage = try slice(
    helpers,
    from: "func sendChatMessage(_ text: String, attachments: [URL] = []) async",
    to: "/// Move a foreground task to background"
)
let cancelChat = try slice(
    helpers,
    from: "func cancelChat(_ msgId: UUID)",
    to: "/// Filter out system prompt lines from openclaw agent output"
)
let moveTaskToBackground = try slice(
    helpers,
    from: "func moveTaskToBackground(_ msgId: UUID)",
    to: "/// Record cancellation intent separately"
)
let taskCleanup = try slice(
    viewModel,
    from: "func clearTaskTracking(_ msgId: UUID)",
    to: "/// Cancel every task (fg + bg) currently bound to `sessionId`"
)

try require(
    sendChatMessage.contains("let sessionKey = sessionKeyForAgent(currentAgentId, sessionId: currentSessionId)"),
    "sendChatMessage should compute the exact backend sessionKey at task creation."
)
try require(
    sendChatMessage.contains("let gatewayBinding = ChatGatewayRunBinding(") &&
        sendChatMessage.contains("sessionKey: sessionKey,") &&
        sendChatMessage.contains("startedAt: placeholderMsg.timestamp ?? Date()") &&
        sendChatMessage.contains("gatewayBinding: gatewayBinding"),
    "Normal chat tasks should capture their exact backend sessionKey and recovery start in the gateway binding."
)
try require(
    helpers.contains("sessionKey: run.gatewayBinding.sessionKey") &&
        reconciliation.contains("run.gatewayBinding.sessionKey == sessionKey") &&
        !cancelChat.contains("taskSid.map({ sessionKeyForAgent(taskAgent, sessionId: $0) })"),
    "cancelChat should use the current gateway binding instead of reconstructing a key from UI state."
)
try require(
    taskCleanup.contains("taskState.removeRun(messageId: msgId)"),
    "Task cleanup should remove the typed run, including its gateway binding."
)

try require(
    moveTaskToBackground.contains("let updated = msg.withTaskStatus(.background, content: content)") &&
        moveTaskToBackground.contains("messages[idx] = updated"),
    "moveTaskToBackground should preserve the original ChatMessage fields while changing status/content."
)
try require(
    !moveTaskToBackground.contains("messages[idx] = ChatMessage("),
    "moveTaskToBackground should not rebuild ChatMessage from a partial field list."
)
try require(
    messageModel.contains("func withTaskStatus(") &&
        messageModel.contains("attachments: attachments") &&
        messageModel.contains("timestamp: timestamp") &&
        messageModel.contains("completedAt: completedAt") &&
        messageModel.contains("activityEvents: activityEvents") &&
        messageModel.contains("scrollTargetId: scrollTargetId"),
    "ChatMessage should expose a status-copy helper that preserves attachments, timestamps, activity events, and scroll targets."
)

print("PASS: chat task identity and background preservation verified")
