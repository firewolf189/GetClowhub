import Foundation

// MARK: - Collab Phase

enum CollabPhase: String, Equatable, Codable {
    case clarifying        // Commander 和用户对话收集需求
    case researching       // 调研阶段：派 agent 调研代码库/架构（P1-2）
    case decomposing       // Commander 正在拆分
    case awaitingApproval  // 拆分完成，等用户确认
    case executing         // 子任务执行中
    case verifying         // 自动验证阶段（P1-3）
    case summarizing       // 汇总中
    case completed         // 完成
}

// MARK: - Collab Task Status

enum CollabTaskStatus: Equatable, Codable {
    case pending
    case inProgress
    case completed
    case failed(String)
    case skipped

    static func == (lhs: CollabTaskStatus, rhs: CollabTaskStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending),
             (.inProgress, .inProgress),
             (.completed, .completed),
             (.skipped, .skipped):
            return true
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }

    // Custom Codable for associated value
    enum CodingKeys: String, CodingKey {
        case type, reason
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pending: try container.encode("pending", forKey: .type)
        case .inProgress: try container.encode("inProgress", forKey: .type)
        case .completed: try container.encode("completed", forKey: .type)
        case .skipped: try container.encode("skipped", forKey: .type)
        case .failed(let reason):
            try container.encode("failed", forKey: .type)
            try container.encode(reason, forKey: .reason)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "pending": self = .pending
        case "inProgress": self = .inProgress
        case "completed": self = .completed
        case "skipped": self = .skipped
        case "failed":
            let reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? "Unknown"
            self = .failed(reason)
        default: self = .pending
        }
    }
}

// MARK: - Collab Sub Task

struct CollabSubTask: Identifiable, Codable {
    let id: Int
    let title: String
    var agentId: String? = nil
    var role: String? = nil
    let prompt: String
    let dependsOn: [Int]
    var needsRecruit: Bool = false  // true = agent from marketplace, needs auto-recruit before execution
    var affectedFiles: [String] = []  // P2-4: target file set for file-level concurrency control
    var status: CollabTaskStatus = .pending
    var result: String?
    var elapsedTime: TimeInterval?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        agentId = try c.decodeIfPresent(String.self, forKey: .agentId)
        role = try c.decodeIfPresent(String.self, forKey: .role)
        prompt = try c.decode(String.self, forKey: .prompt)
        dependsOn = try c.decode([Int].self, forKey: .dependsOn)
        needsRecruit = try c.decodeIfPresent(Bool.self, forKey: .needsRecruit) ?? false
        affectedFiles = try c.decodeIfPresent([String].self, forKey: .affectedFiles) ?? []
        status = try c.decodeIfPresent(CollabTaskStatus.self, forKey: .status) ?? .pending
        result = try c.decodeIfPresent(String.self, forKey: .result)
        elapsedTime = try c.decodeIfPresent(TimeInterval.self, forKey: .elapsedTime)
    }

    init(id: Int, title: String, agentId: String? = nil, role: String? = nil, prompt: String, dependsOn: [Int], needsRecruit: Bool = false, affectedFiles: [String] = [], status: CollabTaskStatus = .pending, result: String? = nil, elapsedTime: TimeInterval? = nil) {
        self.id = id
        self.title = title
        self.agentId = agentId
        self.role = role
        self.prompt = prompt
        self.dependsOn = dependsOn
        self.needsRecruit = needsRecruit
        self.affectedFiles = affectedFiles
        self.status = status
        self.result = result
        self.elapsedTime = elapsedTime
    }
}

// MARK: - Collab Session

struct CollabSession: Identifiable, Codable {
    let id: String
    let taskDescription: String
    var summary: String
    var subtasks: [CollabSubTask]
    var finalResult: String?
    var taskContext: String = ""  // Commander 总结的精炼任务上下文
    var clarifyDialogue: [ClarifyDialogueEntry] = []  // 需求对话记录
    let createdAt: Date
    var phase: CollabPhase = .clarifying  // persisted phase for history display

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        taskDescription = try c.decode(String.self, forKey: .taskDescription)
        summary = try c.decode(String.self, forKey: .summary)
        subtasks = try c.decodeIfPresent([CollabSubTask].self, forKey: .subtasks) ?? []
        finalResult = try c.decodeIfPresent(String.self, forKey: .finalResult)
        taskContext = try c.decodeIfPresent(String.self, forKey: .taskContext) ?? ""
        clarifyDialogue = try c.decodeIfPresent([ClarifyDialogueEntry].self, forKey: .clarifyDialogue) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        phase = try c.decodeIfPresent(CollabPhase.self, forKey: .phase) ?? .clarifying
    }

    init(id: String, taskDescription: String, summary: String, subtasks: [CollabSubTask], finalResult: String? = nil, taskContext: String = "", clarifyDialogue: [ClarifyDialogueEntry] = [], createdAt: Date, phase: CollabPhase = .clarifying) {
        self.id = id
        self.taskDescription = taskDescription
        self.summary = summary
        self.subtasks = subtasks
        self.finalResult = finalResult
        self.taskContext = taskContext
        self.clarifyDialogue = clarifyDialogue
        self.createdAt = createdAt
        self.phase = phase
    }
}

// MARK: - Clarify Dialogue Entry (for persistence)

struct ClarifyDialogueEntry: Identifiable, Codable {
    let id: Int
    let role: String   // "commander" or "user"
    let content: String
}

// MARK: - Commander Decompose Response

struct CommanderDecomposeResponse: Codable {
    let summary: String
    let tasks: [CommanderTask]
}

struct CommanderTask: Codable {
    let id: Int
    let title: String
    let agent: String?
    let role: String?
    let prompt: String
    let depends_on: [Int]
    let needs_recruit: Bool?  // true = marketplace agent, needs auto-recruit
    let affected_files: [String]?  // P2-4: target file set for concurrency control
}

// MARK: - Commander Action Response

struct CommanderActionResponse: Codable {
    let type: String           // "reply" or "action"
    let action: String?        // "skip", "retry", "cancel_all", "modify", "force_complete", "reassign"
    let taskId: Int?
    let newPrompt: String?
    let newAgentId: String?    // for "reassign" action
    let message: String
}

// MARK: - Commander Clarify Response

struct CommanderClarifyResponse: Codable {
    let ready: Bool
    let questions: String?   // When ready == false, Commander's questions
    let context: String?     // When ready == true, refined task context summary
}