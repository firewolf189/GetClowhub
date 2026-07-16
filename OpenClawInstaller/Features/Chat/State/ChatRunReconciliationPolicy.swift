import Foundation

enum ChatRunReconciliationDirective: Equatable, Sendable {
    case retry(after: TimeInterval)
    case poll(after: TimeInterval)
    case suspend(attempts: Int)
}

/// Stateful retry policy for one gateway run. Transport recovery has its own
/// five-attempt policy; this cursor governs the independent run-status/history
/// reconciliation that follows a successful transport reconnect.
struct ChatRunReconciliationCursor: Sendable {
    private static let maximumUnavailableAttempts = 5
    private static let activeRunPollInterval: TimeInterval = 15

    private var unavailableObservationCount = 0
    private var completedReplyUnavailableCount = 0

    mutating func recordUnavailableObservation() -> ChatRunReconciliationDirective {
        unavailableObservationCount += 1
        return retryOrSuspend(for: unavailableObservationCount)
    }

    mutating func recordAuthoritativeObservation() {
        unavailableObservationCount = 0
    }

    func pollActiveRun() -> ChatRunReconciliationDirective {
        .poll(after: Self.activeRunPollInterval)
    }

    mutating func recordCompletedReplyUnavailable() -> ChatRunReconciliationDirective {
        completedReplyUnavailableCount += 1
        return retryOrSuspend(for: completedReplyUnavailableCount)
    }

    private func retryOrSuspend(for attempt: Int) -> ChatRunReconciliationDirective {
        guard attempt < Self.maximumUnavailableAttempts else {
            return .suspend(attempts: attempt)
        }
        let delay = TimeInterval(1 << max(0, attempt - 1))
        return .retry(after: delay)
    }
}

enum ChatRunDeliveryPolicy {
    /// The first send plus at most two retries with the same idempotency key.
    /// A retry is legal only while no run event has proved backend acceptance.
    static let maximumSubmissionAttempts = 3

    /// Bounds only the transport-delivery uncertainty phase. It is not a model
    /// execution deadline and therefore does not limit a confirmed foreground run.
    static let unregisteredRunGracePeriod: TimeInterval = 60
}

enum ChatRunLifetimePolicy {
    static let backgroundHardLimit: TimeInterval = 60 * 60
}
