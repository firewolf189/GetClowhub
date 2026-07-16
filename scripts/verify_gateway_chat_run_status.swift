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

let gateway = try source("OpenClawInstaller/Core/Gateway/GatewayClient.swift")
let snapshot = try source("OpenClawInstaller/Core/Gateway/GatewayChatRecoverySnapshot.swift")

guard let statusMethodStart = gateway.range(of: "func fetchChatRunStatus(runId: String)"),
      let historyMethodStart = gateway.range(
        of: "func fetchChatRecoverySnapshot(sessionKey: String)",
        range: statusMethodStart.upperBound..<gateway.endIndex
      ) else {
    fputs("FAIL: unable to isolate fetchChatRunStatus implementation\n", stderr)
    exit(1)
}
let statusMethod = gateway[statusMethodStart.lowerBound..<historyMethodStart.lowerBound]

require(
    gateway.contains("chatRunStatusRequestRegistry") &&
        gateway.contains("GatewayChatRunStatusRequestRegistry"),
    "agent.wait must use an independent typed continuation registry"
)
require(
    gateway.contains("func fetchChatRunStatus(runId: String) async -> GatewayChatRunStatusSnapshot?") &&
        gateway.contains("\"method\": \"agent.wait\"") &&
        gateway.contains("\"timeoutMs\": 0"),
    "run status lookup must call agent.wait(runId, timeoutMs: 0)"
)
require(
    !statusMethod.contains("chat.send") && !statusMethod.contains("pendingChatSendResponses"),
    "run status lookup must never send or reuse chat.send"
)
require(
    statusMethod.contains("chatRunStatusRequestRegistry.cancel(requestId: requestId)") &&
        statusMethod.contains("deadline: .now() + 10"),
    "agent.wait send failures and ten-second RPC timeouts must clear their continuation"
)
require(
    gateway.contains("chatRunStatusRequestRegistry.resolve(") &&
        gateway.contains("requestId: id"),
    "agent.wait responses must be routed by their exact request id"
)
require(
    gateway.range(of: "chatRunStatusRequestRegistry.resolve(")!.lowerBound <
        gateway.range(of: "guard id == pendingConnectRequestId")!.lowerBound,
    "agent.wait responses must be consumed before connect-response fallback"
)
require(
    snapshot.contains("let assistantMessages: [GatewayAssistantMessageSnapshot]") &&
        gateway.contains("GatewayProtocolTimestamp.date(from:") &&
        gateway.contains("chatRecoveryHistoryMessageLimit = 200") &&
        gateway.contains("\"limit\": Self.chatRecoveryHistoryMessageLimit"),
    "chat.history must retain every assistant message text and timestamp"
)
require(
    snapshot.contains("private static func isTerminalTimeout(") &&
        snapshot.contains("guard !pendingError else { return false }") &&
        gateway.contains("timeoutPhase: runStatusPayload[\"timeoutPhase\"] as? String") &&
        gateway.contains("providerStarted: runStatusPayload[\"providerStarted\"] as? Bool") &&
        gateway.contains("pendingError: self.boolValue(runStatusPayload[\"pendingError\"])") &&
        gateway.contains("aborted: self.boolValue(runStatusPayload[\"aborted\"])") ,
    "agent.wait polling timeout and terminal provider/runtime timeout must remain distinct"
)
require(
    snapshot.contains("gatewayStatus: normalizedGatewayStatus") &&
        snapshot.contains("guard gatewayStatus == \"timeout\" else { return false }") &&
        snapshot.contains("normalized == \"rpc\" || normalized == \"stop\""),
    "agent.wait timeout + rpc/stop must recover user cancellation without misclassifying successful provider stops"
)
require(
    !snapshot.contains("isNewAssistantText") &&
        !snapshot.contains("latestAssistantText") &&
        !gateway.contains("fetchLastAssistantMessage"),
    "recovery must not expose any latest-text terminalization path"
)

print("PASS: gateway chat run status architecture")
