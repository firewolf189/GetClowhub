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
private enum GatewayTranscriptRehydrateTests {
    static func main() throws {
        try restoresArchivedTranscriptWhenLocalTurnsAreMissing()
        try leavesIntactWhenGatewayAlreadyHasLocalTurns()
        try leavesIntactWhenGatewayUsesUserSuffixAndAttachmentManifest()
        try rebuildsFromLocalTurnsWhenArchiveMissing()
        try rebuildsWhenStoreEntryMissingUsingKnownSessionId()
        try rebindsLiveJsonlUsingKnownGatewaySessionId()
        try doesNotRebuildNonEmptyUnrelatedTranscript()
        try skipsWhenNoPriorUserTurns()
        print("PASS: gateway transcript rehydrate")
    }

    private static func restoresArchivedTranscriptWhenLocalTurnsAreMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rehydrate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root
            .appendingPathComponent("agents/main/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

        let oldId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        let newId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        let key = "agent:main:thread-one"
        let oldBody = """
        {"type":"session","id":"\(oldId)"}
        {"type":"message","id":"u1","message":{"role":"user","content":"分析是否是优惠的价格","idempotencyKey":"OLDKEY"}}
        {"type":"message","id":"a1","message":{"role":"assistant","content":"Uppababy Cruz V2"}}
        """
        let reset = sessions.appendingPathComponent("\(oldId).jsonl.reset.2026-08-29T13-25-31.497Z")
        try oldBody.write(to: reset, atomically: true, encoding: .utf8)
        try """
        {"type":"session","id":"\(newId)"}
        {"type":"message","id":"u2","message":{"role":"user","content":"去咸鱼看杭州","idempotencyKey":"NEWKEY"}}
        """.write(to: sessions.appendingPathComponent("\(newId).jsonl"), atomically: true, encoding: .utf8)

        let store: [String: Any] = [
            key: [
                "sessionId": newId,
                "sessionFile": sessions.appendingPathComponent("\(newId).jsonl").path,
                "usageFamilySessionIds": [oldId, newId],
                "updatedAt": 1,
            ]
        ]
        let storeData = try JSONSerialization.data(withJSONObject: store, options: [.prettyPrinted])
        try storeData.write(to: sessions.appendingPathComponent("sessions.json"))

        let result = GatewayTranscriptRehydrate.ensurePriorTurnsPresent(
            openclawHome: root,
            sessionKey: key,
            localTurns: [
                .init(role: "user", text: "分析是否是优惠的价格", idempotencyKey: "OLDKEY", timestamp: nil),
                .init(role: "assistant", text: "Uppababy Cruz V2", idempotencyKey: "OLDKEY", timestamp: nil),
            ]
        )
        try expect(result.outcome == .restored, "missing local history must restore the reset archive: \(result.outcome)")
        try expect(result.gatewaySessionId == oldId, "result must report the restored session id")

        let updated = try JSONSerialization.jsonObject(
            with: Data(contentsOf: sessions.appendingPathComponent("sessions.json"))
        ) as? [String: Any]
        let entry = updated?[key] as? [String: Any]
        try expect(entry?["sessionId"] as? String == oldId, "store must point at the restored session id")
        let restoredText = try String(contentsOf: sessions.appendingPathComponent("\(oldId).jsonl"), encoding: .utf8)
        try expect(restoredText.contains("Uppababy Cruz V2"), "restored jsonl must include the archived assistant turn")
        try expect((entry?["updatedAt"] as? Int) ?? 0 > 1, "updatedAt must bump so idle reset does not fire immediately")
    }

    private static func leavesIntactWhenGatewayAlreadyHasLocalTurns() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rehydrate-ok-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("agents/main/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let sid = "cccccccc-cccc-cccc-cccc-cccccccccccc"
        let jsonl = sessions.appendingPathComponent("\(sid).jsonl")
        try """
        {"type":"message","message":{"role":"user","content":"hello","idempotencyKey":"K1"}}
        """.write(to: jsonl, atomically: true, encoding: .utf8)
        let store: [String: Any] = [
            "agent:main:ok": [
                "sessionId": sid,
                "sessionFile": jsonl.path,
            ]
        ]
        try JSONSerialization.data(withJSONObject: store).write(
            to: sessions.appendingPathComponent("sessions.json")
        )
        let result = GatewayTranscriptRehydrate.ensurePriorTurnsPresent(
            openclawHome: root,
            sessionKey: "agent:main:ok",
            localTurns: [.init(role: "user", text: "hello", idempotencyKey: "K1", timestamp: nil)]
        )
        try expect(result.outcome == .intact, "matching history must not rewrite the store: \(result.outcome)")
        try expect(result.gatewaySessionId == sid, "intact path must still report the live session id")
    }

