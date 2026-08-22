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

/// Scripted inbound WebSocket frames. Product tests drive handshake + abort
/// parsers with recorded gateway JSON instead of `URLSessionWebSocketTask`.
private struct FakeGatewaySocket {
    private var inbound: [String] = []
    private(set) var outbound: [String] = []

    mutating func peerSends(_ text: String) {
        inbound.append(text)
    }

    mutating func send(_ text: String) {
        outbound.append(text)
    }

    mutating func receive() -> String? {
        guard !inbound.isEmpty else { return nil }
        return inbound.removeFirst()
    }
}

@main
private enum GatewayFakeWebSocketTests {
    static func main() async throws {
        try testMalformedFrameIsIgnored()
        try testHelloOkFingerprintFromRecordedFrames()
        try await testAbortWithoutRunIdFromRecordedFrames()
        try testSameProcessReconnectKeepsEpoch()
        print("PASS: gateway fake websocket frames")
    }

    private static func testMalformedFrameIsIgnored() throws {
        try expect(GatewayInboundJSON.object(from: "not-json") == nil, "garbage frames must not parse")
        try expect(GatewayInboundJSON.object(from: "[1,2]") == nil, "non-object JSON must not parse")
    }

    private static func testHelloOkFingerprintFromRecordedFrames() throws {
        var socket = FakeGatewaySocket()
        socket.peerSends(connectChallengeFrame(nonce: "nonce-1"))
        socket.peerSends(helloOkFrame(id: "connect-1", uptimeMs: 30_000))

        var identity = GatewayProcessIdentity()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var sawChallenge = false

        while let text = socket.receive() {
            guard let json = GatewayInboundJSON.object(from: text) else {
                throw TestFailure.assertion("recorded frame must parse")
            }
            let type = json["type"] as? String
            if type == "event", json["event"] as? String == "connect.challenge" {
                let nonce = (json["payload"] as? [String: Any])?["nonce"] as? String
                try expect(nonce == "nonce-1", "challenge nonce must round-trip")
                sawChallenge = true
                socket.send(#"{"type":"req","id":"connect-1","method":"connect"}"#)
                continue
            }
            if type == "res" {
                identity.applyHello(payload: json["payload"] as? [String: Any], now: now)
            }
        }

        try expect(sawChallenge, "the scripted socket must deliver connect.challenge")
        try expect(socket.outbound.count == 1, "the client side of the fixture sends one connect")
        try expect(identity.fingerprint.isKnown, "hello-ok uptime must identify the process")
        try expect(identity.fingerprint.epoch == 1, "the first hello-ok advances epoch")
        try expect(
            abs((identity.fingerprint.startedAtEstimate?.timeIntervalSince1970 ?? 0) - (now.timeIntervalSince1970 - 30)) < 0.001,
            "fake WS hello-ok must yield the same start estimate as a live handshake"
        )
    }

    private static func testAbortWithoutRunIdFromRecordedFrames() async throws {
        let registry = GatewayChatAbortRequestRegistry()
        async let result: GatewayChatAbortResult = withCheckedContinuation { continuation in
            registry.register(
                requestId: "abort-session",
                expectedRunId: nil,
                continuation: continuation
            )
        }
        while registry.count != 1 { await Task.yield() }

        var socket = FakeGatewaySocket()
        socket.peerSends(abortFrame(id: "abort-session", aborted: true, runIds: ["run-live"]))
        guard let text = socket.receive(),
              let json = GatewayInboundJSON.object(from: text) else {
            throw TestFailure.assertion("abort frame must parse")
        }
        try expect(
            registry.resolve(
                requestId: json["id"] as? String ?? "",
                response: GatewayChatAbortResponse.parse(fromRPC: json),
                rejectionMessage: nil
            ),
            "a recorded chat.abort res must resolve the pending request"
        )
        let abortResult = await result
        try expect(
            abortResult == .confirmed(runIds: ["run-live"]),
            "session-level abort without expectedRunId confirms whatever runIds the gateway reports"
        )
        try expect(registry.count == 0, "the abort continuation must be released")
    }

    private static func testSameProcessReconnectKeepsEpoch() throws {
        var identity = GatewayProcessIdentity()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var socket = FakeGatewaySocket()
        socket.peerSends(helloOkFrame(id: "c1", uptimeMs: 10_000))
        socket.peerSends(helloOkFrame(id: "c2", uptimeMs: 12_000))

        if let first = socket.receive(), let json = GatewayInboundJSON.object(from: first) {
            identity.applyHello(payload: json["payload"] as? [String: Any], now: t0)
        }
        if let second = socket.receive(), let json = GatewayInboundJSON.object(from: second) {
            identity.applyHello(
                payload: json["payload"] as? [String: Any],
                now: t0.addingTimeInterval(2)
            )
        }
        try expect(identity.fingerprint.epoch == 1, "two hello-ok frames from the same uptime window keep one epoch")
        try expect(identity.fingerprint.allowsIdempotencyProbe, "same-process reconnect may probe")
    }

    private static func connectChallengeFrame(nonce: String) -> String {
        frame([
            "type": "event",
            "event": "connect.challenge",
            "payload": ["nonce": nonce],
        ])
    }

    private static func helloOkFrame(id: String, uptimeMs: Double) -> String {
        frame([
            "type": "res",
            "id": id,
            "ok": true,
            "payload": [
                "type": "hello-ok",
                "protocol": 3,
                "server": [
                    "version": "2026.7.1-2",
                    "connId": "test-conn",
                ],
                "snapshot": [
                    "uptimeMs": uptimeMs,
                ],
            ],
        ])
    }

    private static func abortFrame(id: String, aborted: Bool, runIds: [String]) -> String {
        frame([
            "type": "res",
            "id": id,
            "ok": true,
            "payload": [
                "aborted": aborted,
                "runIds": runIds,
            ],
        ])
    }

    private static func frame(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(data: data, encoding: .utf8)!
    }
}
