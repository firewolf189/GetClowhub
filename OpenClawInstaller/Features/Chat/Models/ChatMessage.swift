import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: ChatRole
    let content: String
    let agentId: String?
    let agentEmoji: String?
    let attachments: [URL]
    let taskStatus: TaskStatus
    let scrollTargetId: UUID?
    let timestamp: Date?
    let completedAt: Date?
    let activityEvents: [ChatActivityEvent]
    /// Gateway transcript entry id (`jsonl` envelope `id` / history `id`).
    let gatewayEntryId: String?
    /// Client `chat.send` idempotency key. User rows stamp this before the
    /// run binding is created so stop-isolation and history backfill share
    /// one identity.
    let idempotencyKey: String?

    init(
        role: ChatRole,
        content: String,
        agentId: String? = nil,
        agentEmoji: String? = nil,
        attachments: [URL] = [],
        taskStatus: TaskStatus = .completed,
        id: UUID = UUID(),
        scrollTargetId: UUID? = nil,
        timestamp: Date? = Date(),
        completedAt: Date? = nil,
        activityEvents: [ChatActivityEvent] = [],
        gatewayEntryId: String? = nil,
        idempotencyKey: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.agentId = agentId
        self.agentEmoji = agentEmoji
        self.attachments = attachments
        self.taskStatus = taskStatus
        self.scrollTargetId = scrollTargetId
        self.timestamp = timestamp
        self.completedAt = completedAt
        self.activityEvents = activityEvents
        self.gatewayEntryId = Self.normalizedIdentity(gatewayEntryId)
        self.idempotencyKey = Self.normalizedIdentity(idempotencyKey)
    }

    func withTaskStatus(_ taskStatus: TaskStatus, content: String? = nil) -> ChatMessage {
        ChatMessage(
            role: role,
            content: content ?? self.content,
            agentId: agentId,
            agentEmoji: agentEmoji,
            attachments: attachments,
            taskStatus: taskStatus,
            id: id,
            scrollTargetId: scrollTargetId,
            timestamp: timestamp,
            completedAt: completedAt,
            activityEvents: activityEvents,
            gatewayEntryId: gatewayEntryId,
            idempotencyKey: idempotencyKey
        )
    }

    /// Fill missing gateway identities without clobbering values already stamped
    /// at send time.
    func withGatewayIdentity(gatewayEntryId: String? = nil, idempotencyKey: String? = nil) -> ChatMessage {
        let nextEntry = self.gatewayEntryId ?? Self.normalizedIdentity(gatewayEntryId)
        let nextKey = self.idempotencyKey ?? Self.normalizedIdentity(idempotencyKey)
        if nextEntry == self.gatewayEntryId && nextKey == self.idempotencyKey {
            return self
        }
        return ChatMessage(
            role: role,
            content: content,
            agentId: agentId,
            agentEmoji: agentEmoji,
            attachments: attachments,
            taskStatus: taskStatus,
            id: id,
            scrollTargetId: scrollTargetId,
            timestamp: timestamp,
            completedAt: completedAt,
            activityEvents: activityEvents,
            gatewayEntryId: nextEntry,
            idempotencyKey: nextKey
        )
    }

    private static func normalizedIdentity(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case agentId
        case agentEmoji
        case attachments
        case taskStatus
        case scrollTargetId
        case timestamp
        case completedAt
        case activityEvents
        case gatewayEntryId
        case idempotencyKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(ChatRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        agentId = try container.decodeIfPresent(String.self, forKey: .agentId)
        agentEmoji = try container.decodeIfPresent(String.self, forKey: .agentEmoji)
        attachments = try container.decodeIfPresent([URL].self, forKey: .attachments) ?? []
        taskStatus = try container.decodeIfPresent(TaskStatus.self, forKey: .taskStatus) ?? .completed
        scrollTargetId = try container.decodeIfPresent(UUID.self, forKey: .scrollTargetId)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        activityEvents = try container.decodeIfPresent([ChatActivityEvent].self, forKey: .activityEvents) ?? []
        gatewayEntryId = Self.normalizedIdentity(try container.decodeIfPresent(String.self, forKey: .gatewayEntryId))
        idempotencyKey = Self.normalizedIdentity(try container.decodeIfPresent(String.self, forKey: .idempotencyKey))
    }

    enum ChatRole: String, Codable, Equatable {
        case user
        case assistant
    }

    enum TaskStatus: String, Codable, Equatable {
        case loading
        case background
        case completed
        case timedOut
        case cancelled

        var isTerminal: Bool {
            switch self {
            case .completed, .timedOut, .cancelled:
                return true
            case .loading, .background:
                return false
            }
        }
    }
}

/// One row from `chat.history`, used to stamp local `ChatMessage` identity
/// without importing gateway snapshot types into the message model.
struct ChatGatewayMessageIdentity: Equatable, Sendable {
    let role: String
    let entryId: String?
    let idempotencyKey: String?
}

enum ChatMessageGatewayIdentityBinder {
    static func applying(
        _ messages: [ChatMessage],
        history: [ChatGatewayMessageIdentity]
    ) -> [ChatMessage] {
        guard !history.isEmpty else { return messages }
        return messages.map { apply($0, history: history) }
    }

    private static func apply(
        _ message: ChatMessage,
        history: [ChatGatewayMessageIdentity]
    ) -> ChatMessage {
        guard message.gatewayEntryId == nil || message.idempotencyKey == nil else {
            return message
        }
        guard let match = match(message, in: history) else { return message }
        return message.withGatewayIdentity(
            gatewayEntryId: match.entryId,
            idempotencyKey: clientIdempotencyKey(match.idempotencyKey)
        )
    }

    private static func match(
        _ message: ChatMessage,
        in history: [ChatGatewayMessageIdentity]
    ) -> ChatGatewayMessageIdentity? {
        guard let localKey = message.idempotencyKey else { return nil }
        let role = message.role == .user ? "user" : "assistant"
        if let direct = history.last(where: { $0.role == role && keysMatch($0.idempotencyKey, localKey) }) {
            return direct
        }
        guard message.role == .assistant,
              let userIndex = history.lastIndex(where: {
                  $0.role == "user" && keysMatch($0.idempotencyKey, localKey)
              }) else {
            return nil
        }
        return history[(userIndex + 1)...].first(where: { $0.role == "assistant" })
    }

    static func keysMatch(_ historyKey: String?, _ localKey: String) -> Bool {
        guard let historyKey, !historyKey.isEmpty else { return false }
        if historyKey == localKey { return true }
        if historyKey == "\(localKey):user" { return true }
        if localKey.hasSuffix(":user"), historyKey == String(localKey.dropLast(5)) {
            return true
        }
        if historyKey.hasSuffix(":user"), localKey == String(historyKey.dropLast(5)) {
            return true
        }
        return false
    }

    private static func clientIdempotencyKey(_ historyKey: String?) -> String? {
        guard let historyKey, !historyKey.isEmpty else { return nil }
        if historyKey.hasSuffix(":user") {
            let stem = String(historyKey.dropLast(5))
            return stem.isEmpty ? historyKey : stem
        }
        return historyKey
    }
}
