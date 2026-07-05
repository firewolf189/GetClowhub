//
//  DashboardModels.swift
//  Data models extracted verbatim from DashboardViewModel.swift.
//  P1 refactor: file split only, no behavior change.
//

import Foundation

// MARK: - Channel Info Model

struct ChannelInfo: Identifiable {
    let id = UUID()
    let name: String
    let account: String
    let enabled: Bool
    let configured: Bool
    let linked: Bool
    let error: String?
    let statusTags: [String]
}

// MARK: - Model Info

struct ModelOverview: Equatable {
    var defaultModel: String = "-"
    var imageModel: String?
    var fallbacks: String = ""
    var imageFallbacks: String = ""
    var aliases: String = ""
}

struct ModelInfo: Identifiable, Equatable {
    let id = UUID()
    let modelId: String
    let input: String
    let contextLength: String
    let local: Bool
    let authenticated: Bool
    var isDefault: Bool
    let supportsImage: Bool
    let tags: String
}

// MARK: - Chat Message

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: ChatRole
    let content: String
    let agentId: String?
    let agentEmoji: String?
    let attachments: [URL]
    let taskStatus: TaskStatus
    let scrollTargetId: UUID?  // For notification messages: ID of the message to scroll to
    /// When the message was created. Optional so sessions persisted before
    /// this field existed still decode cleanly — pre-existing messages
    /// show no timestamp instead of an inaccurate "now".
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

    enum ChatRole: String, Codable {
        case user
        case assistant
    }

    enum TaskStatus: String, Codable {
        case loading      // Foreground: waiting for result
        case background   // Moved to background, still running
        case completed    // Done
        case timedOut     // Timed out, process terminated
        case cancelled    // Cancelled by user

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

struct ChatActivityEvent: Identifiable, Codable, Equatable {
    let id: String
    let kind: Kind
    let count: Int
    let detail: String?
    let details: [String]

    init(kind: Kind, count: Int, detail: String?, ordinal: Int) {
        self.init(kind: kind, count: count, details: detail.map { [$0] } ?? [], ordinal: ordinal)
    }

    init(kind: Kind, count: Int, details: [String], ordinal: Int) {
        self.kind = kind
        self.count = max(1, count)
        self.details = details
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.detail = self.details.first
        self.id = "\(kind.rawValue)-\(self.count)-\(self.details.joined(separator: "|"))-\(ordinal)"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case count
        case detail
        case details
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        count = max(1, try container.decodeIfPresent(Int.self, forKey: .count) ?? 1)
        let decodedDetail = try container.decodeIfPresent(String.self, forKey: .detail)
        let decodedDetails = try container.decodeIfPresent([String].self, forKey: .details)
        details = (decodedDetails ?? decodedDetail.map { [$0] } ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        detail = details.first ?? decodedDetail
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? "\(kind.rawValue)-\(count)-\(details.joined(separator: "|"))"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(count, forKey: .count)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encode(details, forKey: .details)
    }

    enum Kind: String, Codable {
        case loadedTools
        case searchedCode
        case readFiles
        case ranCommands
        case editedFiles
        case createdFiles
        case selectedModel
        case agentUsed
        case agentRecruited
        case toolFailed
        case progressUpdate

        init(gatewayKind: GatewayActivityEvent.Kind) {
            switch gatewayKind {
            case .loadedTools:
                self = .loadedTools
            case .searchedCode:
                self = .searchedCode
            case .readFiles:
                self = .readFiles
            case .ranCommands:
                self = .ranCommands
            case .editedFiles:
                self = .editedFiles
            case .createdFiles:
                self = .createdFiles
            case .selectedModel:
                self = .selectedModel
            case .agentUsed:
                self = .agentUsed
            case .agentRecruited:
                self = .agentRecruited
            case .toolFailed:
                self = .toolFailed
            }
        }

        func title(count: Int) -> String {
            switch self {
            case .loadedTools:
                return "Loaded \(count) \(count == 1 ? "tool" : "tools")"
            case .searchedCode:
                return "Searched code"
            case .readFiles:
                return "Read \(count) \(count == 1 ? "file" : "files")"
            case .ranCommands:
                return "Ran \(count) \(count == 1 ? "command" : "commands")"
            case .editedFiles:
                return count == 1 ? "Edited a file" : "Edited \(count) files"
            case .createdFiles:
                return "Created \(count) \(count == 1 ? "file" : "files")"
            case .selectedModel:
                return "Selected model"
            case .agentUsed:
                return "Used \(count) \(count == 1 ? "agent" : "agents")"
            case .agentRecruited:
                return "Recruited \(count) \(count == 1 ? "agent" : "agents")"
            case .toolFailed:
                return count == 1 ? "Tool failed" : "\(count) tools failed"
            case .progressUpdate:
                return "Progress update"
            }
        }

        var systemImage: String {
            switch self {
            case .loadedTools: return "wrench.and.screwdriver"
            case .searchedCode: return "magnifyingglass"
            case .readFiles: return "doc.text"
            case .ranCommands: return "terminal"
            case .editedFiles: return "pencil"
            case .createdFiles: return "doc.badge.plus"
            case .selectedModel: return "cpu"
            case .agentUsed: return "person.2"
            case .agentRecruited: return "person.crop.circle.badge.plus"
            case .toolFailed: return "exclamationmark.triangle"
            case .progressUpdate: return "text.alignleft"
            }
        }
    }
}

// MARK: - Skill Info

enum SkillStatus: String {
    case ready = "ready"
    case missing = "missing"
}

struct SkillsSummary {
    var ready: Int = 0
    var total: Int = 0
}

struct SkillInfo: Identifiable {
    let id = UUID()
    let name: String
    let status: SkillStatus
    let description: String
    let source: String
}

struct ProviderModelGroup: Identifiable {
    let providerKey: String
    let displayName: String
    let models: [ModelOption]

    var id: String { providerKey }
}

struct SkillDetailInfo: Identifiable {
    let id = UUID()
    let name: String
    let status: String
    let isReady: Bool
    let description: String
    let source: String
    let path: String
    let requirements: [String]
}

// MARK: - Agent Option

struct AgentOption: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let description: String
    let model: String
    let division: String
}

// MARK: - Cron Job Info

struct CronJobInfo: Identifiable {
    let id = UUID()
    let cronId: String
    let name: String
    let schedule: String
    let timezone: String
    let agentId: String
    let sessionTarget: String
    let message: String
    let enabled: Bool
    let nextRun: String
    let lastRun: String
    let status: String
    let model: String
}

// MARK: - Agent Session Info (Status Tab Monitoring)

struct AgentSessionInfo: Identifiable {
    let id = UUID()
    let agentId: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int
    let lastActiveAt: Date?
    let sessionCount: Int
}

struct SessionsSummary {
    let agents: [AgentSessionInfo]
    let totalInput: Int
    let totalOutput: Int
    let totalTokens: Int
    let totalSessions: Int
}
