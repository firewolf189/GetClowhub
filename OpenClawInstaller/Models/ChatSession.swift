import Foundation

/// One conversation thread for a given agent. Persisted as a single JSON file
/// under that agent workspace's `.sessions` directory.
struct ChatSession: Codable, Identifiable {
    let id: UUID
    let agentId: String
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]
    var isPinned: Bool
    var isArchived: Bool
    var projectId: String?
    var projectRoot: String?
    var projectDisplayName: String?

    init(
        id: UUID = UUID(),
        agentId: String,
        title: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [ChatMessage] = [],
        isPinned: Bool = false,
        isArchived: Bool = false,
        projectId: String? = nil,
        projectRoot: String? = nil,
        projectDisplayName: String? = nil
    ) {
        self.id = id
        self.agentId = agentId
        self.title = title ?? Self.defaultTitle
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.projectId = projectId
        self.projectRoot = projectRoot
        self.projectDisplayName = projectDisplayName
    }

    static let defaultTitle = "新会话"

    /// Build a title from the first user message in the thread, capped at `maxLength`.
    /// Falls back to `defaultTitle` when no usable user content exists.
    static func deriveTitle(from messages: [ChatMessage], maxLength: Int = 30) -> String {
        guard let firstUserText = messages.first(where: { $0.role == .user })?.content,
              !firstUserText.isEmpty else {
            return defaultTitle
        }
        let trimmed = firstUserText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return defaultTitle }
        if trimmed.count <= maxLength { return trimmed }
        return String(trimmed.prefix(maxLength)) + "…"
    }
}

/// Lightweight metadata stored in `index.json` so we don't have to read every
/// session file at launch. The full `ChatSession` is loaded lazily when the
/// user actually opens that thread.
struct ChatSessionMetadata: Codable, Identifiable, Equatable {
    let id: UUID
    let agentId: String
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messageCount: Int
    var isPinned: Bool
    var isArchived: Bool
    var projectId: String?
    var projectRoot: String?
    var projectDisplayName: String?

    init(from session: ChatSession) {
        self.id = session.id
        self.agentId = session.agentId
        self.title = session.title
        self.createdAt = session.createdAt
        self.updatedAt = session.updatedAt
        self.messageCount = session.messages.count
        self.isPinned = session.isPinned
        self.isArchived = session.isArchived
        self.projectId = session.projectId
        self.projectRoot = session.projectRoot
        self.projectDisplayName = session.projectDisplayName
    }
}

extension ChatSessionMetadata: ChatSessionSearchable {}
