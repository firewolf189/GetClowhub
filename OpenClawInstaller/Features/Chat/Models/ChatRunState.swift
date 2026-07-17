import Foundation

struct ChatRunIdentity: Codable, Equatable, Sendable {
    let messageId: UUID
    let agentId: String
    let sessionId: UUID

    init(
        messageId: UUID,
        agentId: String,
        sessionId: UUID
    ) {
        self.messageId = messageId
        self.agentId = agentId
        self.sessionId = sessionId
    }
}

/// The gateway-side run currently executing for a visible chat task. Most
/// tasks have one binding for their whole lifetime. Orchestrated tasks may
/// replace it between child runs without changing UI session ownership.
struct ChatGatewayRunBinding: Codable, Equatable, Sendable {
    let sessionKey: String
    let idempotencyKey: String
    let startedAt: Date
    let runId: String?

    init(
        sessionKey: String,
        idempotencyKey: String = UUID().uuidString,
        startedAt: Date = Date(),
        runId: String? = nil
    ) {
        self.sessionKey = sessionKey
        self.idempotencyKey = idempotencyKey
        self.startedAt = startedAt
        self.runId = runId
    }

    func acknowledging(runId: String) -> ChatGatewayRunBinding {
        ChatGatewayRunBinding(
            sessionKey: sessionKey,
            idempotencyKey: idempotencyKey,
            startedAt: startedAt,
            runId: runId
        )
    }
}

enum ChatRunPlacement: String, Codable, Equatable, Sendable {
    case foreground
    case background
}

/// Identifies who owns terminalization after a gateway run is reconciled.
/// Conversation runs complete the visible message directly. An orchestrated
/// image-review child returns its result to the batch, which decides whether
/// to launch the next child or finish the parent message.
enum ChatRunExecutionKind: String, Codable, Equatable, Sendable {
    case conversation
    case localImageReviewBatch
}

enum ChatRunPhase: Codable, Equatable, Sendable {
    case preparing
    case sending
    case connecting
    case waitingForResponse
    case streaming
    case reconnecting(attempt: Int, maxAttempts: Int)
    case reconciling
    case recoveryUnavailable(attempts: Int)
    case connectionLost(attempts: Int)
    case completed
    case failed
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .preparing, .sending, .connecting, .waitingForResponse, .streaming,
             .reconnecting, .reconciling, .recoveryUnavailable, .connectionLost:
            return false
        }
    }
}

/// Immutable row input derived from the run registry. Cancellation is an
/// intent orthogonal to transport/run phase: requesting an abort must not
/// pretend the gateway has already confirmed a terminal outcome.
struct ChatRunPresentationState: Equatable, Sendable {
    let phase: ChatRunPhase
    let cancellationRequested: Bool

    var isRetryable: Bool {
        switch phase {
        case .connectionLost, .recoveryUnavailable:
            return true
        default:
            return false
        }
    }
}

enum ChatRunEvent: Equatable, Sendable {
    case gatewayRunPrepared(binding: ChatGatewayRunBinding)
    case sendStarted
    case sendAcknowledged(runId: String)
    case sendDeliveryUnconfirmed
    case receivedDelta
    case transportReconnecting(attempt: Int, maxAttempts: Int)
    case transportReconnected
    case recoveryResumed(hasBufferedText: Bool)
    case recoveryExhausted(attempts: Int)
    case reconciliationUnavailable(attempts: Int)
    case retryRequested
    case cancellationRequested
    case movedToBackground
    case completed
    case failed
    case cancelled
}

struct ChatRunState: Codable, Equatable, Sendable {
    let identity: ChatRunIdentity
    let startedAt: Date
    let executionKind: ChatRunExecutionKind
    private(set) var gatewayBinding: ChatGatewayRunBinding
    private(set) var placement: ChatRunPlacement
    private(set) var phase: ChatRunPhase
    private(set) var cancellationRequested: Bool

    init(
        identity: ChatRunIdentity,
        gatewayBinding: ChatGatewayRunBinding,
        startedAt: Date,
        executionKind: ChatRunExecutionKind = .conversation,
        placement: ChatRunPlacement = .foreground,
        phase: ChatRunPhase = .preparing,
        cancellationRequested: Bool = false
    ) {
        self.identity = identity
        self.gatewayBinding = gatewayBinding
        self.startedAt = startedAt
        self.executionKind = executionKind
        self.placement = placement
        self.phase = phase
        self.cancellationRequested = cancellationRequested
    }

    var runId: String? {
        gatewayBinding.runId
    }

    var expectedRunId: String {
        gatewayBinding.runId ?? gatewayBinding.idempotencyKey
    }

    var presentationState: ChatRunPresentationState {
        ChatRunPresentationState(
            phase: phase,
            cancellationRequested: cancellationRequested
        )
    }

    /// A recoverable run remains registered after transport/reconciliation
    /// exhaustion, but no local work is active until the user retries.
    var keepsProcessActive: Bool {
        switch phase {
        case .preparing, .sending, .connecting, .waitingForResponse, .streaming,
             .reconnecting, .reconciling:
            return true
        case .recoveryUnavailable, .connectionLost, .completed, .failed, .cancelled:
            return false
        }
    }

    func applying(_ event: ChatRunEvent) -> ChatRunState {
        var next = self
        guard !next.phase.isTerminal else { return next }

        switch event {
        case .gatewayRunPrepared(let binding):
            next.gatewayBinding = binding
            next.phase = .preparing
        case .sendStarted:
            next.phase = .sending
        case .sendAcknowledged(let runId):
            next.gatewayBinding = next.gatewayBinding.acknowledging(runId: runId)
            next.phase = .waitingForResponse
        case .sendDeliveryUnconfirmed:
            next.phase = .waitingForResponse
        case .receivedDelta:
            next.phase = .streaming
        case .transportReconnecting(let attempt, let maxAttempts):
            next.phase = .reconnecting(attempt: attempt, maxAttempts: maxAttempts)
        case .transportReconnected:
            next.phase = .reconciling
        case .recoveryResumed(let hasBufferedText):
            next.phase = hasBufferedText ? .streaming : .waitingForResponse
        case .recoveryExhausted(let attempts):
            next.phase = .connectionLost(attempts: attempts)
        case .reconciliationUnavailable(let attempts):
            next.phase = .recoveryUnavailable(attempts: attempts)
        case .retryRequested:
            if case .recoveryUnavailable = next.phase {
                next.phase = .reconciling
            } else {
                next.phase = .connecting
            }
        case .cancellationRequested:
            next.cancellationRequested = true
        case .movedToBackground:
            next.placement = .background
        case .completed:
            next.phase = .completed
        case .failed:
            next.phase = .failed
        case .cancelled:
            next.phase = .cancelled
        }

        return next
    }
}
