import Foundation

/// When OpenClaw archives a transcript (`*.jsonl.reset.*`) the Mac UI still
/// shows the local bubbles. The next `chat.send` only carries the latest
/// sentence, so the model "forgets" the thread. Restore the archived jsonl
/// (and bump `updatedAt`) before send so named desktop sessions survive
/// inactivity resets. If the archive is gone, rebuild user/assistant jsonl
/// from the local bubbles. `/new` clears local messages first, so this is a
/// no-op.
enum GatewayTranscriptRehydrate {
    enum Outcome: Equatable {
        case intact
        case restored
        case rebuilt
        case skipped
    }

    struct Result: Equatable {
        var outcome: Outcome
        var gatewaySessionId: String?

        static let skipped = Result(outcome: .skipped, gatewaySessionId: nil)
    }

    struct LocalTurn: Equatable {
        var role: String
        var text: String
        var idempotencyKey: String?
        var timestamp: Date?
    }

    @discardableResult
    static func ensurePriorTurnsPresent(
        openclawHome: URL,
        sessionKey: String,
        localTurns: [LocalTurn],
        knownGatewaySessionId: String? = nil
    ) -> Result {
        let priorUsers = localTurns.filter {
            $0.role == "user" && !($0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        guard priorUsers.count >= 1 else { return .skipped }

        let trimmedKey = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, trimmedKey.count <= 1024 else { return .skipped }
        let knownId = sanitizedSessionId(knownGatewaySessionId)

        do {
            let (agentId, candidateKeys) = try sessionLookup(trimmedKey)
            let sessionsDir = openclawHome
                .appendingPathComponent("agents", isDirectory: true)
                .appendingPathComponent(agentId, isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
            try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
            let storeURL = sessionsDir.appendingPathComponent("sessions.json")

            var root: [String: Any] = [:]
            if let storeData = try? Data(contentsOf: storeURL),
               let parsed = try JSONSerialization.jsonObject(with: storeData) as? [String: Any] {
                root = parsed
            }
            let lowered = Set(candidateKeys.map { $0.lowercased() })
            let storeKey = root.keys.first(where: { lowered.contains($0.lowercased()) })
                ?? candidateKeys[0]
            var entry = root[storeKey] as? [String: Any] ?? [:]

            let currentPath = transcriptURL(entry: entry, sessionsDir: sessionsDir)
            let currentKeys = transcriptUserKeys(at: currentPath)
            let missing = priorUsers.filter { turn in
                turnIdentities(turn).isDisjoint(with: currentKeys)
            }
            if missing.isEmpty {
                let currentId = sanitizedSessionId(entry["sessionId"] as? String) ?? knownId
                return Result(outcome: .intact, gatewaySessionId: currentId)
            }

            var family = ((entry["usageFamilySessionIds"] as? [String]) ?? [])
                + [entry["sessionId"] as? String].compactMap { $0 }
            if let knownId, !family.contains(knownId) {
                family.append(knownId)
            }
            let requiredIdentities = turnIdentities(missing[0])
            if let match = newestMatchingTranscript(
                sessionsDir: sessionsDir,
                sessionIds: family,
                requiredIdentities: requiredIdentities
            ) {
                let restoredId = match.sessionId
                let dest = sessionsDir.appendingPathComponent("\(restoredId).jsonl")
                if match.isResetArchive {
                    let body = try Data(contentsOf: match.url)
                    try body.write(to: dest, options: .atomic)
                }
                try commitEntry(
                    root: &root,
                    storeKey: storeKey,
                    entry: &entry,
                    sessionId: restoredId,
                    dest: dest,
                    family: family,
                    storeURL: storeURL
                )
                return Result(outcome: .restored, gatewaySessionId: restoredId)
            }

            // Never overwrite a live transcript that already has user turns.
            // Identity mismatches on a rich jsonl must not clobber tool history.
            if !currentKeys.isEmpty {
                let currentId = sanitizedSessionId(entry["sessionId"] as? String) ?? knownId
                return Result(outcome: .intact, gatewaySessionId: currentId)
            }

            let rebuiltId = sanitizedSessionId(entry["sessionId"] as? String)
                ?? knownId
                ?? UUID().uuidString.lowercased()
            let dest = sessionsDir.appendingPathComponent("\(rebuiltId).jsonl")
            let body = try rebuiltTranscript(
                sessionId: rebuiltId,
                agentId: agentId,
                openclawHome: openclawHome,
                turns: localTurns
            )
            guard !body.isEmpty else { return .skipped }
            try body.write(to: dest, options: .atomic)
            try commitEntry(
                root: &root,
                storeKey: storeKey,
                entry: &entry,
                sessionId: rebuiltId,
                dest: dest,
                family: family,
                storeURL: storeURL
            )
            return Result(outcome: .rebuilt, gatewaySessionId: rebuiltId)
        } catch {
            NSLog("[Chat] transcript rehydrate skipped: %@", error.localizedDescription)
            return .skipped
        }
    }

    private static func turnIdentities(_ turn: LocalTurn) -> Set<String> {
        var keys = Set<String>()
        if let key = normalizedIdempotencyKey(turn.idempotencyKey) {
            keys.insert("id:" + key)
        }
        let compact = compactUserText(turn.text)
        if !compact.isEmpty {
            keys.insert("text:" + compact)
        }
        return keys
    }

    /// Gateway user rows stamp `uuid:user`; the Mac UI stores the bare uuid.
    private static func normalizedIdempotencyKey(_ raw: String?) -> String? {
        var key = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else { return nil }
        key = key.lowercased()
        if key.hasSuffix(":user") {
            key = String(key.dropLast(5))
        }
        return key.isEmpty ? nil : key
    }

    /// OpenClaw appends an attachment manifest to the persisted user text.
    private static func compactUserText(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let markers = ["\n\nAttachment manifest:", "\nAttachment manifest:"]
        for marker in markers {
            if let range = trimmed.range(of: marker, options: .caseInsensitive) {
                trimmed = String(trimmed[..<range.lowerBound])
                break
            }
        }
        return String(
            trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(160)
                .lowercased()
        )
    }

    private static func transcriptUserKeys(at url: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        var keys = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  obj["type"] as? String == "message" else { continue }
            let message = obj["message"] as? [String: Any] ?? [:]
            guard (message["role"] as? String) == "user" else { continue }
            if let key = normalizedIdempotencyKey(
                (message["idempotencyKey"] as? String)
                    ?? ((message["__openclaw"] as? [String: Any])?["idempotencyKey"] as? String)
            ) {
                keys.insert("id:" + key)
            }
            let content = message["content"]
            var textContent = ""
            if let s = content as? String {
                textContent = s
            } else if let parts = content as? [Any] {
                textContent = parts.compactMap { part in
                    (part as? [String: Any])?["text"] as? String
                }.joined()
            }
            let compact = compactUserText(textContent)
            if !compact.isEmpty {
                keys.insert("text:" + compact)
            }
        }
        return keys
    }

    private struct TranscriptMatch {
        var url: URL
        var sessionId: String
        var modified: Date
        var isResetArchive: Bool
    }

    private static func newestMatchingTranscript(
        sessionsDir: URL,
        sessionIds: [String],
        requiredIdentities: Set<String>
    ) -> TranscriptMatch? {
        guard !requiredIdentities.isEmpty else { return nil }
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: sessionsDir.path)) ?? []
        let idSet = Set(sessionIds.compactMap { sanitizedSessionId($0) })
        var matches: [TranscriptMatch] = []
        for name in names {
            let isReset = name.contains(".jsonl.reset.")
            let isLive = name.hasSuffix(".jsonl") && !name.contains(".jsonl.")
            guard isReset || isLive else { continue }
            let sessionId = String(name.prefix { $0 != "." })
            guard idSet.contains(sessionId) else { continue }
            let url = sessionsDir.appendingPathComponent(name)
            let keys = transcriptUserKeys(at: url)
            guard !keys.isDisjoint(with: requiredIdentities) else { continue }
            let modified = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
            matches.append(
                TranscriptMatch(
                    url: url,
                    sessionId: sessionId,
                    modified: modified,
                    isResetArchive: isReset
                )
            )
        }
        return matches.max(by: { $0.modified < $1.modified })
    }

