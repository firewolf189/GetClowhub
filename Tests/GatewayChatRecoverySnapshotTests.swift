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

private func runStatus(
    runId: String,
    state: GatewayChatRunState,
    startedAt: TimeInterval? = nil,
    endedAt: TimeInterval? = nil,
    errorMessage: String? = nil,
    stopReason: String? = nil
) -> GatewayChatRunStatusSnapshot {
    GatewayChatRunStatusSnapshot(
        runId: runId,
        state: state,
        startedAt: startedAt.map(Date.init(timeIntervalSince1970:)),
        endedAt: endedAt.map(Date.init(timeIntervalSince1970:)),
        errorMessage: errorMessage,
        stopReason: stopReason
    )
}

@main
private enum GatewayChatRecoverySnapshotTests {
    static func main() throws {
        let matchingActive = GatewayChatRecoverySnapshot(
            assistantMessages: [],
            inFlightRun: GatewayInFlightRunSnapshot(runId: "run-1", text: "partial answer"),
            hasActiveRun: true
        )
        try expect(
            matchingActive.decision(
                expectedRunId: "run-1",
                expectedRunStatus: runStatus(runId: "run-1", state: .running)
            ) == .resume(bufferedText: "partial answer"),
            "a matching in-flight run must resume its gateway-buffered draft"
        )

        let twoRunHistory = GatewayChatRecoverySnapshot(
            assistantMessages: [
                GatewayAssistantMessageSnapshot(
                    text: "second run reply",
                    timestamp: Date(timeIntervalSince1970: 125)
                )
            ],
            inFlightRun: nil,
            hasActiveRun: false
        )
        try expect(
            twoRunHistory.decision(
                expectedRunId: "run-1",
                expectedRunStatus: runStatus(
                    runId: "run-1",
                    state: .completed,
                    startedAt: 100,
                    endedAt: 110
                )
            ) == .awaitingAuthoritativeState,
            "a completed run must not reuse a later run's latest assistant reply"
        )
        try expect(
            twoRunHistory.decision(
                expectedRunId: "run-2",
                expectedRunStatus: runStatus(
                    runId: "run-2",
                    state: .completed,
                    startedAt: 120,
                    endedAt: 130
                )
            ) == .complete(text: "second run reply"),
            "a completed run may claim an assistant reply inside its own time window"
        )

        let completedHistory = GatewayChatRecoverySnapshot(
            assistantMessages: [
                GatewayAssistantMessageSnapshot(
                    text: "old reply",
                    timestamp: Date(timeIntervalSince1970: 90)
                ),
                GatewayAssistantMessageSnapshot(
                    text: "final answer",
                    timestamp: Date(timeIntervalSince1970: 105)
                )
            ],
            inFlightRun: nil,
            hasActiveRun: false
        )
        try expect(
            completedHistory.decision(
                expectedRunId: "run-1",
                expectedRunStatus: runStatus(
                    runId: "run-1",
                    state: .completed,
                    startedAt: 100,
                    endedAt: 110
                )
            ) == .complete(text: "final answer"),
            "completed recovery must select an assistant reply inside startedAt/endedAt"
        )

        try expect(
            completedHistory.decision(
                expectedRunId: "run-1",
                expectedRunStatus: runStatus(
                    runId: "run-1",
                    state: .completed,
                    endedAt: 110
                ),
                fallbackStartedAt: Date(timeIntervalSince1970: 100)
            ) == .complete(text: "final answer"),
            "client-owned run start time must recover chat completions whose gateway status omits startedAt"
        )

        let unrelatedHistory = GatewayChatRecoverySnapshot(
            assistantMessages: [
                GatewayAssistantMessageSnapshot(
                    text: "unrelated latest reply",
                    timestamp: Date(timeIntervalSince1970: 105)
                )
            ],
            inFlightRun: nil,
            hasActiveRun: false
        )
        for state in [GatewayChatRunState.running, .unknown] {
            try expect(
                unrelatedHistory.decision(
                    expectedRunId: "run-1",
                    expectedRunStatus: runStatus(
                        runId: "run-1",
                        state: state,
                        startedAt: 100,
                        endedAt: 110
                    )
                ) == .awaitingAuthoritativeState,
                "running and unknown run states must never complete from history text"
            )
        }

        try expect(
            GatewayChatRecoverySnapshot(
                assistantMessages: [],
                inFlightRun: nil,
                hasActiveRun: false
            ).decision(
                expectedRunId: "run-1",
                expectedRunStatus: runStatus(
                    runId: "run-1",
                    state: .completed,
                    startedAt: 100,
                    endedAt: 110
                )
            ) == .awaitingAuthoritativeState,
            "a completed run whose reply is not persisted yet must remain awaiting"
        )

        try expect(
            unrelatedHistory.decision(
                expectedRunId: "run-1",
                expectedRunStatus: runStatus(
                    runId: "run-1",
                    state: .failed,
                    errorMessage: "provider failed"
                )
            ) == .failed(message: "provider failed"),
            "an authoritative run error must fail recovery"
        )
        try expect(
            unrelatedHistory.decision(
                expectedRunId: "run-1",
                expectedRunStatus: runStatus(runId: "run-1", state: .cancelled)
            ) == .cancelled,
            "an authoritative cancellation must cancel recovery"
        )
        try expect(
            unrelatedHistory.decision(
                expectedRunId: "run-1",
                expectedRunStatus: runStatus(
                    runId: "another-run",
                    state: .completed,
                    startedAt: 100,
                    endedAt: 110
                )
            ) == .awaitingAuthoritativeState,
            "a status snapshot for another run id must never terminalize this run"
        )

        try expect(
            GatewayChatSendResult.acknowledged(runId: "run-1").expectedRunId == "run-1",
            "an acknowledged send exposes its authoritative run id"
        )
        try expect(
            GatewayChatSendResult.deliveryUnconfirmed(expectedRunId: "stable-key").expectedRunId == "stable-key",
            "an acknowledgement timeout must retain the stable idempotency identity"
        )
        try expect(
            GatewayChatSendResult.rejected(message: "invalid").expectedRunId == nil,
            "an authoritative rejection must not pretend a run exists"
        )

        try testConservativeHistoryDoesNotStealAnotherTurn()
        try testUnknownProcessResumesNeitherInFlightNorLatestHistory()

        print("PASS: gateway chat recovery snapshot")
    }

