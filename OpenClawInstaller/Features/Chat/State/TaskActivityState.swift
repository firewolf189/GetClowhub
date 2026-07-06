import Foundation
import Combine

@MainActor
final class TaskActivityState: ObservableObject {
    @Published var isSendingMessage = false
    @Published var foregroundTaskIds: Set<UUID> = []
    @Published var backgroundTaskIds: Set<UUID> = []

    var taskAgentMap: [UUID: String] = [:]
    var taskSessionMap: [UUID: UUID] = [:]

    var inflightSessionIds: Set<UUID> {
        Set((foregroundTaskIds.union(backgroundTaskIds)).compactMap { taskSessionMap[$0] })
    }

    func foregroundTaskId(inSession sessionId: UUID) -> UUID? {
        foregroundTaskIds.first { taskSessionMap[$0] == sessionId }
    }

    func hasForegroundTask(inSession sessionId: UUID) -> Bool {
        foregroundTaskIds.contains { taskSessionMap[$0] == sessionId }
    }

    func hasInflightTask(inSession sessionId: UUID) -> Bool {
        hasForegroundTask(inSession: sessionId)
            || backgroundTaskIds.contains { taskSessionMap[$0] == sessionId }
    }
}
