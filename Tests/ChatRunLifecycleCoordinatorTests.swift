import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): message
        }
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure.assertion(message) }
}

@main
private enum ChatRunLifecycleCoordinatorTests {
    @MainActor
    static func main() async throws {
        let coordinator = ChatRunLifecycleCoordinator()
        let first = UUID()
        var fired = false

        coordinator.scheduleAutomaticBackground(
            messageId: first,
            deadline: Date().addingTimeInterval(0.02)
        ) {
            fired = true
        }
        try await Task.sleep(nanoseconds: 80_000_000)
        try expect(fired, "the deadline must survive independently of a SwiftUI row lifecycle")

        let cancelled = UUID()
        var cancelledFired = false
        coordinator.scheduleAutomaticBackground(
            messageId: cancelled,
            deadline: Date().addingTimeInterval(0.05)
        ) {
            cancelledFired = true
        }
        coordinator.finish(messageId: cancelled)
        try await Task.sleep(nanoseconds: 80_000_000)
        try expect(!cancelledFired, "finishing a run must cancel its pending deadline")

        let recovery = UUID()
        var recoveryGeneration = 0
        coordinator.scheduleReconciliation(messageId: recovery) {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if !Task.isCancelled { recoveryGeneration = 1 }
        }
        coordinator.scheduleReconciliation(messageId: recovery) {
            recoveryGeneration = 2
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        try expect(recoveryGeneration == 2, "a newer reconciliation task must replace the stale generation")

        let hardDeadline = UUID()
        var hardDeadlineFired = false
        coordinator.scheduleHardDeadline(
            messageId: hardDeadline,
            deadline: Date().addingTimeInterval(0.02)
        ) {
            hardDeadlineFired = true
        }
        try await Task.sleep(nanoseconds: 80_000_000)
        try expect(hardDeadlineFired, "a background hard deadline must be owned outside the SwiftUI row")

        print("PASS: chat run lifecycle coordinator")
    }
}
