import Foundation

/// Maps a cron job onto a Mac chat session using the same
/// `session:agent:<id>:<uuid>` target Windows managed cron writes.
enum CronConversationBinding {
    static func dedicatedTarget(agentId: String, sessionId: UUID) -> String {
        let agent = agentId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "session:agent:\(agent.isEmpty ? "main" : agent):\(sessionId.uuidString.lowercased())"
    }

    static func parse(_ target: String) -> (agentId: String, sessionId: UUID)? {
        let raw = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw != "isolated", raw != "main", raw != "current" else {
            return nil
        }
        let body = raw.hasPrefix("session:") ? String(raw.dropFirst("session:".count)) : raw
        let parts = body.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, parts[0].lowercased() == "agent",
              let uuid = UUID(uuidString: parts[parts.count - 1]) else {
            return nil
        }
        let agentId = parts.dropFirst().dropLast().joined(separator: ":")
        return (agentId.isEmpty ? "main" : agentId, uuid)
    }
}

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
