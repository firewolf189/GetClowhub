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
private enum GatewayChatRunStatusTests {
    static func main() throws {
        let startedAt = Date(timeIntervalSince1970: 100)
        let endedAt = Date(timeIntervalSince1970: 110)

        let completed = GatewayChatRunStatusSnapshot(
            runId: "run-ok",
            gatewayStatus: "ok",
            startedAt: startedAt,
            endedAt: endedAt,
            errorMessage: nil,
            stopReason: "end_turn"
        )
        try expect(completed.state == .completed, "agent.wait status=ok must be completed")
        try expect(completed.startedAt == startedAt, "completed status must preserve startedAt")
        try expect(completed.endedAt == endedAt, "completed status must preserve endedAt")

        let failed = GatewayChatRunStatusSnapshot(
            runId: "run-error",
            gatewayStatus: "error",
            startedAt: startedAt,
            endedAt: endedAt,
            errorMessage: "provider failed",
            stopReason: "error"
        )
        try expect(failed.state == .failed, "agent.wait status=error must be failed")
        try expect(failed.errorMessage == "provider failed", "failed status must preserve its error")

        for (gatewayStatus, stopReason) in [
            ("timeout", "aborted"),
            ("error", "user CANCEL request"),
            ("ok", "killed_by_operator")
        ] {
            let cancelled = GatewayChatRunStatusSnapshot(
                runId: "run-cancelled",
                gatewayStatus: gatewayStatus,
                startedAt: startedAt,
                endedAt: endedAt,
                errorMessage: nil,
                stopReason: stopReason
            )
            try expect(
                cancelled.state == .cancelled,
                "abort/cancel/kill stop reasons must override error as cancelled"
            )
        }

        let rpcCancellation = GatewayChatRunStatusSnapshot(
            runId: "run-rpc-cancelled",
            gatewayStatus: "timeout",
            startedAt: startedAt,
            endedAt: endedAt,
            errorMessage: nil,
            stopReason: "rpc",
            aborted: false
        )
        try expect(
            rpcCancellation.state == .cancelled,
            "agent.wait must classify its timeout + stopReason=rpc abort shape as cancelled"
        )

        let rpcErrorWithoutAbort = GatewayChatRunStatusSnapshot(
            runId: "run-rpc-error",
            gatewayStatus: "error",
            startedAt: startedAt,
            endedAt: endedAt,
            errorMessage: "RPC execution failed",
            stopReason: "rpc",
            aborted: false
        )
        try expect(
            rpcErrorWithoutAbort.state == .failed,
            "stopReason=rpc outside the gateway abort timeout shape must not hide a real failure"
        )

        let stopCommandCancellation = GatewayChatRunStatusSnapshot(
            runId: "run-stop-command",
            gatewayStatus: "timeout",
            startedAt: startedAt,
            endedAt: endedAt,
            errorMessage: nil,
            stopReason: "stop"
        )
        try expect(
            stopCommandCancellation.state == .cancelled,
            "the chat stop command must reconcile as cancellation"
        )

        let successfulProviderStop = GatewayChatRunStatusSnapshot(
            runId: "run-provider-stop",
            gatewayStatus: "ok",
            startedAt: startedAt,
            endedAt: endedAt,
            errorMessage: nil,
            stopReason: "stop"
        )
        try expect(
            successfulProviderStop.state == .completed,
            "a successful provider stop reason must remain completed"
        )

        let running = GatewayChatRunStatusSnapshot(
            runId: "run-timeout",
            gatewayStatus: "timeout",
            startedAt: startedAt,
            endedAt: nil,
            errorMessage: nil,
            stopReason: nil
        )
        try expect(running.state == .running, "agent.wait timeout is non-terminal, not failed")

        let unregistered = GatewayChatRunStatusSnapshot(
            runId: "run-not-registered",
            gatewayStatus: "timeout",
            startedAt: nil,
            endedAt: nil,
            errorMessage: nil,
            stopReason: nil,
            timeoutPhase: "queue",
            providerStarted: false
        )
        try expect(
            unregistered.indicatesNoRegisteredRun,
            "queue timeout with providerStarted=false is evidence that an unacknowledged send has not registered"
        )

        let gatewayDraining = GatewayChatRunStatusSnapshot(
            runId: "run-draining",
            gatewayStatus: "timeout",
            startedAt: nil,
            endedAt: nil,
            errorMessage: nil,
            stopReason: nil,
            timeoutPhase: "gateway_draining"
        )
        try expect(
            !gatewayDraining.indicatesNoRegisteredRun,
            "an active gateway-draining run must never be mistaken for an undelivered request"
        )

        let providerTimeout = GatewayChatRunStatusSnapshot(
            runId: "run-provider-timeout",
            gatewayStatus: "timeout",
            startedAt: startedAt,
            endedAt: endedAt,
            errorMessage: "LLM request timed out.",
            stopReason: nil,
            timeoutPhase: "provider",
            providerStarted: true
        )
        try expect(
            providerTimeout.state == .failed,
            "a terminal provider timeout must not be polled as a running agent.wait timeout"
        )
        try expect(
            providerTimeout.errorMessage == "LLM request timed out.",
            "terminal timeout recovery must preserve the provider error"
        )
        let providerTimeoutDecision = GatewayChatRecoverySnapshot(
            assistantMessages: [],
            inFlightRun: nil,
            hasActiveRun: false
        ).decision(
            expectedRunId: providerTimeout.runId,
            expectedRunStatus: providerTimeout
        )
        try expect(
            providerTimeoutDecision == .failed(message: "LLM request timed out."),
            "reconciliation must surface a provider timeout as a terminal error"
        )

        let providerTimeoutWithoutEndedAt = GatewayChatRunStatusSnapshot(
            runId: "run-provider-timeout-no-end",
            gatewayStatus: "timeout",
            startedAt: startedAt,
            endedAt: nil,
            errorMessage: nil,
            stopReason: nil,
            timeoutPhase: "provider",
            providerStarted: true
        )
        try expect(
            providerTimeoutWithoutEndedAt.state == .failed,
            "authoritative timeout metadata must be terminal even when endedAt is absent"
        )

        let pendingTimeoutError = GatewayChatRunStatusSnapshot(
            runId: "run-pending-timeout",
            gatewayStatus: "timeout",
            startedAt: startedAt,
            endedAt: nil,
            errorMessage: "temporary lifecycle error",
            stopReason: nil,
            timeoutPhase: "provider",
            providerStarted: true,
            pendingError: true
        )
        try expect(
            pendingTimeoutError.state == .running,
            "pendingError marks the gateway retry grace and must remain nonterminal"
        )

        let unknown = GatewayChatRunStatusSnapshot(
            runId: "run-unknown",
            gatewayStatus: "future-status",
            startedAt: nil,
            endedAt: nil,
            errorMessage: nil,
            stopReason: nil
        )
        try expect(unknown.state == .unknown, "unrecognized statuses must fail closed as unknown")

        let skillFailure = GatewayChatRunStatusSnapshot(
            runId: "run-skill-failure",
            gatewayStatus: "error",
            startedAt: startedAt,
            endedAt: endedAt,
            errorMessage: "skill failed",
            stopReason: "skill_error"
        )
        try expect(
            skillFailure.state == .failed,
            "words that merely contain 'kill' must not be misclassified as cancellation"
        )

        let milliseconds = GatewayProtocolTimestamp.date(from: 1_700_000_000_250.0)
        try expect(
            abs((milliseconds?.timeIntervalSince1970 ?? 0) - 1_700_000_000.25) < 0.000_1,
            "numeric millisecond timestamps must be normalized to seconds"
        )

        let seconds = GatewayProtocolTimestamp.date(from: 1_700_000_000.25)
        try expect(
            abs((seconds?.timeIntervalSince1970 ?? 0) - 1_700_000_000.25) < 0.000_1,
            "numeric second timestamps must retain subsecond precision"
        )

        let iso8601 = GatewayProtocolTimestamp.date(from: "2026-06-10T12:34:56.789Z")
        try expect(
            abs((iso8601?.timeIntervalSince1970 ?? 0) - 1_781_094_896.789) < 0.001,
            "ISO8601 timestamps with fractional seconds must parse"
        )

        print("PASS: gateway chat run status")
    }
}
