import Foundation

enum GatewayChatAbortResult: Equatable, Sendable {
    case confirmed(runIds: [String])
    case notRunning
    case rejected(message: String?)
    case transportUnavailable

    var isConfirmed: Bool {
        if case .confirmed = self { return true }
        return false
    }
}

struct GatewayChatAbortResponse: Equatable, Sendable {
    let aborted: Bool
    let runIds: [String]

    func result(expectedRunId: String?) -> GatewayChatAbortResult {
        guard aborted else { return .notRunning }
        guard let expectedRunId else { return .confirmed(runIds: runIds) }
        guard runIds.contains(expectedRunId) else { return .notRunning }
        return .confirmed(runIds: runIds)
    }
}

/// Routes each `chat.abort` response back to the exact request and validates
/// the gateway's semantic result. A successful RPC envelope is not sufficient:
/// cancellation is confirmed only when `aborted=true` and the requested run id
/// is present in `runIds`.
nonisolated final class GatewayChatAbortRequestRegistry: @unchecked Sendable {
    private struct PendingRequest {
        let expectedRunId: String?
        let continuation: CheckedContinuation<GatewayChatAbortResult, Never>
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
        expectedRunId: String?,
        continuation: CheckedContinuation<GatewayChatAbortResult, Never>
    ) {
        lock.lock()
        let replaced = requests.updateValue(
            PendingRequest(expectedRunId: expectedRunId, continuation: continuation),
            forKey: requestId
        )
        lock.unlock()
        replaced?.continuation.resume(returning: .transportUnavailable)
    }

    @discardableResult
    func resolve(
        requestId: String,
        response: GatewayChatAbortResponse?,
        rejectionMessage: String?
    ) -> Bool {
        guard let pending = take(requestId: requestId) else { return false }

        let result: GatewayChatAbortResult
        if let rejectionMessage {
            result = .rejected(message: rejectionMessage)
        } else if let response {
            result = response.result(expectedRunId: pending.expectedRunId)
        } else {
            result = .rejected(message: "Malformed chat.abort response")
        }
        pending.continuation.resume(returning: result)
        return true
    }

    @discardableResult
    func cancel(requestId: String) -> Bool {
        guard let pending = take(requestId: requestId) else { return false }
        pending.continuation.resume(returning: .transportUnavailable)
        return true
    }

    private func take(requestId: String) -> PendingRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests.removeValue(forKey: requestId)
    }
}
