import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func source(_ relativePath: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let reconciliation = try source("OpenClawInstaller/Features/Chat/State/ChatRunReconciliation.swift")
let helpers = try source("OpenClawInstaller/Features/Chat/ChatHelpers.swift")
let inFlight = try source("OpenClawInstaller/Features/Dashboard/InFlightRuns.swift")
let viewModel = try source("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")

require(
        reconciliation.contains("func scheduleChatRunReconciliation(messageId: UUID)") &&
        reconciliation.contains("func reconcileChatRun(messageId: UUID) async") &&
        reconciliation.contains("fetchChatRunStatus(runId: runId)") &&
        reconciliation.contains("fetchChatRecoverySnapshot(sessionKey: sessionKey)"),
    "one per-run coordinator must own status/history reconciliation"
)
require(
    reconciliation.contains("run.expectedRunId == expectedRunId") &&
        reconciliation.contains("run.gatewayBinding.sessionKey == sessionKey"),
    "every asynchronous reconciliation result must be revalidated against run and session identity"
)
require(
    reconciliation.contains("case .failed") &&
        reconciliation.contains("case .cancelled") &&
        reconciliation.contains("case .complete") &&
        reconciliation.contains("case .awaitingAuthoritativeState"),
    "the coordinator must preserve all authoritative run outcomes"
)
require(
    !helpers.contains("fetchLastAssistantMessage(sessionKey: eventSessionKey)") &&
        !helpers.contains("case .unrecoverable"),
    "live chat recovery must not guess from the latest assistant text or use the legacy unrecoverable branch"
)
require(
    inFlight.contains("scheduleChatRunReconciliation(messageId: entry.msgId)") &&
        !inFlight.contains("latestBySession") &&
        !inFlight.contains("fetchLastAssistantMessage"),
    "crash recovery must reuse the run-specific coordinator instead of latest-message heuristics"
)
require(
    viewModel.contains("requestRunReconciliationRetry(messageId: messageId)") &&
        viewModel.contains("scheduleChatRunReconciliation(messageId: messageId)"),
    "manual retry must distinguish per-run reconciliation from shared transport retry"
)

print("PASS: chat run reconciliation coordinator")
