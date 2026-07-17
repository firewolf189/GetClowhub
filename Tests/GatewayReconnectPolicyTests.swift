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
private enum GatewayReconnectPolicyTests {
    static func main() throws {
        let policy = GatewayReconnectPolicy()

        try expect(policy.maximumAttempts == 5, "automatic recovery must stop after five reconnect attempts")
        try expect(policy.handshakeTimeout == 30, "one WebSocket handshake must be bounded independently")
        try expect(
            (1...5).compactMap(policy.delayBeforeAttempt) == [1, 2, 4, 8, 16],
            "reconnect attempts must use bounded exponential backoff"
        )
        try expect(policy.delayBeforeAttempt(0) == nil, "attempt numbering must be one-based")
        try expect(policy.delayBeforeAttempt(6) == nil, "the policy must not schedule a sixth attempt")
        try expect(policy.canScheduleAttempt(afterCompletedAttempts: 4), "the fifth attempt must still be allowed")
        try expect(!policy.canScheduleAttempt(afterCompletedAttempts: 5), "five failed attempts must exhaust automatic recovery")

        print("PASS: gateway reconnect policy")
    }
}
