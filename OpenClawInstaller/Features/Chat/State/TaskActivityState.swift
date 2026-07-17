import Foundation
import Combine

@MainActor
final class TaskActivityState: ObservableObject {
    @Published var isSendingMessage = false
    @Published private(set) var runsByMessageId: [UUID: ChatRunState] = [:]

    var foregroundTaskIds: Set<UUID> {
        Set(activeRuns(in: .foreground).map(\.identity.messageId))
    }

    var backgroundTaskIds: Set<UUID> {
        Set(activeRuns(in: .background).map(\.identity.messageId))
    }

    var inflightSessionIds: Set<UUID> {
        Set(activeRuns().map(\.identity.sessionId))
    }

    func registerRun(_ run: ChatRunState) {
        let messageId = run.identity.messageId
        precondition(runsByMessageId[messageId] == nil, "A chat message can own only one run state")
        runsByMessageId[messageId] = run
    }

    func bindGatewayRun(messageId: UUID, runId: String) {
        applyRunEvent(messageId: messageId, event: .sendAcknowledged(runId: runId))
    }

    func prepareGatewayRun(
        messageId: UUID,
        sessionKey: String,
        idempotencyKey: String,
        startedAt: Date = Date()
    ) {
        applyRunEvent(
            messageId: messageId,
            event: .gatewayRunPrepared(
                binding: ChatGatewayRunBinding(
                    sessionKey: sessionKey,
                    idempotencyKey: idempotencyKey,
                    startedAt: startedAt
                )
            )
        )
    }

    func applyRunEvent(messageId: UUID, event: ChatRunEvent) {
        guard let current = runsByMessageId[messageId] else { return }
        let updated = current.applying(event)
        guard updated != current else { return }
        runsByMessageId[messageId] = updated
    }

    /// Applies one shared transport transition with a single publication so a
    /// gateway reconnect does not invalidate the chat tree once per active row.
    func applyRunEventToActiveRuns(_ event: ChatRunEvent) {
        var updatedRuns = runsByMessageId
        var changed = false

        for (messageId, run) in runsByMessageId where !run.phase.isTerminal {
            let updated = run.applying(event)
            guard updated != run else { continue }
            updatedRuns[messageId] = updated
            changed = true
        }

        if changed {
            runsByMessageId = updatedRuns
        }
    }

    /// Move every transport-lost run back into the connecting phase with one
    /// published registry replacement. One retry command represents one
    /// shared gateway connection, not one reconnect attempt per chat row.
    @discardableResult
    func requestTransportRecoveryRetry() -> Int {
        var updatedRuns = runsByMessageId
        var transitionedCount = 0

        for (messageId, run) in runsByMessageId {
            guard case .connectionLost = run.phase else { continue }
            updatedRuns[messageId] = run.applying(.retryRequested)
            transitionedCount += 1
        }

        guard transitionedCount > 0 else { return 0 }
        runsByMessageId = updatedRuns
        return transitionedCount
    }

    /// A reconciliation retry operates on one run while the shared WebSocket
    /// is already healthy. It must not reconnect every other chat task.
    @discardableResult
    func requestRunReconciliationRetry(messageId: UUID) -> Bool {
        guard let run = runsByMessageId[messageId],
              case .recoveryUnavailable = run.phase else {
            return false
        }
        runsByMessageId[messageId] = run.applying(.retryRequested)
        return true
    }

    func moveRunToBackground(messageId: UUID) {
        applyRunEvent(messageId: messageId, event: .movedToBackground)
    }

    @discardableResult
    func removeRun(messageId: UUID) -> ChatRunState? {
        runsByMessageId.removeValue(forKey: messageId)
    }

    func run(for messageId: UUID) -> ChatRunState? {
        runsByMessageId[messageId]
    }

    func foregroundTaskId(inSession sessionId: UUID) -> UUID? {
        activeRuns(in: .foreground)
            .first(where: { $0.identity.sessionId == sessionId })?
            .identity.messageId
    }

    func hasForegroundTask(inSession sessionId: UUID) -> Bool {
        activeRuns(in: .foreground).contains { $0.identity.sessionId == sessionId }
    }

    func hasForegroundTask(forAgent agentId: String) -> Bool {
        activeRuns(in: .foreground).contains { $0.identity.agentId == agentId }
    }

    func hasInflightTask(inSession sessionId: UUID) -> Bool {
        activeRuns().contains { $0.identity.sessionId == sessionId }
    }

    func runIds(inSession sessionId: UUID) -> Set<UUID> {
        Set(activeRuns()
            .filter { $0.identity.sessionId == sessionId }
            .map(\.identity.messageId))
    }

    private func activeRuns(in placement: ChatRunPlacement? = nil) -> [ChatRunState] {
        runsByMessageId.values.filter { run in
            !run.phase.isTerminal && (placement == nil || run.placement == placement)
        }
    }
}
