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
private enum GatewayChatEventHubTests {
    static func main() async throws {
        let hub = GatewayChatEventHub()
        let stream = hub.stream(
            subscriberId: "row-1",
            runId: "run-1",
            sessionKey: "session-1"
        )
        var iterator = stream.makeAsyncIterator()
        let otherStream = hub.stream(
            subscriberId: "row-2",
            runId: "run-2",
            sessionKey: "session-2"
        )
        var otherIterator = otherStream.makeAsyncIterator()

        try expect(hub.count == 2, "subscribing must register exactly one continuation per run")

        hub.broadcast(.delta(runId: "run-2", sessionKey: "session-2", text: "other draft"))
        hub.broadcast(.delta(runId: "run-1", sessionKey: "session-1", text: "draft"))
        hub.broadcast(.final_(runId: "run-1", sessionKey: "session-1", text: "final"))

        guard let first = await iterator.next(),
              case .delta(let firstRunId, _, let draft) = first else {
            throw TestFailure.assertion("the first broadcast event must remain first")
        }
        try expect(firstRunId == "run-1" && draft == "draft", "delta payload must be preserved")

        guard let second = await iterator.next(),
              case .final_(let secondRunId, _, let finalText) = second else {
            throw TestFailure.assertion("the terminal event must follow its preceding delta")
        }
        try expect(secondRunId == "run-1" && finalText == "final", "final payload must be preserved")
        let terminalEnd = await iterator.next()
        try expect(terminalEnd == nil, "a terminal run event must finish its routed stream")

        guard let otherEvent = await otherIterator.next(),
              case .delta(let otherRunId, _, let otherDraft) = otherEvent else {
            throw TestFailure.assertion("each subscriber must receive only its own run events")
        }
        try expect(otherRunId == "run-2" && otherDraft == "other draft", "run routing must preserve the matching payload")

        hub.unsubscribe(subscriberId: "row-1")
        hub.unsubscribe(subscriberId: "row-2")
        try expect(hub.count == 0, "terminal delivery and unsubscribe must remove continuations")

        let originalStream = hub.stream(subscriberId: "same-id", runId: "pending-run", sessionKey: "session")
        var originalIterator = originalStream.makeAsyncIterator()
        let replacementStream = hub.stream(subscriberId: "same-id", runId: "pending-run", sessionKey: "session")
        var replacementIterator = replacementStream.makeAsyncIterator()
        try expect(hub.count == 1, "reusing an id must atomically replace, not leak, the old subscription")
        let replacedEnd = await originalIterator.next()
        try expect(replacedEnd == nil, "replacing a subscription id must finish the old stream")
        hub.broadcast(.transport(.reconnecting(attempt: 1, maxAttempts: 5)))
        guard let replacementEvent = await replacementIterator.next(),
              case .transport(.reconnecting(let attempt, let maximum)) = replacementEvent else {
            throw TestFailure.assertion("replacement stream must remain registered after old-stream termination")
        }
        try expect(attempt == 1 && maximum == 5, "replacement stream must receive subsequent events")
        hub.bindRun(subscriberId: "same-id", runId: "acknowledged-run", sessionKey: "session")
        hub.broadcast(.delta(runId: "acknowledged-run", sessionKey: "session", text: "bound"))
        guard let reboundEvent = await replacementIterator.next(),
              case .delta(let reboundRunId, _, _) = reboundEvent else {
            throw TestFailure.assertion("an acknowledged run id must be routed to the existing stream")
        }
        try expect(reboundRunId == "acknowledged-run", "run binding must not replace the consumer stream")
        hub.unsubscribe(subscriberId: "same-id")

        let boundedStream = hub.stream(subscriberId: "bounded", runId: "run-bounded", sessionKey: "session")
        var boundedIterator = boundedStream.makeAsyncIterator()
        for index in 0..<(GatewayChatEventHub.bufferLimit + 20) {
            hub.broadcast(.delta(runId: "run-bounded", sessionKey: "session", text: "draft-\(index)"))
        }
        hub.broadcast(.final_(runId: "run-bounded", sessionKey: "session", text: "final"))
        var bufferedEventCount = 0
        var sawTerminal = false
        while let event = await boundedIterator.next() {
            bufferedEventCount += 1
            if case .final_ = event { sawTerminal = true }
        }
        try expect(sawTerminal, "bounded buffering must never lose the terminal event")
        try expect(
            bufferedEventCount <= GatewayChatEventHub.bufferLimit,
            "a stalled consumer must not create an unbounded event queue"
        )

        // Regression (v1.1.70 "send but no reply received"): a subscription is
        // created with the client idempotency key before the gateway's own run id
        // is known. Events carry the gateway-assigned run id, which never equals
        // the idempotency key, so the old strict run-id gate dropped every reply.
        // A provisional subscription must be routed by session until its real run
        // id is bound.
        let provisional = hub.stream(
            subscriberId: "provisional",
            runId: "client-idempotency-key",
            sessionKey: "session-P"
        )
        var provisionalIterator = provisional.makeAsyncIterator()
        hub.broadcast(.delta(runId: "gateway-assigned-run", sessionKey: "session-P", text: "reply"))
        // A different session must still be rejected even while provisional.
        hub.broadcast(.delta(runId: "gateway-assigned-run", sessionKey: "other-session", text: "leak"))
        guard let provisionalEvent = await provisionalIterator.next(),
              case .delta(let provisionalRunId, _, let provisionalText) = provisionalEvent else {
            throw TestFailure.assertion("a provisional subscription must receive gateway-run-id events by session")
        }
        try expect(
            provisionalRunId == "gateway-assigned-run" && provisionalText == "reply",
            "provisional routing must deliver the gateway-assigned run id without requiring the idempotency key"
        )

        // After binding the real run id, matching becomes strict again: a foreign
        // run in the same session must be dropped, the bound run's final delivered.
        hub.bindRun(subscriberId: "provisional", runId: "gateway-assigned-run", sessionKey: "session-P")
        hub.broadcast(.delta(runId: "foreign-run", sessionKey: "session-P", text: "should-not-arrive"))
        hub.broadcast(.final_(runId: "gateway-assigned-run", sessionKey: "session-P", text: "done"))
        guard let boundEvent = await provisionalIterator.next(),
              case .final_(let boundRunId, _, let boundText) = boundEvent else {
            throw TestFailure.assertion("after binding, only the bound run's events may be delivered")
        }
        try expect(
            boundRunId == "gateway-assigned-run" && boundText == "done",
            "post-bind strict matching must drop foreign runs while delivering the bound run"
        )
        let provisionalTail = await provisionalIterator.next()
        try expect(provisionalTail == nil, "the bound run's final must finish the stream")

        // Regression (v1.1.70 production root cause): the gateway canonicalizes
        // session keys to lowercase while the client derives uppercase-UUID keys.
        // A case-sensitive session gate dropped every reply. Session matching
        // must be case-insensitive.
        let caseStream = hub.stream(
            subscriberId: "case-sub",
            runId: "case-run",
            sessionKey: "agent:main:ABCDEF12-3456-7890-ABCD-EF1234567890"
        )
        var caseIterator = caseStream.makeAsyncIterator()
        hub.bindRun(
            subscriberId: "case-sub",
            runId: "case-run",
            sessionKey: "agent:main:ABCDEF12-3456-7890-ABCD-EF1234567890"
        )
        hub.broadcast(.final_(
            runId: "case-run",
            sessionKey: "agent:main:abcdef12-3456-7890-abcd-ef1234567890",
            text: "reply"
        ))
        guard let caseEvent = await caseIterator.next(),
              case .final_(_, _, let caseText) = caseEvent else {
            throw TestFailure.assertion("a lowercase-normalized gateway session key must still match an uppercase subscription")
        }
        try expect(caseText == "reply", "case-insensitive session matching must deliver the reply")

        print("PASS: gateway chat event hub")
    }
}
