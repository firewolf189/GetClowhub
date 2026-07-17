import Foundation

/// Lock-owned request router for `agent.wait`. It gives send callbacks,
/// response callbacks, and timeout callbacks one atomic consume operation, so
/// reverse-order and late responses cannot resume the wrong continuation or
/// resume one continuation twice.
nonisolated final class GatewayChatRunStatusRequestRegistry: @unchecked Sendable {
    private struct PendingRequest {
        let expectedRunId: String
        let continuation: CheckedContinuation<GatewayChatRunStatusSnapshot?, Never>
    }

    private let lock = NSLock()
    private var requests: [String: PendingRequest] = [:]

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count
    }

    func register(
        requestId: String,
        expectedRunId: String,
        continuation: CheckedContinuation<GatewayChatRunStatusSnapshot?, Never>
    ) {
        lock.lock()
        let replaced = requests.updateValue(
            PendingRequest(expectedRunId: expectedRunId, continuation: continuation),
            forKey: requestId
        )
        lock.unlock()
        replaced?.continuation.resume(returning: nil)
    }

    @discardableResult
    func resolve(
        requestId: String,
        responseRunId: String?,
        snapshot: GatewayChatRunStatusSnapshot?
    ) -> Bool {
        guard let pending = take(requestId: requestId) else { return false }
        let result = responseRunId == pending.expectedRunId ? snapshot : nil
        pending.continuation.resume(returning: result)
        return true
    }

    @discardableResult
    func cancel(requestId: String) -> Bool {
        guard let pending = take(requestId: requestId) else { return false }
        pending.continuation.resume(returning: nil)
        return true
    }

    private func take(requestId: String) -> PendingRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests.removeValue(forKey: requestId)
    }
}