    private static func unregisteredStatus(runId: String) -> GatewayChatRunStatusSnapshot {
        GatewayChatRunStatusSnapshot(
            runId: runId,
            state: .running,
            startedAt: nil,
            endedAt: nil,
            errorMessage: nil,
            stopReason: nil,
            timeoutPhase: "queue",
            providerStarted: false
        )
    }

    private static func testConservativeHistoryDoesNotStealAnotherTurn() throws {
        let mixedHistory = GatewayChatRecoverySnapshot(
            assistantMessages: [
                GatewayAssistantMessageSnapshot(
                    text: "older turn",
                    timestamp: Date(timeIntervalSince1970: 90)
                ),
                GatewayAssistantMessageSnapshot(
                    text: "this run",
                    timestamp: Date(timeIntervalSince1970: 105)
                ),
                GatewayAssistantMessageSnapshot(
                    text: "later turn",
                    timestamp: Date(timeIntervalSince1970: 140)
                )
            ],
            inFlightRun: nil,
            hasActiveRun: false
        )
        try expect(
            mixedHistory.decision(
                expectedRunId: "run-1",
                expectedRunStatus: unregisteredStatus(runId: "run-1"),
                fallbackStartedAt: Date(timeIntervalSince1970: 100),
                processTrust: .unknownOrRestarted
            ) == .unrecoverable,
            "without an authoritative endedAt window, later-turn history must not complete this run"
        )

        let uniqueHistory = GatewayChatRecoverySnapshot(
            assistantMessages: [
                GatewayAssistantMessageSnapshot(
                    text: "this run",
                    timestamp: Date(timeIntervalSince1970: 105)
                )
            ],
            inFlightRun: nil,
            hasActiveRun: false
        )
        try expect(
            uniqueHistory.decision(
                expectedRunId: "run-1",
                expectedRunStatus: unregisteredStatus(runId: "run-1"),
                fallbackStartedAt: Date(timeIntervalSince1970: 100),
                processTrust: .unknownOrRestarted
            ) == .unrecoverable,
            "a single post-start reply is still not proof after a process restart"
        )
        try expect(
            uniqueHistory.decision(
                expectedRunId: "run-1",
                expectedRunStatus: unregisteredStatus(runId: "run-1"),
                fallbackStartedAt: Date(timeIntervalSince1970: 100),
                processTrust: .sameProcess,
                deliveryAcknowledged: true
            ) == .unrecoverable,
            "an acknowledged run that vanished from wait must interrupt rather than poll as running"
        )
        try expect(
            uniqueHistory.decision(
                expectedRunId: "run-1",
                expectedRunStatus: unregisteredStatus(runId: "run-1"),
                fallbackStartedAt: Date(timeIntervalSince1970: 100),
                processTrust: .sameProcess,
                deliveryAcknowledged: false
            ) == .awaitingAuthoritativeState,
            "an unacknowledged missing run must keep the registration grace path"
        )
        try expect(
            uniqueHistory.decision(
                expectedRunId: "run-1",
                expectedRunStatus: runStatus(
                    runId: "run-1",
                    state: .completed,
                    startedAt: 100,
                    endedAt: 110
                ),
                processTrust: .unknownOrRestarted
            ) == .complete(text: "this run"),
            "an authoritative completed window may still recover after a process restart"
        )
    }

    private static func testUnknownProcessResumesNeitherInFlightNorLatestHistory() throws {
        let snapshot = GatewayChatRecoverySnapshot(
            assistantMessages: [
                GatewayAssistantMessageSnapshot(
                    text: "later turn",
                    timestamp: Date(timeIntervalSince1970: 140)
                )
            ],
            inFlightRun: GatewayInFlightRunSnapshot(runId: "run-1", text: "new process draft"),
            hasActiveRun: true
        )
        try expect(
            snapshot.decision(
                expectedRunId: "run-1",
                expectedRunStatus: runStatus(runId: "run-1", state: .running, startedAt: 100),
                fallbackStartedAt: Date(timeIntervalSince1970: 100),
                processTrust: .unknownOrRestarted
            ) == .unrecoverable,
            "a restarted process must not resume in-flight text or steal a later turn"
        )
        try expect(
            snapshot.decision(
                expectedRunId: "run-1",
                expectedRunStatus: runStatus(runId: "run-1", state: .running, startedAt: 100),
                fallbackStartedAt: Date(timeIntervalSince1970: 100),
                processTrust: .sameProcess
            ) == .resume(bufferedText: "new process draft"),
            "the same process may still resume a matching in-flight draft"
        )
        try expect(
            snapshot.decision(
                expectedRunId: "run-1",
                expectedRunStatus: runStatus(
                    runId: "another-run",
                    state: .completed,
                    startedAt: 100,
                    endedAt: 110
                ),
                processTrust: .unknownOrRestarted
            ) == .unrecoverable,
            "a status snapshot for another run must not complete after a process restart"
        )
    }
}
