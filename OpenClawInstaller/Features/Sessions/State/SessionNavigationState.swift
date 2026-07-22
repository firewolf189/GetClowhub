import Foundation
import Combine

@MainActor
final class SessionNavigationState: ObservableObject {
    @Published var sessionsByAgent: [String: [ChatSessionMetadata]] = [:]
    @Published var pinnedSessions: [ChatSessionMetadata] = []
    @Published var projectBindingsByAgent: [String: [AgentProjectBinding]] = [:]
    @Published var projectSessionsByAgent: [String: [ProjectSessionGroup]] = [:]
    @Published var generalSessionsByAgent: [String: [ChatSessionMetadata]] = [:]
    @Published var projectsById: [String: ProjectRecord] = [:]
    @Published var selectedSessionIdByAgent: [String: UUID] = [:]
    @Published var selectedAgentId: String = "main"
    /// Sessions whose latest run finished while the user was NOT viewing them.
    /// The sidebar shows a solid (non-pulsing) dot until the session is opened.
    @Published var unreadSessionIds: Set<UUID> = []
    @Published var availableAgents: [AgentOption] = [
        AgentOption(id: "main", name: "main", emoji: "", description: "", model: "", division: "")
    ]
}
