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
private enum ChatRunReconciliationPolicyTests {
    static func main() throws {
        var cursor = ChatRunReconciliationCursor()

        for (attempt, expectedDelay) in zip(1...4, [1.0, 2.0, 4.0, 8.0]) {
            try expect(
                cursor.recordUnavailableObservation() == .retry(after: expectedDelay),
                "unavailable observation \(attempt) must use exponential backoff"
            )
        }
        try expect(
            cursor.recordUnavailableObservation() == .suspend(attempts: 5),
            "the fifth unavailable observation must suspend automatic reconciliation"
        )

        cursor.recordAuthoritativeObservation()
        try expect(
            cursor.recordUnavailableObservation() == .retry(after: 1),
            "an authoritative observation must reset transient availability failures"
        )

        for _ in 1...20 {
            cursor.recordAuthoritativeObservation()
            try expect(
                cursor.pollActiveRun() == .poll(after: 15),
                "a confirmed active foreground run must keep polling without a total deadline"
            )
        }

        cursor.recordAuthoritativeObservation()
        for attempt in 1...4 {
            try expect(
                cursor.recordCompletedReplyUnavailable() == .retry(after: Double(1 << (attempt - 1))),
                "completed history observation \(attempt) must retry persistence lag"
            )
        }
        try expect(
            cursor.recordCompletedReplyUnavailable() == .suspend(attempts: 5),
            "completed status without a correlated history message must suspend instead of guessing"
        )

        try expect(
            ChatRunDeliveryPolicy.maximumSubmissionAttempts == 3,
            "an unacknowledged submission needs a bounded idempotent retry budget"
        )
        try expect(
            ChatRunDeliveryPolicy.unregisteredRunGracePeriod == 60,
            "missing-run evidence needs a bounded registration grace period, not an infinite foreground poll"
        )

        print("PASS: chat run reconciliation policy")
    }
}