    private static func leavesIntactWhenGatewayUsesUserSuffixAndAttachmentManifest() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rehydrate-suffix-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("agents/main/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let sid = "33c20f44-da8c-4331-864e-20742f2afe7d"
        let jsonl = sessions.appendingPathComponent("\(sid).jsonl")
        let userBody = "分析是否是优惠的价格，是否值得买二手\\n\\nAttachment manifest:\\nThese local attachments are provided by path"
        try """
        {"type":"session","id":"\(sid)"}
        {"type":"message","message":{"role":"user","content":"\(userBody)","idempotencyKey":"ED29F15E-630E-4A69-8ED9-2E5CD5CF6084:user"}}
        {"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"Uppababy Cruz V2"}]}}
        """.write(to: jsonl, atomically: true, encoding: .utf8)
        let store: [String: Any] = [
            "agent:main:9b50525a-aed3-4328-89c5-c5e23c2bfd8e": [
                "sessionId": sid,
                "sessionFile": jsonl.path,
            ]
        ]
        try JSONSerialization.data(withJSONObject: store).write(
            to: sessions.appendingPathComponent("sessions.json")
        )
        let before = try Data(contentsOf: jsonl)
        let result = GatewayTranscriptRehydrate.ensurePriorTurnsPresent(
            openclawHome: root,
            sessionKey: "agent:main:9b50525a-aed3-4328-89c5-c5e23c2bfd8e",
            localTurns: [
                .init(
                    role: "user",
                    text: "分析是否是优惠的价格，是否值得买二手",
                    idempotencyKey: "ED29F15E-630E-4A69-8ED9-2E5CD5CF6084",
                    timestamp: nil
                ),
                .init(role: "assistant", text: "Uppababy Cruz V2", idempotencyKey: nil, timestamp: nil),
            ],
            knownGatewaySessionId: sid
        )
        try expect(result.outcome == .intact, "live 闲鱼 identities must match :user keys: \(result.outcome)")
        let after = try Data(contentsOf: jsonl)
        try expect(after == before, "must not rewrite a matching live jsonl")
    }

    private static func rebuildsFromLocalTurnsWhenArchiveMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rehydrate-rebuild-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("agents/main/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let sid = "dddddddd-dddd-dddd-dddd-dddddddddddd"
        let jsonl = sessions.appendingPathComponent("\(sid).jsonl")
        try """
        {"type":"session","id":"\(sid)"}
        """.write(to: jsonl, atomically: true, encoding: .utf8)
        let store: [String: Any] = [
            "agent:main:rebuild": [
                "sessionId": sid,
                "sessionFile": jsonl.path,
                "updatedAt": 1,
            ]
        ]
        try JSONSerialization.data(withJSONObject: store).write(
            to: sessions.appendingPathComponent("sessions.json")
        )

        let result = GatewayTranscriptRehydrate.ensurePriorTurnsPresent(
            openclawHome: root,
            sessionKey: "agent:main:rebuild",
            localTurns: [
                .init(role: "user", text: "杭州闲鱼 Uppababy", idempotencyKey: "U1", timestamp: nil),
                .init(role: "assistant", text: "Cruz V2 值得买", idempotencyKey: nil, timestamp: nil),
            ]
        )
        try expect(result.outcome == .rebuilt, "missing archive must rebuild from local bubbles: \(result.outcome)")
        try expect(result.gatewaySessionId == sid, "rebuild must keep the current session id")
        let rebuilt = try String(contentsOf: jsonl, encoding: .utf8)
        try expect(rebuilt.contains("杭州闲鱼 Uppababy"), "rebuilt jsonl must include the local user turn")
        try expect(rebuilt.contains("Cruz V2 值得买"), "rebuilt jsonl must include the local assistant turn")
        try expect(rebuilt.contains("\"idempotencyKey\":\"U1\""), "rebuilt jsonl must keep the user idempotency key")
    }