    private static func transcriptURL(entry: [String: Any], sessionsDir: URL) -> URL {
        if let configured = (entry["sessionFile"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            if configured.hasPrefix("/") {
                return URL(fileURLWithPath: configured)
            }
            return sessionsDir.appendingPathComponent(configured)
        }
        let sessionId = (entry["sessionId"] as? String) ?? "session"
        return sessionsDir.appendingPathComponent("\(sessionId).jsonl")
    }

    private static func sessionLookup(_ sessionKey: String) throws -> (String, [String]) {
        if sessionKey.hasPrefix("agent:") {
            let rest = sessionKey.dropFirst("agent:".count)
            guard let slash = rest.firstIndex(of: ":") else {
                throw NSError(domain: "GatewayTranscriptRehydrate", code: 1)
            }
            let agentId = String(rest[..<slash])
            return (agentId, [sessionKey])
        }
        return ("main", [sessionKey, "agent:main:\(sessionKey)"])
    }

    private static func sanitizedSessionId(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 128 else { return nil }
        guard trimmed.allSatisfy({ ch in
            ch.isASCII && (ch.isLetter || ch.isNumber || ch == "-" || ch == "_")
        }) else {
            return nil
        }
        return trimmed
    }

    private static func commitEntry(
        root: inout [String: Any],
        storeKey: String,
        entry: inout [String: Any],
        sessionId: String,
        dest: URL,
        family: [String],
        storeURL: URL
    ) throws {
        entry["sessionId"] = sessionId
        entry["sessionFile"] = dest.path
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        entry["updatedAt"] = nowMs
        entry["lastInteractionAt"] = nowMs
        var ids = family
        if !ids.contains(sessionId) { ids.append(sessionId) }
        entry["usageFamilySessionIds"] = ids
        if entry["origin"] == nil {
            entry["origin"] = [
                "provider": "webchat",
                "surface": "webchat",
                "chatType": "direct",
            ]
            entry["chatType"] = "direct"
            entry["lastChannel"] = "webchat"
        }
        root[storeKey] = entry
        let updated = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try updated.write(to: storeURL, options: .atomic)
    }

    private static func rebuiltTranscript(
        sessionId: String,
        agentId: String,
        openclawHome: URL,
        turns: [LocalTurn]
    ) throws -> Data {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = Date()
        let cwdName = agentId == "main" ? "workspace/main" : "workspace-\(agentId)"
        let cwd = openclawHome.appendingPathComponent(cwdName).path
        let usable = turns.filter {
            ($0.role == "user" || $0.role == "assistant")
                && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !usable.isEmpty else { return Data() }

        var lines: [String] = []
        let header: [String: Any] = [
            "type": "session",
            "version": 3,
            "id": sessionId,
            "timestamp": iso.string(from: usable.first?.timestamp ?? now),
            "cwd": cwd,
        ]
        lines.append(try jsonLine(header))

        var parentId: String?
        for turn in usable {
            let role = turn.role == "user" ? "user" : "assistant"
            let id = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
            let ts = turn.timestamp ?? now
            var message: [String: Any] = [
                "role": role,
                "timestamp": Int(ts.timeIntervalSince1970 * 1000),
            ]
            if role == "user" {
                message["content"] = turn.text
                message["__openclaw"] = ["senderIsOwner": true]
            } else {
                message["content"] = [["type": "text", "text": turn.text]]
            }
            if let key = turn.idempotencyKey?.trimmingCharacters(in: .whitespacesAndNewlines),
               !key.isEmpty {
                message["idempotencyKey"] = key
            }
            var obj: [String: Any] = [
                "type": "message",
                "id": id,
                "timestamp": iso.string(from: ts),
                "message": message,
            ]
            if let parentId {
                obj["parentId"] = parentId
            } else {
                obj["parentId"] = NSNull()
            }
            lines.append(try jsonLine(obj))
            parentId = id
        }
        guard let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8) else {
            return Data()
        }
        return data
    }

    private static func jsonLine(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.withoutEscapingSlashes]
        )
        guard let line = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "GatewayTranscriptRehydrate", code: 2)
        }
        return line
    }
}
