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
private enum GatewayProcessIdentityTests {
    static func main() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        var identity = GatewayProcessIdentity()
        try expect(identity.fingerprint.epoch == 0, "a new identity starts at epoch 0")
        try expect(!identity.fingerprint.isKnown, "a new identity is unknown until hello-ok")
        try expect(!identity.fingerprint.allowsIdempotencyProbe, "unknown identity must not probe")

        let first = identity.applyHello(payload: helloPayload(uptimeMs: 60_000), now: t0)
        try expect(first.isKnown, "valid uptimeMs must mark the process known")
        try expect(first.epoch == 1, "the first valid hello must advance the epoch")
        try expect(
            abs((first.startedAtEstimate?.timeIntervalSince1970 ?? 0) - (t0.timeIntervalSince1970 - 60)) < 0.001,
            "startedAt must be wall clock minus uptime"
        )
        try expect(first.allowsIdempotencyProbe, "a known process may probe")

        let sameProcess = identity.applyHello(
            payload: helloPayload(uptimeMs: 65_000),
            now: t0.addingTimeInterval(5)
        )
        try expect(sameProcess.epoch == 1, "jitter within 5s must keep the same process epoch")
        try expect(sameProcess.isKnown, "the same process stays known")
        try expect(
            sameProcess.startedAtEstimate == first.startedAtEstimate,
            "the original start estimate must not drift with reconnect jitter"
        )

        let restarted = identity.applyHello(
            payload: helloPayload(uptimeMs: 100),
            now: t0.addingTimeInterval(10)
        )
        try expect(restarted.epoch == 2, "a material start-time change must bump the process epoch")
        try expect(restarted.isKnown, "a valid new uptime is a known (new) process")

        let unknown = identity.applyHello(payload: ["type": "hello-ok"], now: t0.addingTimeInterval(11))
        try expect(!unknown.isKnown, "missing uptimeMs must produce an unknown process identity")
        try expect(unknown.epoch == 3, "unknown identity must still advance epoch so old probes cannot match")
        try expect(!unknown.allowsIdempotencyProbe, "unknown identity must not probe")
        try expect(unknown.startedAtEstimate == nil, "unknown identity has no start estimate")

        let recovered = identity.applyHello(
            payload: helloPayload(uptimeMs: 1_000),
            now: t0.addingTimeInterval(20)
        )
        try expect(recovered.isKnown && recovered.epoch == 4, "a later valid hello must become known on a new epoch")

        try expect(GatewayProcessIdentity.parseUptimeMs(from: nil) == nil, "nil payload is unknown")
        try expect(GatewayProcessIdentity.parseUptimeMs(from: ["uptimeMs": true]) == nil, "bool must not coerce to uptime")
        try expect(GatewayProcessIdentity.parseUptimeMs(from: ["uptimeMs": -1]) == nil, "negative uptime is malformed")
        try expect(GatewayProcessIdentity.parseUptimeMs(from: ["uptimeMs": "4500"]) == 4500, "numeric strings are accepted")
        try expect(
            GatewayProcessIdentity.parseUptimeMs(from: ["snapshot": ["uptimeMs": 12.5]]) == 12.5,
            "hello-ok.snapshot.uptimeMs is the canonical path"
        )

        print("PASS: gateway process identity")
    }

    private static func helloPayload(uptimeMs: Double) -> [String: Any] {
        [
            "type": "hello-ok",
            "server": ["version": "2026.7.1-2", "connId": "c1"],
            "snapshot": ["uptimeMs": uptimeMs],
        ]
    }
}
