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
private enum StoppedRunTranscriptIsolationTests {
    static func main() throws {
        try testAppendsLeafTargetingStoppedUserMessage()
        try testBareSessionKeyResolvesMainAgent()
        try testRefusesToRewindPastANewerUserTurn()
        try testIsolatesWhenAssistantEntryWasNeverPersisted()
        try testIdempotentWhenLeafAlreadyTargetsUser()
        print("PASS: stopped run transcript isolation")
    }

    private static func testAppendsLeafTargetingStoppedUserMessage() throws {
        let key = "agent:main:conversation-one"
        let (root, transcript) = try fixture(sessionKey: key, userKey: "run-one", trailingUser: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = StoppedRunTranscriptIsolation.isolate(
            openclawHome: root,
            sessionKey: key,
            idempotencyKey: "run-one",
            policy: .init(readyAttempts: 3, readyDelayNanoseconds: 0)
        )
        try expect(outcome == .isolated, "a stopped turn must append a leaf: \(outcome)")

        let last = try lastJSON(transcript)
        try expect(last["type"] as? String == "leaf", "last entry must be a leaf")
        try expect(last["parentId"] as? String == "abort001", "leaf parent is the aborted assistant")
        try expect(last["targetId"] as? String == "user0001", "leaf must retarget the stopped user message")
    }

    private static func testBareSessionKeyResolvesMainAgent() throws {
        let canonical = "agent:main:conversation-two"
        let (root, transcript) = try fixture(sessionKey: canonical, userKey: "run-two", trailingUser: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = StoppedRunTranscriptIsolation.isolate(
            openclawHome: root,
            sessionKey: "conversation-two",
            idempotencyKey: "run-two",
            policy: .init(readyAttempts: 3, readyDelayNanoseconds: 0)
        )
        try expect(outcome == .isolated, "bare keys must resolve agent:main: \(outcome)")
        let last = try lastJSON(transcript)
        try expect(last["targetId"] as? String == "user0001", "bare-key isolation must still target the user turn")
    }

    private static func testRefusesToRewindPastANewerUserTurn() throws {
        let key = "agent:main:conversation-three"
        let (root, _) = try fixture(sessionKey: key, userKey: "run-three", trailingUser: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = StoppedRunTranscriptIsolation.isolate(
            openclawHome: root,
            sessionKey: key,
            idempotencyKey: "run-three",
            policy: .init(readyAttempts: 3, readyDelayNanoseconds: 0)
        )
        try expect(
            outcome == .refusedBecauseSessionAdvanced,
            "a newer user turn must block isolation: \(outcome)"
        )
    }

    private static func testIsolatesWhenAssistantEntryWasNeverPersisted() throws {
        let key = "agent:main:conversation-six"
        let (root, transcript) = try fixture(sessionKey: key, userKey: "run-six", trailingUser: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let userOnly = try String(contentsOf: transcript, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(2)
            .joined(separator: "\n") + "\n"
        try userOnly.write(to: transcript, atomically: true, encoding: .utf8)

        let outcome = StoppedRunTranscriptIsolation.isolate(
            openclawHome: root,
            sessionKey: key,
            idempotencyKey: "run-six",
            policy: .init(readyAttempts: 3, readyDelayNanoseconds: 0)
        )
        try expect(outcome == .isolated, "stop before assistant persist must still isolate: \(outcome)")
        let last = try lastJSON(transcript)
        try expect(last["type"] as? String == "leaf", "leaf is appended after the user turn")
        try expect(last["parentId"] as? String == "user0001", "parent is the user entry")
        try expect(last["targetId"] as? String == "user0001", "target is the user entry")
    }

    private static func testIdempotentWhenLeafAlreadyTargetsUser() throws {
        let key = "agent:main:conversation-seven"
        let (root, _) = try fixture(sessionKey: key, userKey: "run-seven", trailingUser: false)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = StoppedRunTranscriptIsolation.isolate(
            openclawHome: root,
            sessionKey: key,
            idempotencyKey: "run-seven",
            policy: .init(readyAttempts: 3, readyDelayNanoseconds: 0)
        )
        let second = StoppedRunTranscriptIsolation.isolate(
            openclawHome: root,
            sessionKey: key,
            idempotencyKey: "run-seven",
            policy: .init(readyAttempts: 3, readyDelayNanoseconds: 0)
        )
        try expect(second == .alreadyIsolated, "a second isolate must not stack leaves: \(second)")
    }

    private static func fixture(sessionKey: String, userKey: String, trailingUser: Bool) throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gch-stopped-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("agents/main/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let sessionId = "11111111-2222-3333-4444-555555555555"
        let transcript = sessions.appendingPathComponent("\(sessionId).jsonl")
        var lines: [[String: Any]] = [
            [
                "type": "session",
                "version": 3,
                "id": sessionId,
                "timestamp": "2026-07-31T00:00:00.000Z",
                "cwd": "/tmp",
            ],
            [
                "type": "message",
                "id": "user0001",
                "parentId": NSNull(),
                "timestamp": "2026-07-31T00:00:01.000Z",
                "message": [
                    "role": "user",
                    "content": "keep me",
                    "idempotencyKey": "\(userKey):user",
                ] as [String: Any],
            ],
            [
                "type": "message",
                "id": "abort001",
                "parentId": "user0001",
                "timestamp": "2026-07-31T00:00:02.000Z",
                "message": [
                    "role": "assistant",
                    "content": [["type": "text", "text": "partial"]],
                    "stopReason": "aborted",
                ] as [String: Any],
            ],
        ]
        if trailingUser {
            lines.append([
                "type": "message",
                "id": "user0002",
                "parentId": "abort001",
                "timestamp": "2026-07-31T00:00:03.000Z",
                "message": ["role": "user", "content": "too late"] as [String: Any],
            ])
        }
        let body = try lines.map { object -> String in
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return String(data: data, encoding: .utf8)!
        }.joined(separator: "\n") + "\n"
        try body.write(to: transcript, atomically: true, encoding: .utf8)
        let store: [String: Any] = [
            sessionKey: [
                "sessionId": sessionId,
                "sessionFile": transcript.path,
            ] as [String: Any],
        ]
        let storeData = try JSONSerialization.data(withJSONObject: store, options: [.sortedKeys])
        try storeData.write(to: sessions.appendingPathComponent("sessions.json"))
        return (root, transcript)
    }

    private static func lastJSON(_ transcript: URL) throws -> [String: Any] {
        let line = try String(contentsOf: transcript, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .last
            .map(String.init) ?? ""
        let data = line.data(using: .utf8)!
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
}
