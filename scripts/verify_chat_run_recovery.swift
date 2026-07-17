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

let gateway = try read("OpenClawInstaller/Core/Gateway/GatewayClient.swift")
let helpers = try read("OpenClawInstaller/Features/Chat/ChatHelpers.swift")
let persistedRuns = try read("OpenClawInstaller/Features/Dashboard/InFlightRuns.swift")
let reconciliation = try read("OpenClawInstaller/Features/Chat/State/ChatRunReconciliation.swift")
let policy = try read("OpenClawInstaller/Features/Chat/State/ChatRunReconciliationPolicy.swift")
let localization = try read("OpenClawInstaller/Localization/Resources/Localizable.xcstrings")

try require(
    gateway.contains("CheckedContinuation<GatewayChatRecoverySnapshot?, Never>") &&
        gateway.contains("func fetchChatRecoverySnapshot(sessionKey: String) async -> GatewayChatRecoverySnapshot?"),
    "chat.history must resolve a typed recovery snapshot instead of only the last assistant string."
)
for field in ["inFlightRun", "hasActiveRun", "assistantMessages"] {
    try require(gateway.contains(field), "Gateway recovery parsing is missing \(field).")
}
try require(
    !gateway.contains("fetchLastAssistantMessage") &&
        !gateway.contains("latestAssistantText"),
    "Recovery must not expose an unbound latest-assistant-message shortcut."
)
try require(
    gateway.contains("idempotencyKey: String") &&
        gateway.contains("async -> GatewayChatSendResult"),
    "chat.send must receive a caller-owned stable idempotency key and return a typed delivery outcome."
)
try require(
    helpers.contains("case .deliveryUnconfirmed(let expectedRunId)") &&
        helpers.contains("case .transport(.connected)") &&
        helpers.contains("submissionAttemptCount < ChatRunDeliveryPolicy.maximumSubmissionAttempts") &&
        helpers.contains("idempotencyKey: gatewayBinding.idempotencyKey") &&
        helpers.contains("activeRun.runId == nil") &&
        helpers.contains("recordRunEventDelivery(eventRunId)") &&
        helpers.contains("scheduleChatRunReconciliation(messageId: msgId)"),
    "Reconnect may retry only an unacknowledged, evidence-free submission with the original idempotency key."
)
try require(
    !helpers.contains("let inactivityLimit: TimeInterval") &&
        !helpers.contains("let recoveryDeadline = Date().addingTimeInterval(30)"),
    "Foreground run lifetime must not be terminated by fixed client-side total or recovery deadlines."
)
try require(
    persistedRuns.contains("scheduleChatRunReconciliation(messageId: entry.msgId)") &&
        !persistedRuns.contains("latestBySession") &&
        !persistedRuns.contains("historyBaseline"),
    "Launch recovery must use the same run-aware typed reconciliation rules."
)
try require(
    persistedRuns.contains("let deliveryAcknowledged: Bool?") &&
        persistedRuns.contains("func registerInFlightRun(_ run: ChatRunState") &&
        persistedRuns.contains("deliveryAcknowledged: run.runId != nil") &&
        persistedRuns.contains("startedAt: run.gatewayBinding.startedAt") &&
        persistedRuns.contains("runId: entry.deliveryAcknowledged == false ? nil : entry.runId"),
    "Crash recovery must preserve whether the stable run identity was actually acknowledged."
)
try require(
    persistedRuns.contains("msg.withTaskStatus(.timedOut, content: content)") &&
        reconciliation.contains("attachments: message.attachments") &&
        reconciliation.contains("scrollTargetId: message.scrollTargetId"),
    "Recovery terminalization must preserve the latest persisted message metadata."
)
try require(
    policy.contains("backgroundHardLimit: TimeInterval = 60 * 60") &&
        reconciliation.contains("scheduleBackgroundRunHardDeadline") &&
        reconciliation.contains("expireBackgroundChatRun"),
    "Crash-recovery tasks need a bounded background lifetime without reintroducing a foreground timeout."
)
try require(
    policy.contains("unregisteredRunGracePeriod: TimeInterval = 60") &&
        reconciliation.contains("currentRun.runId == nil") &&
        reconciliation.contains("observation.status.indicatesNoRegisteredRun") &&
        reconciliation.contains("ChatRunDeliveryPolicy.unregisteredRunGracePeriod"),
    "Only an unacknowledged send with authoritative missing-run evidence may leave infinite foreground polling."
)
try require(
    reconciliation.contains("switch gatewayClient.connectionState") &&
        reconciliation.contains("case .reconnecting(let attempt, let maximum):") &&
        reconciliation.contains("case .recoveryExhausted(let attempts):") &&
        reconciliation.contains("event: .recoveryExhausted(attempts: attempts)"),
    "Launch-recovered runs without an event stream must still project transport exhaustion and expose manual retry."
)
try require(
    localization.contains("\"Task started over an hour ago and result is no longer recoverable. Please re-send.\" : {") &&
        localization.components(separatedBy: "Task started over an hour ago and result is no longer recoverable. Please re-send.").count == 2,
    "The stale crash-recovery terminal message must be owned by the string catalog."
)

print("PASS: chat run recovery architecture verified")
