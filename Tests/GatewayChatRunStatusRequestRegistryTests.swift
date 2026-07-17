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
private enum GatewayChatRunStatusRequestRegistryTests {
    static func main() async throws {
        let registry = GatewayChatRunStatusRequestRegistry()

        async let first: GatewayChatRunStatusSnapshot? = withCheckedContinuation { continuation in
            registry.register(requestId: "request-1", expectedRunId: "run-1", continuation: continuation)
        }
        async let second: GatewayChatRunStatusSnapshot? = withCheckedContinuation { continuation in
            registry.register(requestId: "request-2", expectedRunId: "run-2", continuation: continuation)
        }

        while registry.count != 2 { await Task.yield() }
        let secondSnapshot = GatewayChatRunStatusSnapshot(
            runId: "run-2",
            state: .running,
            startedAt: nil,
            endedAt: nil,
            errorMessage: nil,
            stopReason: nil
        )
        let firstSnapshot = GatewayChatRunStatusSnapshot(
            runId: "run-1",
            state: .completed,
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            errorMessage: nil,
            stopReason: nil
        )

        try expect(
            registry.resolve(requestId: "request-2", responseRunId: "run-2", snapshot: secondSnapshot),
            "the second request must be independently routable first"
        )
        try expect(
            registry.resolve(requestId: "request-1", responseRunId: "run-1", snapshot: firstSnapshot),
            "the first request must remain routable after reverse-order completion"
        )
        let firstResult = await first
        let secondResult = await second
        try expect(firstResult == firstSnapshot, "request-1 must receive only run-1")
        try expect(secondResult == secondSnapshot, "request-2 must receive only run-2")
        try expect(registry.count == 0, "completed requests must leave no registry entries")

        async let mismatch: GatewayChatRunStatusSnapshot? = withCheckedContinuation { continuation in
            registry.register(requestId: "request-3", expectedRunId: "run-3", continuation: continuation)
        }
        while registry.count != 1 { await Task.yield() }
        try expect(
            registry.resolve(requestId: "request-3", responseRunId: "another-run", snapshot: firstSnapshot),
            "a mismatched response still consumes its exact request"
        )
        let mismatchResult = await mismatch
        try expect(mismatchResult == nil, "a mismatched run id must fail closed")
        try expect(registry.count == 0, "mismatched responses must not leak continuations")

        async let cancelled: GatewayChatRunStatusSnapshot? = withCheckedContinuation { continuation in
            registry.register(requestId: "request-4", expectedRunId: "run-4", continuation: continuation)
        }
        while registry.count != 1 { await Task.yield() }
        try expect(registry.cancel(requestId: "request-4"), "timeout/send failure must cancel an existing request")
        let cancelledResult = await cancelled
        try expect(cancelledResult == nil, "cancelled requests must resolve nil exactly once")
        try expect(!registry.cancel(requestId: "request-4"), "a late timeout must not resume twice")
        try expect(
            !registry.resolve(requestId: "request-4", responseRunId: "run-4", snapshot: firstSnapshot),
            "a late response must not revive a removed request"
        )
        try expect(registry.count == 0, "late callbacks must leave the registry empty")

        print("PASS: gateway chat run status request registry")
    }
}
