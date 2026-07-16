import Foundation

struct GatewayReconnectPolicy: Equatable, Sendable {
    let maximumAttempts: Int
    let maximumDelay: TimeInterval
    let handshakeTimeout: TimeInterval

    init(
        maximumAttempts: Int = 5,
        maximumDelay: TimeInterval = 16,
        handshakeTimeout: TimeInterval = 30
    ) {
        precondition(maximumAttempts > 0)
        precondition(maximumDelay > 0)
        precondition(handshakeTimeout > 0)
        self.maximumAttempts = maximumAttempts
        self.maximumDelay = maximumDelay
        self.handshakeTimeout = handshakeTimeout
    }

    func delayBeforeAttempt(_ attempt: Int) -> TimeInterval? {
        guard (1...maximumAttempts).contains(attempt) else { return nil }
        return min(pow(2, Double(attempt - 1)), maximumDelay)
    }

    func canScheduleAttempt(afterCompletedAttempts completedAttempts: Int) -> Bool {
        completedAttempts < maximumAttempts
    }
}

enum GatewayConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int, maxAttempts: Int)
    case recoveryExhausted(attempts: Int)

    var isConnected: Bool {
        self == .connected
    }
}
