#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func source(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
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

let state = try source("OpenClawInstaller/Features/Chat/Models/ChatRunState.swift")
let reconciliation = try source("OpenClawInstaller/Features/Chat/State/ChatRunReconciliation.swift")
let helpers = try source("OpenClawInstaller/Features/Chat/ChatHelpers.swift")
let viewModel = try source("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")
let imageChunk = slice(
    helpers,
    from: "private func runLocalImageReviewChunk(",
    to: "private func localImageReviewProgressMessage("
)
let imageBatch = slice(
    helpers,
    from: "private func runLocalImageReviewBatch(",
    to: "private func runLocalImageReviewChunk("
)
let supersededBranch = slice(
    imageChunk,
    from: "case .superseded:",
    to: "case .suspended:"
)
let retryWait = slice(
    helpers,
    from: "private func waitForLocalImageReviewRetry(",
    to: "private func localImageReviewProgressMessage("
)
let sendPath = slice(
    helpers,
    from: "func sendChatMessage(",
    to: "func moveTaskToBackground("
)

require(
    state.contains("enum ChatRunExecutionKind") &&
        state.contains("case conversation") &&
        state.contains("case localImageReviewBatch"),
    "the run registry must distinguish visible conversation runs from orchestrated child runs"
)
require(
    reconciliation.contains("func reconcileChatRunOutcome(messageId: UUID) async -> ChatRunReconciliationResult") &&
        reconciliation.contains("case terminal(ChatRunTerminalOutcome)") &&
        reconciliation.contains("case suspended"),
    "authoritative reconciliation must return an owner-neutral result before UI terminalization"
)
require(
    reconciliation.contains("initialRun.executionKind == .conversation") &&
        reconciliation.contains("finishChatRun(messageId: messageId, outcome: outcome)"),
    "only conversation-owned reconciliation may terminalize the visible message directly"
)
require(
    sendPath.contains("let isLocalImageReviewBatch = ImageReviewBatchStore.isImageReviewBatchCandidate(") &&
        sendPath.contains("executionKind: isLocalImageReviewBatch ? .localImageReviewBatch : .conversation") &&
        sendPath.components(separatedBy: "ImageReviewBatchStore.isImageReviewBatchCandidate(").count == 2,
    "the immutable run execution kind must be decided once before registration"
)
require(
    imageChunk.contains("reconcileLocalImageReviewChunk(") &&
        imageChunk.contains("reconcileChatRunOutcome(messageId: messageId)") &&
        imageChunk.contains("waitForLocalImageReviewRetry("),
    "image child runs must consume the shared reconciler and preserve suspension for manual retry"
)
require(
    imageChunk.contains("recordImageRunEventDelivery(") &&
        imageChunk.contains("submissionAttemptCount < ChatRunDeliveryPolicy.maximumSubmissionAttempts") &&
        imageChunk.contains("idempotencyKey: idempotencyKey"),
    "image child delivery must use the same evidence-gated idempotent retry policy as conversation runs"
)
require(
    !imageChunk.contains("fetchChatRunReconciliationDecision(") &&
        !imageChunk.contains("return (\"failed\", accumulatedText.isEmpty ? \"Connection interrupted"),
    "image review must not retain a one-shot history branch or classify stream closure as failure"
)
require(
    supersededBranch.contains("if Task.isCancelled") &&
        supersededBranch.contains("Local image review run identity changed during recovery."),
    "task cancellation and a genuine child identity replacement must remain distinct"
)
require(
    retryWait.contains("if gatewayClient.isConnected") &&
        retryWait.contains("return true"),
    "a child waiting without an event subscription must observe transport recovery directly"
)
require(
    imageBatch.components(separatedBy: "finishChatRun(").count >= 5 &&
        imageBatch.contains("outcome: .completed(") &&
        imageBatch.contains("outcome: .cancelled") &&
        imageBatch.contains("outcome: .failed(") &&
        !imageBatch.contains("clearTaskTracking(msgId)"),
    "the batch must remain the parent terminal owner and use the centralized terminalizer"
)
require(
    viewModel.contains("run.executionKind == .conversation") &&
        viewModel.contains("let conversationRunIds") &&
        viewModel.contains("scheduleChatRunReconciliation(messageId: messageId)"),
    "shared transport recovery must schedule only conversation-owned runs without live subscribers"
)

print("PASS: image review run reconciliation architecture")
