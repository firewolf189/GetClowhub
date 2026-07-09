import Foundation
import Combine

@MainActor
final class ChatRuntimeState: ObservableObject {
    @Published var chatMessagesByAgent: [String: [ChatMessage]] = [:]
    @Published var chatMessagesByInactiveSession: [UUID: [ChatMessage]] = [:]
    @Published var activeStreamStatesByMessageId: [UUID: ChatActiveStreamState] = [:]
    @Published var loadingSessionIds: Set<UUID> = []

    func chatMessages(for agentId: String) -> [ChatMessage] {
        chatMessagesByAgent[agentId] ?? []
    }

    func setChatMessages(_ messages: [ChatMessage], for agentId: String) {
        chatMessagesByAgent[agentId] = messages
    }

    func updateActiveStreamState(
        messageId: UUID,
        visibleDraftText: String,
        activityEvents: [ChatActivityEvent]
    ) {
        let next = ChatActiveStreamState(
            messageId: messageId,
            visibleDraftText: visibleDraftText,
            activityEvents: activityEvents
        )
        guard activeStreamStatesByMessageId[messageId] != next else { return }
        activeStreamStatesByMessageId[messageId] = next
    }

    func clearActiveStreamState(_ messageId: UUID) {
        activeStreamStatesByMessageId.removeValue(forKey: messageId)
    }
}
