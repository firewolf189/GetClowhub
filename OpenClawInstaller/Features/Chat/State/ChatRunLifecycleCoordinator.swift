import Foundation

/// Owns cancellable per-run side work that must outlive SwiftUI row creation.
/// The run registry remains the source of truth; this coordinator only scopes
/// deadlines and asynchronous recovery/cancellation operations by message id.
@MainActor
final class ChatRunLifecycleCoordinator {
    private struct Operation {
        let token: UUID
        let task: Task<Void, Never>
    }

    private var automaticBackgroundOperations: [UUID: Operation] = [:]
    private var hardDeadlineOperations: [UUID: Operation] = [:]
    private var reconciliationOperations: [UUID: Operation] = [:]
    private var cancellationOperations: [UUID: Operation] = [:]

    func scheduleAutomaticBackground(
        messageId: UUID,
        deadline: Date?,
        action: @escaping @MainActor () -> Void
    ) {
        cancelAutomaticBackground(messageId: messageId)
        guard let deadline else { return }

        let token = UUID()
        let task = Task { [weak self] in
            let remaining = deadline.timeIntervalSinceNow
            if remaining > 0 {
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(remaining * 1_000_000_000)
                    )
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            action()
            self?.removeAutomaticBackgroundOperation(messageId: messageId, token: token)
        }
        automaticBackgroundOperations[messageId] = Operation(token: token, task: task)
    }

    func scheduleHardDeadline(
        messageId: UUID,
        deadline: Date,
        action: @escaping @MainActor () async -> Void
    ) {
        hardDeadlineOperations.removeValue(forKey: messageId)?.task.cancel()

        let token = UUID()
        let task = Task { [weak self] in
            let remaining = deadline.timeIntervalSinceNow
            if remaining > 0 {
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(remaining * 1_000_000_000)
                    )
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            await action()
            self?.removeHardDeadlineOperation(messageId: messageId, token: token)
        }
        hardDeadlineOperations[messageId] = Operation(token: token, task: task)
    }

    func scheduleReconciliation(
        messageId: UUID,
        operation: @escaping @MainActor () async -> Void
    ) {
        reconciliationOperations[messageId]?.task.cancel()
        let token = UUID()
        let task = Task { [weak self] in
            await operation()
            guard !Task.isCancelled, let self else { return }
            self.removeReconciliationOperation(messageId: messageId, token: token)
        }
        reconciliationOperations[messageId] = Operation(token: token, task: task)
    }

    func scheduleCancellation(
        messageId: UUID,
        operation: @escaping @MainActor () async -> Void
    ) {
        cancellationOperations[messageId]?.task.cancel()
        let token = UUID()
        let task = Task { [weak self] in
            await operation()
            guard !Task.isCancelled, let self else { return }
            self.removeCancellationOperation(messageId: messageId, token: token)
        }
        cancellationOperations[messageId] = Operation(token: token, task: task)
    }

    func cancelAutomaticBackground(messageId: UUID) {
        automaticBackgroundOperations.removeValue(forKey: messageId)?.task.cancel()
    }

    func cancelReconciliation(messageId: UUID) {
        reconciliationOperations.removeValue(forKey: messageId)?.task.cancel()
    }

    func cancelHardDeadline(messageId: UUID) {
        hardDeadlineOperations.removeValue(forKey: messageId)?.task.cancel()
    }

    func finish(messageId: UUID) {
        automaticBackgroundOperations.removeValue(forKey: messageId)?.task.cancel()
        hardDeadlineOperations.removeValue(forKey: messageId)?.task.cancel()
        reconciliationOperations.removeValue(forKey: messageId)?.task.cancel()
        cancellationOperations.removeValue(forKey: messageId)?.task.cancel()
    }

    private func removeAutomaticBackgroundOperation(messageId: UUID, token: UUID) {
        guard automaticBackgroundOperations[messageId]?.token == token else { return }
        automaticBackgroundOperations.removeValue(forKey: messageId)
    }

    private func removeReconciliationOperation(messageId: UUID, token: UUID) {
        guard reconciliationOperations[messageId]?.token == token else { return }
        reconciliationOperations.removeValue(forKey: messageId)
    }

    private func removeHardDeadlineOperation(messageId: UUID, token: UUID) {
        guard hardDeadlineOperations[messageId]?.token == token else { return }
        hardDeadlineOperations.removeValue(forKey: messageId)
    }

    private func removeCancellationOperation(messageId: UUID, token: UUID) {
        guard cancellationOperations[messageId]?.token == token else { return }
        cancellationOperations.removeValue(forKey: messageId)
    }
}
