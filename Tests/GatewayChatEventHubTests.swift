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

        print("PASS: gateway chat event hub")
    }
}
