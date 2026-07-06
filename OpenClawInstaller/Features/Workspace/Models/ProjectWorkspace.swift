import Foundation

struct ProjectRecord: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var displayName: String
    var rootPath: String
    var createdAt: Date
    var lastOpenedAt: Date
    var lastIndexedAt: Date?
    var indexVersion: Int
    var indexStatus: ProjectIndexStatus

    init(
        id: String = UUID().uuidString,
        displayName: String,
        rootPath: String,
        createdAt: Date = Date(),
        lastOpenedAt: Date = Date(),
        lastIndexedAt: Date? = nil,
        indexVersion: Int = 1,
        indexStatus: ProjectIndexStatus = .notStarted
    ) {
        self.id = id
        self.displayName = displayName
        self.rootPath = rootPath
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.lastIndexedAt = lastIndexedAt
        self.indexVersion = indexVersion
        self.indexStatus = indexStatus
    }

    var sortKey: String {
        displayName.localizedLowercase
    }
}

enum ProjectIndexStatus: String, Codable, Equatable, Hashable {
    case notStarted
    case ready
    case unavailable
}

struct AgentProjectBinding: Codable, Identifiable, Equatable, Hashable {
    var agentId: String
    var projectId: String
    var isCollapsed: Bool
    var sortOrder: Int
    var lastOpenedAt: Date

    var id: String {
        "\(agentId)::\(projectId)"
    }

    init(
        agentId: String,
        projectId: String,
        isCollapsed: Bool = false,
        sortOrder: Int = 0,
        lastOpenedAt: Date = Date()
    ) {
        self.agentId = agentId
        self.projectId = projectId
        self.isCollapsed = isCollapsed
        self.sortOrder = sortOrder
        self.lastOpenedAt = lastOpenedAt
    }
}

struct ProjectSessionGroup: Identifiable, Equatable {
    let project: ProjectRecord
    var binding: AgentProjectBinding
    var sessions: [ChatSessionMetadata]

    var id: String {
        binding.id
    }
}
