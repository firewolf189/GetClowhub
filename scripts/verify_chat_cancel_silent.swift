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
let reconciliation = try read("OpenClawInstaller/Features/Chat/State/ChatRunReconciliation.swift")
let gateway = try read("OpenClawInstaller/Core/Gateway/GatewayClient.swift")
let abortRegistry = try read("OpenClawInstaller/Core/Gateway/GatewayChatAbortRequestRegistry.swift")
let mainStreamLoop = slice(
    chatHelpers,
    from: "streamLoop: for await event in eventStream",
    to: "/// Move a foreground task to background"
)

let abortBranch = slice(
    mainStreamLoop,
    from: "case .aborted(let eventRunId, let eventSessionKey):",
    to: "case .error(let eventRunId, let eventSessionKey, let message):"
)
let cancelChat = slice(
    chatHelpers,
    from: "func cancelChat(_ msgId: UUID)",
    to: "/// Filter out system prompt lines"
)
let imageReviewBatch = slice(
    chatHelpers,
    from: "private func runLocalImageReviewBatch(",
    to: "private func runLocalImageReviewChunk("
)
let imageReviewChunk = slice(
    chatHelpers,
    from: "private func runLocalImageReviewChunk(",
    to: "private func localImageReviewProgressMessage("
)
let chatBubble = slice(
    dashboard,
    from: "struct ChatBubble: View",
    to: "struct InlineUserMessageEditor: View"
)

require(!abortBranch.contains("Task cancelled"), "aborted stream branch should not append cancellation text")
require(abortBranch.contains("finishCancelledChatRun(msgId)"), "aborted events should enter the centralized cancellation terminalizer")
require(!cancelChat.contains("Task cancelled"), "manual cancel should not append cancellation text")
require(
    cancelChat.contains("event: .cancellationRequested") &&
        cancelChat.contains("scheduleCancellation(messageId: msgId)"),
    "manual cancellation must record intent before requesting a backend abort"
)
require(
    gateway.contains("async -> GatewayChatAbortResult") &&
        gateway.contains("chatAbortRequestRegistry.resolve(") &&
        abortRegistry.contains("guard aborted else { return .notRunning }") &&
        abortRegistry.contains("guard runIds.contains(expectedRunId) else { return .notRunning }") &&
        reconciliation.contains("abortResult.isConfirmed") &&
        chatHelpers.contains("result.isConfirmed"),
    "cancellation may terminalize only after chat.abort confirms the exact run id"
)
require(
    reconciliation.contains("case .cancelled:") &&
        reconciliation.contains("content = streamState?.visibleDraftText ?? existingMessage?.content ?? \"\"") &&
        reconciliation.contains("taskStatus = .cancelled") &&
        reconciliation.contains("clearTaskTracking(messageId)"),
    "confirmed cancellation must preserve visible text and clear runtime state centrally"
)
require(
    imageReviewChunk.contains("taskState.run(for: msgId) == nil") &&
        imageReviewChunk.contains("return (\"cancelled\", accumulatedText)"),
    "ending an image-review event stream after cancellation should remain cancelled, not become failed"
)
require(
    chatHelpers.contains("private func canContinueChatRunAfterPreflight(") &&
        chatHelpers.components(separatedBy: "guard canContinueChatRunAfterPreflight(").count == 3 &&
        chatHelpers.contains("run.gatewayBinding.idempotencyKey == idempotencyKey"),
    "late preflight results must revalidate exact run ownership before changing UI or batch state"
)
require(
    imageReviewBatch.contains("if result.status == \"cancelled\"") &&
        imageReviewBatch.contains("status: .cancelled"),
    "the image-review batch must preserve cancellation as its own terminal outcome"
)
require(!chatBubble.contains("Text(\"Cancelled\")"), "chat bubble should not render a Cancelled status label")
require(!chatBubble.contains("taskStatus == .cancelled"), "chat bubble should not render a cancelled status row")

print("PASS: silent chat cancellation contracts verified")
