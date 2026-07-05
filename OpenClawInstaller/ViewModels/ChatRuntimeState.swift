import Foundation
import Combine

@MainActor
final class ChatRuntimeState: ObservableObject {
    @Published var chatMessagesByAgent: [String: [ChatMessage]] = [:]
    @Published var chatMessagesByInactiveSession: [UUID: [ChatMessage]] = [:]
    @Published var loadingSessionIds: Set<UUID> = []

    func chatMessages(for agentId: String) -> [ChatMessage] {
        chatMessagesByAgent[agentId] ?? []
    }

    func setChatMessages(_ messages: [ChatMessage], for agentId: String) {
        chatMessagesByAgent[agentId] = messages
    }
}
