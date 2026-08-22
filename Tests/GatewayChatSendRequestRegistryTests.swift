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
private enum GatewayChatSendRequestRegistryTests {
    static func main() async throws {
        try testMatcherExactAndSessionFallback()
        try await testSessionEventMarksUniquePendingSend()
        try await testTwoSendsOnSameSessionDoNotStealDelivery()
        try await testIdempotencyKeyMarksTheMatchingSend()
        print("PASS: gateway chat send request registry")
    }

    private static func testMatcherExactAndSessionFallback() throws {
        let pending = GatewayChatSendPendingIdentity(
            expectedRunId: "idem-1",
            sessionKey: "agent:main:aaaa"
        )
        try expect(
            GatewayChatSendDeliveryMatcher.matchesExact(
                pending: pending,
                eventRunId: "idem-1",
                eventIdempotencyKey: nil
            ),
            "client idempotency key echoed as runId still counts as delivery"
        )
        try expect(
            GatewayChatSendDeliveryMatcher.matchesExact(
                pending: pending,
                eventRunId: "gw-run-9",
                eventIdempotencyKey: "idem-1"
            ),
            "gateway echoing the idempotency key must count as delivery"
        )
        try expect(
            !GatewayChatSendDeliveryMatcher.matchesExact(
                pending: pending,
                eventRunId: "gw-run-9",
                eventIdempotencyKey: nil
            ),
            "a gateway-assigned run id must not match the client idempotency key"
        )
        try expect(
            GatewayChatSendDeliveryMatcher.matchesSessionFallback(
                pending: pending,
                eventSessionKey: "agent:main:aaaa",
                pendingCountForSession: 1
            ),
            "a unique in-flight send on that session may adopt the session's first event"
        )
        try expect(
            !GatewayChatSendDeliveryMatcher.matchesSessionFallback(
                pending: pending,
                eventSessionKey: "agent:main:aaaa",
                pendingCountForSession: 2
            ),
            "two in-flight sends on one session must not share session-only evidence"
        )
        try expect(
            !GatewayChatSendDeliveryMatcher.matchesSessionFallback(
                pending: pending,
                eventSessionKey: "agent:other:bbbb",
                pendingCountForSession: 1
            ),
            "a different session must not prove delivery"
        )
    }

    private static func awaitRegistered(_ registry: GatewayChatSendRequestRegistry) async {
        while registry.count == 0 { await Task.yield() }
    }

    private static func testSessionEventMarksUniquePendingSend() async throws {
        let registry = GatewayChatSendRequestRegistry()
        async let result: GatewayChatSendResult = withCheckedContinuation { continuation in
            registry.register(
                requestId: "req-1",
                identity: GatewayChatSendPendingIdentity(
                    expectedRunId: "idem-1",
                    sessionKey: "agent:main:sess"
                ),
                startedAt: ContinuousClock.now,
                continuation: continuation
            )
        }
        await awaitRegistered(registry)
        registry.recordDelivery(runId: "gw-run-1", sessionKey: "agent:main:sess", idempotencyKey: nil)
        try expect(registry.isObserved(requestId: "req-1"), "unique session event should mark the pending send observed")
        let taken = registry.take(requestId: "req-1")
        try expect(taken?.deliveryObserved == true, "take must report delivery observed")
        try expect(taken?.observedRunId == "gw-run-1", "session fallback must remember the gateway run id")
        taken?.request.continuation.resume(returning: .acknowledged(runId: taken?.observedRunId ?? "idem-1"))
        let resolved = await result
        try expect(resolved == .acknowledged(runId: "gw-run-1"), "observed take should acknowledge the gateway run id")
    }

    private static func testTwoSendsOnSameSessionDoNotStealDelivery() async throws {
        let registry = GatewayChatSendRequestRegistry()
        async let first: GatewayChatSendResult = withCheckedContinuation { continuation in
            registry.register(
                requestId: "req-a",
                identity: GatewayChatSendPendingIdentity(
                    expectedRunId: "idem-a",
                    sessionKey: "agent:main:sess"
                ),
                startedAt: ContinuousClock.now,
                continuation: continuation
            )
        }
        await awaitRegistered(registry)
        async let second: GatewayChatSendResult = withCheckedContinuation { continuation in
            registry.register(
                requestId: "req-b",
                identity: GatewayChatSendPendingIdentity(
                    expectedRunId: "idem-b",
                    sessionKey: "agent:main:sess"
                ),
                startedAt: ContinuousClock.now,
                continuation: continuation
            )
        }
        while registry.count != 2 { await Task.yield() }

        registry.recordDelivery(runId: "gw-run-x", sessionKey: "agent:main:sess", idempotencyKey: nil)
        try expect(!registry.isObserved(requestId: "req-a"), "ambiguous session event must not mark send A")
        try expect(!registry.isObserved(requestId: "req-b"), "ambiguous session event must not mark send B")

        registry.recordDelivery(runId: "gw-run-b", sessionKey: "agent:main:sess", idempotencyKey: "idem-b")
        try expect(registry.isObserved(requestId: "req-b"), "idempotency echo must mark send B")
        try expect(!registry.isObserved(requestId: "req-a"), "send A stays unobserved")

        let takenB = registry.take(requestId: "req-b")
        try expect(takenB?.deliveryObserved == true, "B is observed")
        try expect(takenB?.observedRunId == "gw-run-b", "B remembers the event run id")
        takenB?.request.continuation.resume(returning: .acknowledged(runId: "gw-run-b"))
        let takenA = registry.take(requestId: "req-a")
        try expect(takenA?.deliveryObserved == false, "A is not observed")
        try expect(takenA?.observedRunId == nil, "unobserved send has no gateway run id")
        takenA?.request.continuation.resume(returning: .deliveryUnconfirmed(expectedRunId: "idem-a"))

        let firstResult = await first
        let secondResult = await second
        try expect(firstResult == .deliveryUnconfirmed(expectedRunId: "idem-a"), "A remains unconfirmed")
        try expect(secondResult == .acknowledged(runId: "gw-run-b"), "B is acknowledged")
    }

    private static func testIdempotencyKeyMarksTheMatchingSend() async throws {
        let registry = GatewayChatSendRequestRegistry()
        async let result: GatewayChatSendResult = withCheckedContinuation { continuation in
            registry.register(
                requestId: "req-k",
                identity: GatewayChatSendPendingIdentity(
                    expectedRunId: "idem-k",
                    sessionKey: "agent:main:other"
                ),
                startedAt: ContinuousClock.now,
                continuation: continuation
            )
        }
        await awaitRegistered(registry)
        registry.recordDelivery(
            runId: "totally-different-gateway-id",
            sessionKey: "agent:main:other",
            idempotencyKey: "idem-k"
        )
        let taken = registry.take(requestId: "req-k")
        try expect(taken?.deliveryObserved == true, "idempotency key on the event must prove delivery")
        try expect(
            taken?.observedRunId == "totally-different-gateway-id",
            "exact idempotency match still stores the gateway run id"
        )
        taken?.request.continuation.resume(
            returning: .acknowledged(runId: taken?.observedRunId ?? "idem-k")
        )
        let resolved = await result
        try expect(
            resolved == .acknowledged(runId: "totally-different-gateway-id"),
            "exact idempotency match acknowledges the gateway run id"
        )
    }
}
