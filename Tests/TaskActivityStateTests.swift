import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): message
        }
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure.assertion(message) }
}

@main
private enum TaskActivityStateTests {
    @MainActor
    static func main() throws {
        let messageId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let sessionId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let identity = ChatRunIdentity(
            messageId: messageId,
            agentId: "main",
            sessionId: sessionId
        )
        let run = ChatRunState(
            identity: identity,
            gatewayBinding: ChatGatewayRunBinding(
                sessionKey: "agent:main:\(sessionId.uuidString)",
                idempotencyKey: "run-key"
            ),
            startedAt: Date(timeIntervalSince1970: 1_000)
        )
        let state = TaskActivityState()

        state.registerRun(run)
        try expect(state.run(for: messageId) == run, "registration must preserve the complete run state")
        try expect(state.foregroundTaskIds == [messageId], "a new foreground run must appear in the derived foreground projection")
        try expect(state.backgroundTaskIds.isEmpty, "a new foreground run must not appear in the background projection")
        try expect(state.inflightSessionIds == [sessionId], "session ownership must derive from the run identity")
        try expect(state.hasForegroundTask(inSession: sessionId), "foreground session lookup must derive from the registry")
        try expect(state.hasInflightTask(inSession: sessionId), "in-flight session lookup must derive from the registry")

        state.bindGatewayRun(messageId: messageId, runId: "gateway-run")
        try expect(state.run(for: messageId)?.runId == "gateway-run", "gateway acknowledgement must bind to the existing run")
        try expect(state.run(for: messageId)?.phase == .waitingForResponse, "binding a gateway run must advance its phase")

        let childSessionKey = "agent:main:image-review-child"
        state.prepareGatewayRun(
            messageId: messageId,
            sessionKey: childSessionKey,
            idempotencyKey: "child-key",
            startedAt: Date(timeIntervalSince1970: 1_001)
        )
        state.bindGatewayRun(messageId: messageId, runId: "child-run")
        try expect(state.run(for: messageId)?.gatewayBinding.sessionKey == childSessionKey, "an orchestrated child run must expose its exact gateway session for cancellation")
        try expect(state.run(for: messageId)?.gatewayBinding.idempotencyKey == "child-key", "a child run must retain its own idempotency identity")
        try expect(state.run(for: messageId)?.gatewayBinding.startedAt == Date(timeIntervalSince1970: 1_001), "a child run must own its own recovery window")
        try expect(state.run(for: messageId)?.identity.sessionId == sessionId, "rebinding a gateway child must preserve UI session ownership")
        try expect(state.run(for: messageId)?.runId == "child-run", "rebinding must replace only the active gateway run")

        state.applyRunEvent(messageId: messageId, event: .receivedDelta)
        try expect(state.run(for: messageId)?.phase == .streaming, "a delta must transition only the addressed run")

        state.moveRunToBackground(messageId: messageId)
        try expect(state.foregroundTaskIds.isEmpty, "backgrounding must remove the run from the foreground projection")
        try expect(state.backgroundTaskIds == [messageId], "backgrounding must add the run to the background projection")
        try expect(state.run(for: messageId)?.phase == .streaming, "background placement must not alter the run lifecycle")

        state.applyRunEvent(messageId: messageId, event: .completed)
        try expect(state.foregroundTaskIds.isEmpty && state.backgroundTaskIds.isEmpty, "terminal runs must not remain in active projections")
        try expect(state.run(for: messageId)?.phase == .completed, "the registry must retain terminal state until explicit removal")

        state.removeRun(messageId: messageId)
        try expect(state.run(for: messageId) == nil, "explicit removal must clear the single source of task identity")
        try expect(state.inflightSessionIds.isEmpty, "removal must clear derived session ownership")

        let secondMessageId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let thirdMessageId = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let lostRun = run
            .applying(.recoveryExhausted(attempts: 5))
        let secondLostRun = ChatRunState(
            identity: ChatRunIdentity(messageId: secondMessageId, agentId: "main", sessionId: sessionId),
            gatewayBinding: ChatGatewayRunBinding(sessionKey: "agent:main:second", idempotencyKey: "second"),
            startedAt: Date(timeIntervalSince1970: 1_001),
            phase: .connectionLost(attempts: 5)
        )
        let stillStreamingRun = ChatRunState(
            identity: ChatRunIdentity(messageId: thirdMessageId, agentId: "main", sessionId: sessionId),
            gatewayBinding: ChatGatewayRunBinding(sessionKey: "agent:main:third", idempotencyKey: "third"),
            startedAt: Date(timeIntervalSince1970: 1_002),
            phase: .streaming
        )

        state.registerRun(lostRun)
        state.registerRun(secondLostRun)
        state.registerRun(stillStreamingRun)
        try expect(state.requestTransportRecoveryRetry() == 2, "one transport retry must transition every lost run")
        try expect(state.run(for: messageId)?.phase == .connecting, "the first lost run must re-enter connecting")
        try expect(state.run(for: secondMessageId)?.phase == .connecting, "the second lost run must share the same retry")
        try expect(state.run(for: thirdMessageId)?.phase == .streaming, "retry must not perturb a run that never lost transport")

        state.applyRunEventToActiveRuns(.transportReconnected)
        try expect(state.run(for: messageId)?.phase == .reconciling, "shared transport recovery must wake the first unresolved run")
        try expect(state.run(for: secondMessageId)?.phase == .reconciling, "shared transport recovery must wake every unresolved run")
        try expect(state.run(for: thirdMessageId)?.phase == .reconciling, "a live run must reconcile after socket replacement")

        state.applyRunEvent(messageId: thirdMessageId, event: .reconciliationUnavailable(attempts: 5))
        try expect(
            state.requestRunReconciliationRetry(messageId: thirdMessageId),
            "a run-level retry must be accepted only for unavailable authoritative reconciliation"
        )
        try expect(state.run(for: thirdMessageId)?.phase == .reconciling, "run-level retry must not reconnect the shared transport")

        print("PASS: task activity run registry")
    }
}
