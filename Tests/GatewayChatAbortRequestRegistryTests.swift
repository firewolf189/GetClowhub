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
private enum GatewayChatAbortRequestRegistryTests {
    static func main() async throws {
        let registry = GatewayChatAbortRequestRegistry()

        async let confirmed: GatewayChatAbortResult = withCheckedContinuation { continuation in
            registry.register(
                requestId: "request-confirmed",
                expectedRunId: "run-1",
                continuation: continuation
            )
        }
        while registry.count != 1 { await Task.yield() }
        try expect(
            registry.resolve(
                requestId: "request-confirmed",
                response: GatewayChatAbortResponse(aborted: true, runIds: ["run-1"]),
                rejectionMessage: nil
            ),
            "an exact chat.abort response must resolve its request"
        )
        let confirmedResult = await confirmed
        try expect(
            confirmedResult == .confirmed(runIds: ["run-1"]),
            "aborted=true must confirm only the requested run id"
        )

        async let notRunning: GatewayChatAbortResult = withCheckedContinuation { continuation in
            registry.register(
                requestId: "request-not-running",
                expectedRunId: "run-2",
                continuation: continuation
            )
        }
        while registry.count != 1 { await Task.yield() }
        _ = registry.resolve(
            requestId: "request-not-running",
            response: GatewayChatAbortResponse(aborted: false, runIds: []),
            rejectionMessage: nil
        )
        let notRunningResult = await notRunning
        try expect(
            notRunningResult == .notRunning,
            "a successful RPC with aborted=false must not be treated as confirmed cancellation"
        )

        async let mismatched: GatewayChatAbortResult = withCheckedContinuation { continuation in
            registry.register(
                requestId: "request-mismatched",
                expectedRunId: "run-3",
                continuation: continuation
            )
        }
        while registry.count != 1 { await Task.yield() }
        _ = registry.resolve(
            requestId: "request-mismatched",
            response: GatewayChatAbortResponse(aborted: true, runIds: ["another-run"]),
            rejectionMessage: nil
        )
        let mismatchedResult = await mismatched
        try expect(
            mismatchedResult == .notRunning,
            "an abort response for another run must fail closed"
        )

        async let rejected: GatewayChatAbortResult = withCheckedContinuation { continuation in
            registry.register(
                requestId: "request-rejected",
                expectedRunId: "run-4",
                continuation: continuation
            )
        }
        while registry.count != 1 { await Task.yield() }
        _ = registry.resolve(
            requestId: "request-rejected",
            response: nil,
            rejectionMessage: "unauthorized"
        )
        let rejectedResult = await rejected
        try expect(
            rejectedResult == .rejected(message: "unauthorized"),
            "gateway rejection details must remain distinguishable from an inactive run"
        )

        async let unavailable: GatewayChatAbortResult = withCheckedContinuation { continuation in
            registry.register(
                requestId: "request-unavailable",
                expectedRunId: "run-5",
                continuation: continuation
            )
        }
        while registry.count != 1 { await Task.yield() }
        try expect(
            registry.cancel(requestId: "request-unavailable"),
            "transport failure must consume the pending request"
        )
        let unavailableResult = await unavailable
        try expect(
            unavailableResult == .transportUnavailable,
            "transport failure must not masquerade as a gateway cancellation result"
        )
        try expect(
            !registry.cancel(requestId: "request-unavailable"),
            "late timeout callbacks must not resume a continuation twice"
        )
        try expect(registry.count == 0, "all abort continuations must be released")

        try await testAbortWithoutExpectedRunId()
        try testAbortResponseParser()

        print("PASS: gateway chat abort request registry")
    }

    /// Rewind / session-level abort omits `runId`. The gateway saying
    /// `aborted=true` is confirmation even when `runIds` is empty or unexpected.
    private static func testAbortWithoutExpectedRunId() async throws {
        try expect(
            GatewayChatAbortResponse(aborted: true, runIds: ["run-live"]).result(expectedRunId: nil)
                == .confirmed(runIds: ["run-live"]),
            "nil expectedRunId + aborted=true confirms the reported run ids"
        )
        try expect(
            GatewayChatAbortResponse(aborted: true, runIds: []).result(expectedRunId: nil)
                == .confirmed(runIds: []),
            "nil expectedRunId + aborted=true confirms even when runIds is empty"
        )
        try expect(
            GatewayChatAbortResponse(aborted: false, runIds: ["run-live"]).result(expectedRunId: nil)
                == .notRunning,
            "nil expectedRunId + aborted=false is still notRunning"
        )

        let registry = GatewayChatAbortRequestRegistry()
        async let sessionAbort: GatewayChatAbortResult = withCheckedContinuation { continuation in
            registry.register(
                requestId: "request-no-run-id",
                expectedRunId: nil,
                continuation: continuation
            )
        }
        while registry.count != 1 { await Task.yield() }
        try expect(
            registry.resolve(
                requestId: "request-no-run-id",
                response: GatewayChatAbortResponse(aborted: true, runIds: ["run-a", "run-b"]),
                rejectionMessage: nil
            ),
            "session-level abort must resolve its request"
        )
        let sessionResult = await sessionAbort
        try expect(
            sessionResult == .confirmed(runIds: ["run-a", "run-b"]),
            "abort without expectedRunId must confirm whatever runIds the gateway reports"
        )
        try expect(registry.count == 0, "session-level abort continuation must be released")
    }

    private static func testAbortResponseParser() throws {
        let parsed = GatewayChatAbortResponse.parse(fromRPC: [
            "type": "res",
            "id": "abort-1",
            "payload": ["aborted": true, "runIds": ["run-1"]],
        ])
        try expect(parsed == GatewayChatAbortResponse(aborted: true, runIds: ["run-1"]), "RPC payload must decode aborted + runIds")
        try expect(
            GatewayChatAbortResponse.parse(fromRPC: ["payload": ["runIds": ["run-1"]]]) == nil,
            "a payload missing aborted is malformed"
        )
        try expect(
            GatewayChatAbortResponse.parse(fromRPC: ["ok": true]) == nil,
            "a response without a payload is malformed"
        )
    }
}