    private static func rebuildsWhenStoreEntryMissingUsingKnownSessionId() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rehydrate-nostore-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let known = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
        let key = "agent:main:missing-store"
        let result = GatewayTranscriptRehydrate.ensurePriorTurnsPresent(
            openclawHome: root,
            sessionKey: key,
            localTurns: [
                .init(role: "user", text: "上次买的推车", idempotencyKey: "P1", timestamp: nil),
                .init(role: "assistant", text: "Uppababy", idempotencyKey: nil, timestamp: nil),
            ],
            knownGatewaySessionId: known
        )
        try expect(result.outcome == .rebuilt, "missing store must still rebuild: \(result.outcome)")
        try expect(result.gatewaySessionId == known, "rebuild must use the known gateway session id")
        let jsonl = root.appendingPathComponent("agents/main/sessions/\(known).jsonl")
        let body = try String(contentsOf: jsonl, encoding: .utf8)
        try expect(body.contains("上次买的推车"), "rebuilt jsonl must include local history")
        let store = try JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent("agents/main/sessions/sessions.json"))
        ) as? [String: Any]
        let entry = store?[key] as? [String: Any]
        try expect(entry?["sessionId"] as? String == known, "new store entry must point at the known session id")
    }

    private static func rebindsLiveJsonlUsingKnownGatewaySessionId() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rehydrate-known-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("agents/main/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let oldId = "ffffffff-ffff-ffff-ffff-ffffffffffff"
        let newId = "11111111-1111-1111-1111-111111111111"
        try """
        {"type":"message","message":{"role":"user","content":"分析是否是优惠的价格","idempotencyKey":"OLDKEY"}}
        {"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"Uppababy"}]}}
        """.write(to: sessions.appendingPathComponent("\(oldId).jsonl"), atomically: true, encoding: .utf8)
        try """
        {"type":"session","id":"\(newId)"}
        """.write(to: sessions.appendingPathComponent("\(newId).jsonl"), atomically: true, encoding: .utf8)
        let store: [String: Any] = [
            "agent:main:known": [
                "sessionId": newId,
                "sessionFile": sessions.appendingPathComponent("\(newId).jsonl").path,
                "updatedAt": 1,
            ]
        ]
        try JSONSerialization.data(withJSONObject: store).write(
            to: sessions.appendingPathComponent("sessions.json")
        )

        let result = GatewayTranscriptRehydrate.ensurePriorTurnsPresent(
            openclawHome: root,
            sessionKey: "agent:main:known",
            localTurns: [
                .init(role: "user", text: "分析是否是优惠的价格", idempotencyKey: "OLDKEY", timestamp: nil),
            ],
            knownGatewaySessionId: oldId
        )
        try expect(result.outcome == .restored, "known live jsonl must be rebound: \(result.outcome)")
        try expect(result.gatewaySessionId == oldId, "store must rebind to the known live session id")
        let updated = try JSONSerialization.jsonObject(
            with: Data(contentsOf: sessions.appendingPathComponent("sessions.json"))
        ) as? [String: Any]
        let entry = updated?["agent:main:known"] as? [String: Any]
        try expect(entry?["sessionId"] as? String == oldId, "sessions.json must point at the known live jsonl")
    }

    private static func doesNotRebuildNonEmptyUnrelatedTranscript() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rehydrate-noclobber-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("agents/main/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let sid = "99999999-9999-9999-9999-999999999999"
        let jsonl = sessions.appendingPathComponent("\(sid).jsonl")
        try """
        {"type":"session","id":"\(sid)"}
        {"type":"message","message":{"role":"user","content":"unrelated other thread","idempotencyKey":"OTHER"}}
        {"type":"message","message":{"role":"assistant","content":"keep me"}}
        """.write(to: jsonl, atomically: true, encoding: .utf8)
        let store: [String: Any] = [
            "agent:main:noclobber": [
                "sessionId": sid,
                "sessionFile": jsonl.path,
            ]
        ]
        try JSONSerialization.data(withJSONObject: store).write(
            to: sessions.appendingPathComponent("sessions.json")
        )
        let result = GatewayTranscriptRehydrate.ensurePriorTurnsPresent(
            openclawHome: root,
            sessionKey: "agent:main:noclobber",
            localTurns: [
                .init(role: "user", text: "分析是否是优惠的价格", idempotencyKey: "LOCAL", timestamp: nil),
            ]
        )
        try expect(result.outcome == .intact, "non-empty jsonl must not be rebuilt over: \(result.outcome)")
        let body = try String(contentsOf: jsonl, encoding: .utf8)
        try expect(body.contains("keep me"), "existing assistant turn must survive")
        try expect(!body.contains("分析是否是优惠的价格"), "must not clobber with local-only rebuild")
    }

    private static func skipsWhenNoPriorUserTurns() throws {
        let result = GatewayTranscriptRehydrate.ensurePriorTurnsPresent(
            openclawHome: FileManager.default.temporaryDirectory,
            sessionKey: "agent:main:empty",
            localTurns: []
        )
        try expect(result.outcome == .skipped, "/new or empty local history must not rewrite jsonl")
        try expect(result.gatewaySessionId == nil, "skip must not invent a gateway session id")
    }
}
