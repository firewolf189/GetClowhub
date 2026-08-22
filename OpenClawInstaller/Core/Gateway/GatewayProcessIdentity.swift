import Foundation

/// Parsed inbound gateway WebSocket text. Isolated so product tests can feed
/// recorded frames without standing up `URLSessionWebSocketTask`.
enum GatewayInboundJSON {
    static func object(from text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}

/// Snapshot of the Gateway process the client last authenticated against.
/// Recovery may repeat `chat.send` with the original idempotency key only when
/// `isKnown` is true and `epoch` still matches the run's originating epoch.
struct GatewayProcessFingerprint: Equatable, Sendable {
    var epoch: UInt64
    var startedAtEstimate: Date?
    var isKnown: Bool

    var allowsIdempotencyProbe: Bool { isKnown }
}

/// Distinguishes reconnecting to the same Gateway process from a process
/// restart. `hello-ok.snapshot.uptimeMs` yields a start-time estimate; a
/// material change (beyond jitter tolerance) or missing/malformed uptime
/// advances `epoch`. Unknown identity forbids the idempotency probe.
struct GatewayProcessIdentity: Equatable, Sendable {
    /// Network and clock jitter absorbed when comparing start estimates.
    static let startEstimateTolerance: TimeInterval = 5

    private(set) var fingerprint = GatewayProcessFingerprint(
        epoch: 0,
        startedAtEstimate: nil,
        isKnown: false
    )

    @discardableResult
    mutating func applyHello(payload: [String: Any]?, now: Date = Date()) -> GatewayProcessFingerprint {
        guard let startedAt = Self.startedAtEstimate(from: payload, now: now) else {
            fingerprint = GatewayProcessFingerprint(
                epoch: fingerprint.epoch &+ 1,
                startedAtEstimate: nil,
                isKnown: false
            )
            return fingerprint
        }

        if fingerprint.isKnown,
           let previous = fingerprint.startedAtEstimate,
           abs(startedAt.timeIntervalSince(previous)) <= Self.startEstimateTolerance {
            return fingerprint
        }

        fingerprint = GatewayProcessFingerprint(
            epoch: fingerprint.epoch &+ 1,
            startedAtEstimate: startedAt,
            isKnown: true
        )
        return fingerprint
    }

    static func startedAtEstimate(from payload: [String: Any]?, now: Date) -> Date? {
        guard let uptimeMs = parseUptimeMs(from: payload) else { return nil }
        return now.addingTimeInterval(-uptimeMs / 1_000)
    }

    static func parseUptimeMs(from payload: [String: Any]?) -> Double? {
        guard let payload else { return nil }
        let snapshot = payload["snapshot"] as? [String: Any]
        let raw = snapshot?["uptimeMs"] ?? payload["uptimeMs"]
        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            let value = number.doubleValue
            guard value.isFinite, value >= 0 else { return nil }
            return value
        }
        if let string = raw as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Double(trimmed), value.isFinite, value >= 0 else { return nil }
            return value
        }
        return nil
    }
}

/// Repeating `chat.send` with the original idempotency key is safe only on the
/// same known Gateway process. A restart drops the in-memory dedupe cache, so
/// a probe would start a duplicate run.
enum GatewayChatSendMode: Equatable, Sendable {
    case initial
    case recoveryProbe(originatingEpoch: UInt64?)
}

enum GatewayChatSendProbePolicy {
    static func allowsProbe(
        originatingEpoch: UInt64?,
        current: GatewayProcessFingerprint
    ) -> Bool {
        guard current.allowsIdempotencyProbe,
              let originatingEpoch,
              originatingEpoch == current.epoch else {
            return false
        }
        return true
    }

    static func allows(_ mode: GatewayChatSendMode, current: GatewayProcessFingerprint) -> Bool {
        switch mode {
        case .initial:
            return true
        case .recoveryProbe(let originatingEpoch):
            return allowsProbe(originatingEpoch: originatingEpoch, current: current)
        }
    }
}
