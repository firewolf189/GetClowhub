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
        activityEvents: [ChatActivityEvent] = []
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
            activityEvents: activityEvents
        )
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
