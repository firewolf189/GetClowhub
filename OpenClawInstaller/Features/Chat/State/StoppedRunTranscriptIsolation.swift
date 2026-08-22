import Foundation

/// After a user-stopped run, OpenClaw keeps the aborted assistant entry on the
/// active model branch. Appending a `leaf` that targets the stopped user
/// message moves the next `chat.send` off that partial reply — the same
/// contract as the Windows client (`stopped_context.rs`).
enum StoppedRunTranscriptIsolation {
    enum Outcome: Equatable, Sendable {
        case isolated
        case alreadyIsolated
        case refusedBecauseSessionAdvanced
        case failed(String)
    }

    struct Policy: Equatable, Sendable {
        var readyAttempts: Int
        var readyDelayNanoseconds: UInt64

        static let `default` = Policy(readyAttempts: 20, readyDelayNanoseconds: 50_000_000)
    }

    @discardableResult
    static func isolate(
        openclawHome: URL,
        sessionKey: String,
        idempotencyKey: String,
        policy: Policy = .default
    ) -> Outcome {
        let trimmedKey = idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, trimmedKey.count <= 256 else {
            return .failed("invalid run idempotency key")
        }
        do {
            let transcript = try resolveTranscriptPath(
                openclawHome: openclawHome,
                sessionKey: sessionKey,
                policy: policy
            )
            let (entries, userIndex) = try readStoppedTurnWhenReady(
                transcriptPath: transcript,
                idempotencyKey: trimmedKey,
                policy: policy
            )
            guard let userId = string(entries[userIndex]["id"]), !userId.isEmpty else {
                return .failed("stopped user message has no entry id")
            }
            guard let last = entries.last else {
                return .failed("empty session transcript")
            }
            if string(last["type"]) == "leaf", string(last["targetId"]) == userId {
                return .alreadyIsolated
            }
            guard let parentId = string(last["id"]), !parentId.isEmpty else {
                return .failed("last session entry has no id")
            }
            guard let timestamp = string(last["timestamp"]), !timestamp.isEmpty else {
                return .failed("last session entry has no timestamp")
            }
            let leaf: [String: Any] = [
                "type": "leaf",
                "id": String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased(),
                "parentId": parentId,
                "timestamp": timestamp,
                "targetId": userId,
            ]
            let encoded = try JSONSerialization.data(withJSONObject: leaf, options: [.sortedKeys])
            var existing = try Data(contentsOf: transcript)
            if existing.last != 0x0a {
                existing.append(0x0a)
            }
            existing.append(encoded)
            existing.append(0x0a)
            try existing.write(to: transcript, options: .atomic)
            return .isolated
        } catch IsolationError.sessionAdvanced {
            return .refusedBecauseSessionAdvanced
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private enum IsolationError: Error, LocalizedError {
        case message(String)
        case sessionAdvanced

        var errorDescription: String? {
            switch self {
            case .message(let text): text
            case .sessionAdvanced: "session advanced before the stopped response could be isolated"
            }
        }
    }

    private static func resolveTranscriptPath(
        openclawHome: URL,
        sessionKey: String,
        policy: Policy
    ) throws -> URL {
        let trimmed = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 1024 else {
            throw IsolationError.message("invalid session key")
        }
        let (agentId, candidateKeys) = try sessionLookup(trimmed)
        let sessionsDir = openclawHome
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent(agentId, isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        let storeURL = sessionsDir.appendingPathComponent("sessions.json")
        let storeData = try Data(contentsOf: storeURL)
        guard let root = try JSONSerialization.jsonObject(with: storeData) as? [String: Any] else {
            throw IsolationError.message("sessions.json is not an object")
        }
        let lowered = Set(candidateKeys.map { $0.lowercased() })
        guard let entry = root.first(where: { lowered.contains($0.key.lowercased()) })?.value as? [String: Any] else {
            throw IsolationError.message("gateway session was not found")
        }

        let configured = (entry["sessionFile"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let transcriptPath: URL
        if let configured, !configured.isEmpty {
            let asURL = URL(fileURLWithPath: configured)
            transcriptPath = asURL.isFileURL && configured.hasPrefix("/")
                ? asURL
                : sessionsDir.appendingPathComponent(configured)
        } else {
            guard let sessionId = entry["sessionId"] as? String, isSafePathComponent(sessionId) else {
                throw IsolationError.message("gateway session has no session id")
            }
            transcriptPath = sessionsDir.appendingPathComponent("\(sessionId).jsonl")
        }

        let canonicalSessions = sessionsDir.resolvingSymlinksInPath().standardizedFileURL
        let canonicalTranscript = try canonicalizeWhenReady(transcriptPath, policy: policy)
        let transcriptPathString = canonicalTranscript.path
        let sessionsPathString = canonicalSessions.path
        guard transcriptPathString == sessionsPathString
            || transcriptPathString.hasPrefix(sessionsPathString.hasSuffix("/") ? sessionsPathString : sessionsPathString + "/")
        else {
            throw IsolationError.message("session transcript is outside the managed state directory")
        }
        guard canonicalTranscript.pathExtension.lowercased() == "jsonl" else {
            throw IsolationError.message("session transcript is outside the managed state directory")
        }
        return canonicalTranscript
    }

    private static func sessionLookup(_ sessionKey: String) throws -> (String, [String]) {
        if let rest = sessionKey.splitPrefix("agent:") {
            guard let slash = rest.firstIndex(of: ":") else {
                throw IsolationError.message("malformed agent session key")
            }
            let agentId = String(rest[..<slash])
            let remainder = String(rest[rest.index(after: slash)...])
            guard isSafePathComponent(agentId), !remainder.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw IsolationError.message("unsafe agent session key")
            }
            return (agentId, [sessionKey])
        }
        return ("main", [sessionKey, "agent:main:\(sessionKey)"])
    }

    private static func canonicalizeWhenReady(_ path: URL, policy: Policy) throws -> URL {
        for attempt in 0..<policy.readyAttempts {
            if FileManager.default.fileExists(atPath: path.path) {
                return path.resolvingSymlinksInPath().standardizedFileURL
            }
            if attempt + 1 == policy.readyAttempts {
                throw IsolationError.message("resolve \(path.path)")
            }
            sleepNanos(policy.readyDelayNanoseconds)
        }
        throw IsolationError.message("resolve \(path.path)")
    }

    private static func readStoppedTurnWhenReady(
        transcriptPath: URL,
        idempotencyKey: String,
        policy: Policy
    ) throws -> ([[String: Any]], Int) {
        let gatewayUserKey = "\(idempotencyKey):user"
        for attempt in 0..<policy.readyAttempts {
            let entries = try readTranscriptEntries(transcriptPath)
            if let userIndex = entries.lastIndex(where: { entry in
                messageRole(entry) == "user" && {
                    guard let key = userIdempotencyKey(entry) else { return false }
                    return key == idempotencyKey || key == gatewayUserKey
                }()
            }) {
                if entries[(userIndex + 1)...].contains(where: { messageRole($0) == "user" }) {
                    throw IsolationError.sessionAdvanced
                }
                return (entries, userIndex)
            }
            if attempt + 1 == policy.readyAttempts {
                throw IsolationError.message("stopped user message was not found")
            }
            sleepNanos(policy.readyDelayNanoseconds)
        }
        throw IsolationError.message("stopped user message was not found")
    }

    private static func readTranscriptEntries(_ path: URL) throws -> [[String: Any]] {
        let body = try String(contentsOf: path, encoding: .utf8)
        var entries: [[String: Any]] = []
        for (index, line) in body.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let data = trimmed.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw IsolationError.message("parse \(path.lastPathComponent) line \(index + 1)")
            }
            entries.append(object)
        }
        guard string(entries.first?["type"]) == "session" else {
            throw IsolationError.message("session transcript has no valid header")
        }
        return entries
    }

    private static func messageRole(_ entry: [String: Any]) -> String? {
        guard string(entry["type"]) == "message",
              let message = entry["message"] as? [String: Any] else {
            return nil
        }
        return string(message["role"])
    }

    private static func userIdempotencyKey(_ entry: [String: Any]) -> String? {
        guard let message = entry["message"] as? [String: Any] else { return nil }
        if let key = string(message["idempotencyKey"]), !key.isEmpty { return key }
        if let nested = message["__openclaw"] as? [String: Any],
           let key = string(nested["idempotencyKey"]), !key.isEmpty {
            return key
        }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    private static func isSafePathComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= 128
            && value != "."
            && value != ".."
            && value.unicodeScalars.allSatisfy { scalar in
                CharacterSet.alphanumerics.contains(scalar)
                    || scalar == "-"
                    || scalar == "_"
                    || scalar == "."
            }
    }

    private static func sleepNanos(_ nanos: UInt64) {
        guard nanos > 0 else { return }
        var spec = timespec(
            tv_sec: time_t(nanos / 1_000_000_000),
            tv_nsec: Int(nanos % 1_000_000_000)
        )
        nanosleep(&spec, nil)
    }
}

private extension String {
    func splitPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
