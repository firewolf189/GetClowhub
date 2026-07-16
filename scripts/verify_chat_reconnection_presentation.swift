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
    guard condition() else { throw CheckFailure(description: message) }
}

let models = try read("OpenClawInstaller/Features/Chat/Models/ChatTimelineModels.swift")
let timeline = try read("OpenClawInstaller/Features/Chat/Views/ChatTimelineSurface.swift")
let workStatus = try read("OpenClawInstaller/Features/Chat/Views/WorkStatusHeader.swift")
let taskState = try read("OpenClawInstaller/Features/Chat/State/TaskActivityState.swift")
let runState = try read("OpenClawInstaller/Features/Chat/Models/ChatRunState.swift")
let dashboard = try read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let viewModel = try read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")
let lifecycle = try read("OpenClawInstaller/Features/Chat/State/ChatRunLifecycleCoordinator.swift")
let localization = try read("OpenClawInstaller/Localization/Resources/Localizable.xcstrings")

try require(
    models.contains("runStatesByMessageId: [UUID: ChatRunPresentationState]") &&
        models.components(separatedBy: "let runState: ChatRunPresentationState?").count >= 3,
    "Timeline construction must project each run presentation state into its own message/loading row model."
)
try require(
    models.contains("runPhase?.isTerminal != false"),
    "Nonterminal rows must stay on lightweight rendering even when no draft text has arrived."
)
try require(
    !timeline.contains("@ObservedObject var taskState: TaskActivityState") &&
        timeline.contains("let onRetryConnection: (UUID) -> Void"),
    "The timeline must not observe the global run registry; retry should be routed by stable message id."
)
try require(
    workStatus.contains("let runState: ChatRunPresentationState?") &&
        workStatus.contains("case .reconnecting(let attempt, let maxAttempts)") &&
        workStatus.contains("case .reconciling") &&
        workStatus.contains("case .connectionLost") &&
        workStatus.contains("case .recoveryUnavailable"),
    "The work-status surface must present transport and run-reconciliation recovery phases."
)
try require(
    workStatus.contains("runState?.isRetryable == true") &&
        workStatus.contains("systemImage: \"arrow.clockwise\"") &&
        workStatus.contains("localized: \"Retry\""),
    "Only retryable transport/reconciliation states may expose the retry command."
)
try require(
    taskState.contains("func requestTransportRecoveryRetry() -> Int") &&
        taskState.contains("func requestRunReconciliationRetry(messageId: UUID) -> Bool") &&
        taskState.contains("runsByMessageId = updatedRuns"),
    "Transport retry must batch lost runs while reconciliation retry remains run-scoped."
)
try require(
    viewModel.contains("func retryChatConnection(for messageId: UUID)") &&
        viewModel.contains("taskState.requestTransportRecoveryRetry()") &&
        viewModel.contains("taskState.requestRunReconciliationRetry(messageId: messageId)") &&
        viewModel.contains("gatewayClient.$connectionState") &&
        viewModel.contains("handleGatewayConnectionState(state)") &&
        viewModel.contains("!gatewayClient.hasEventSubscription(") &&
        viewModel.contains("gatewayClient.connect()"),
    "The ViewModel must distinguish shared transport retry from one-run reconciliation retry and wake recovered runs after connection success."
)
try require(
    runState.contains("var keepsProcessActive: Bool") &&
        runState.contains("case .recoveryUnavailable, .connectionLost, .completed, .failed, .cancelled:") &&
        viewModel.contains("runs.values.contains(where: \\.keepsProcessActive)"),
    "An exhausted recoverable run must release App Nap suppression until manual retry."
)
try require(
    dashboard.contains("runStatesByMessageId:") &&
        dashboard.contains("onRetryConnection: viewModel.retryChatConnection"),
    "ChatView must supply value-only run presentation states and route retry through the ViewModel."
)
try require(
    !dashboard.contains("@State private var timer: Timer?") &&
        dashboard.contains("struct ThinkingIndicator: View, Equatable") &&
        lifecycle.contains("func scheduleAutomaticBackground(") &&
        viewModel.contains("chatRunLifecycleCoordinator.scheduleAutomaticBackground(") &&
        timeline.contains("ThinkingIndicator(") &&
        timeline.contains(".equatable()"),
    "Background deadlines must be owned outside the SwiftUI row lifecycle."
)
for key in ["Connecting", "Connection lost", "Reconnecting (%lld/%lld)", "Restoring response", "Cancelling", "Response recovery unavailable"] {
    try require(
        localization.contains("\"\(key)\" : {") &&
            localization.contains("\"zh-Hans\""),
        "Recovery status must be present in the string catalog: \(key)"
    )
}

print("PASS: chat reconnection presentation verified")
