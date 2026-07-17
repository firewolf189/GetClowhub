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
private enum ChatRunStateTests {
    static func main() throws {
        let messageId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let sessionId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let identity = ChatRunIdentity(
            messageId: messageId,
            agentId: "main",
            sessionId: sessionId
        )
        let gatewayBinding = ChatGatewayRunBinding(
            sessionKey: "agent:main:\(sessionId.uuidString)",
            startedAt: Date(timeIntervalSince1970: 999)
        )
        let idempotencyKey = gatewayBinding.idempotencyKey
        var run = ChatRunState(
            identity: identity,
            gatewayBinding: gatewayBinding,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )

        try expect(run.phase == .preparing, "a new run starts in the preparing phase")
        try expect(run.executionKind == .conversation, "ordinary chat owns visible-message terminalization")
        try expect(run.placement == .foreground, "a new interactive run starts in the foreground")
        try expect(run.runId == nil, "runId is attached only after chat.send is acknowledged")
        try expect(!run.gatewayBinding.idempotencyKey.isEmpty, "a stable idempotency key must exist before chat.send")
        try expect(UUID(uuidString: idempotencyKey) != nil, "a run identity must create a valid default idempotency key")
        try expect(!run.cancellationRequested, "a new run must not inherit cancellation intent")

        let imageReviewRun = ChatRunState(
            identity: identity,
            gatewayBinding: gatewayBinding,
            startedAt: Date(timeIntervalSince1970: 1_000),
            executionKind: .localImageReviewBatch
        )
        try expect(
            imageReviewRun.executionKind == .localImageReviewBatch,
            "an orchestrated image batch must retain child-run terminal ownership"
        )

        run = run.applying(.sendStarted)
        try expect(run.phase == .sending, "the state machine must distinguish an in-flight send from local preparation")

        let deliveryUnconfirmed = run.applying(.sendDeliveryUnconfirmed)
        try expect(deliveryUnconfirmed.phase == .waitingForResponse, "an acknowledgement timeout must keep waiting for the possibly accepted run")
        try expect(deliveryUnconfirmed.runId == nil, "an unconfirmed delivery must not be mislabeled as acknowledged")
        try expect(deliveryUnconfirmed.expectedRunId == idempotencyKey, "an unconfirmed delivery must keep filtering by the stable idempotency key")

        run = run.applying(.sendAcknowledged(runId: "run-1"))
        try expect(run.runId == "run-1", "the acknowledged gateway runId must stay bound to the run")
        try expect(run.phase == .waitingForResponse, "an acknowledged send waits for gateway events")

        run = run.applying(.receivedDelta)
        try expect(run.phase == .streaming, "the first delta moves only the active run into streaming")

        run = run.applying(.transportReconnecting(attempt: 3, maxAttempts: 5))
        try expect(run.phase == .reconnecting(attempt: 3, maxAttempts: 5), "transport loss must not become a terminal model failure")
        try expect(run.runId == "run-1", "reconnecting must preserve the original runId")
        try expect(run.identity == identity, "reconnecting must preserve the complete original run identity")
        try expect(run.gatewayBinding == gatewayBinding.acknowledging(runId: "run-1"), "reconnecting must preserve the complete gateway binding")
        try expect(run.gatewayBinding.startedAt == gatewayBinding.startedAt, "acknowledgement must preserve the gateway child start time")
        try expect(run.gatewayBinding.idempotencyKey == idempotencyKey, "reconnecting must preserve the original idempotency key")

        run = run.applying(.transportReconnected)
        try expect(run.phase == .reconciling, "a restored transport must reconcile authoritative run state before resuming")

        run = run.applying(.recoveryResumed(hasBufferedText: true))
        try expect(run.phase == .streaming, "a matching in-flight run with buffered text resumes streaming")

        run = run.applying(.recoveryExhausted(attempts: 5))
        try expect(run.phase == .connectionLost(attempts: 5), "five failed reconnects stop automation but keep the run recoverable")
        try expect(!run.phase.isTerminal, "connection loss alone must not claim that the model run failed")
        try expect(!run.keepsProcessActive, "exhausted recovery must release App Nap suppression while awaiting user action")

        run = run.applying(.retryRequested)
        try expect(run.phase == .connecting, "manual retry starts a fresh transport recovery cycle")
        try expect(run.keepsProcessActive, "manual retry must restore process activity while transport recovery is running")

        run = run.applying(.reconciliationUnavailable(attempts: 5))
        try expect(run.phase == .recoveryUnavailable(attempts: 5), "run reconciliation exhaustion must remain distinct from transport loss")
        try expect(!run.phase.isTerminal, "an unavailable recovery result must remain manually recoverable")

        run = run.applying(.retryRequested)
        try expect(run.phase == .reconciling, "retrying an available transport must resume run reconciliation without reconnecting the socket")

        run = run.applying(.cancellationRequested)
        try expect(run.cancellationRequested, "cancellation intent must remain attached to the run until the backend confirms a terminal state")
        try expect(!run.phase.isTerminal, "requesting cancellation is not the same as receiving an aborted terminal event")
        try expect(run.presentationState.cancellationRequested, "row presentation must receive cancellation intent without observing the global registry")

        let phaseBeforeBackgrounding = run.phase
        run = run.applying(.movedToBackground)
        try expect(run.placement == .background, "placement changes independently of transport lifecycle")
        try expect(run.phase == phaseBeforeBackgrounding, "moving a run to the background must not alter its lifecycle phase")

        run = run.applying(.completed)
        try expect(run.phase == .completed, "an explicit final outcome is terminal")
        try expect(run.phase.isTerminal, "completed must be terminal")

        var failedRun = ChatRunState(identity: identity, gatewayBinding: gatewayBinding, startedAt: Date())
        failedRun = failedRun.applying(.failed)
        try expect(failedRun.phase == .failed, "an explicit error outcome is terminal")
        try expect(failedRun.phase.isTerminal, "failed must be terminal")

        var cancelledRun = ChatRunState(identity: identity, gatewayBinding: gatewayBinding, startedAt: Date())
        cancelledRun = cancelledRun.applying(.cancelled)
        try expect(cancelledRun.phase == .cancelled, "an explicit aborted outcome is terminal")
        try expect(cancelledRun.phase.isTerminal, "cancelled must be terminal")

        print("PASS: chat run state machine")
    }
}
