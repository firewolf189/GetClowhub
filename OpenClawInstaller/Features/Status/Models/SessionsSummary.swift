import Foundation

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
