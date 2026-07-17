import Foundation

enum GatewayChatRunState: String, Codable, Equatable, Sendable {
    case running
    case completed
    case failed
    case cancelled
    case unknown
}

struct GatewayChatRunStatusSnapshot: Codable, Equatable, Sendable {
    let runId: String
    let state: GatewayChatRunState
    let startedAt: Date?
    let endedAt: Date?
    let errorMessage: String?
    let stopReason: String?
    let timeoutPhase: String?
    let livenessState: String?
    let providerStarted: Bool?
    let yielded: Bool
    let pendingError: Bool
    let aborted: Bool

    /// OpenClaw uses this exact wait-only shape when no active run or terminal
    /// dedupe record exists for the requested id. It is meaningful only for a
    /// locally unacknowledged submission; acknowledged runs remain recoverable.
    var indicatesNoRegisteredRun: Bool {
        state == .running
            && timeoutPhase?.lowercased() == "queue"
            && providerStarted == false
            && startedAt == nil
            && endedAt == nil
            && errorMessage == nil
            && stopReason == nil
            && livenessState == nil
            && !yielded
            && !pendingError
            && !aborted
    }

    init(
        runId: String,
        state: GatewayChatRunState,
        startedAt: Date?,
        endedAt: Date?,
        errorMessage: String?,
        stopReason: String?,
        timeoutPhase: String? = nil,
        livenessState: String? = nil,
        providerStarted: Bool? = nil,
        yielded: Bool = false,
        pendingError: Bool = false,
        aborted: Bool = false
    ) {
        self.runId = runId
        self.state = state
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.errorMessage = Self.nonEmpty(errorMessage)
        self.stopReason = Self.nonEmpty(stopReason)
        self.timeoutPhase = Self.nonEmpty(timeoutPhase)
        self.livenessState = Self.nonEmpty(livenessState)
        self.providerStarted = providerStarted
        self.yielded = yielded
        self.pendingError = pendingError
        self.aborted = aborted
    }

    init(
        runId: String,
        gatewayStatus: String?,
        startedAt: Date?,
        endedAt: Date?,
        errorMessage: String?,
        stopReason: String?,
        timeoutPhase: String? = nil,
        livenessState: String? = nil,
        providerStarted: Bool? = nil,
        yielded: Bool = false,
        pendingError: Bool = false,
        aborted: Bool = false
    ) {
        let normalizedError = Self.nonEmpty(errorMessage)
        let normalizedStopReason = Self.nonEmpty(stopReason)
        let normalizedTimeoutPhase = Self.nonEmpty(timeoutPhase)
        let normalizedLivenessState = Self.nonEmpty(livenessState)
        let normalizedGatewayStatus = gatewayStatus?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let state: GatewayChatRunState

        if Self.isCancellation(
            gatewayStatus: normalizedGatewayStatus,
            stopReason: normalizedStopReason,
            aborted: aborted
        ) {
            state = .cancelled
        } else {
            switch normalizedGatewayStatus {
            case "ok":
                state = .completed
            case "error":
                state = .failed
            case "timeout":
                state = Self.isTerminalTimeout(
                    endedAt: endedAt,
                    errorMessage: normalizedError,
                    stopReason: normalizedStopReason,
                    timeoutPhase: normalizedTimeoutPhase,
                    livenessState: normalizedLivenessState,
                    providerStarted: providerStarted,
                    yielded: yielded,
                    pendingError: pendingError,
                    aborted: aborted
                ) ? .failed : .running
            case "pending":
                state = .running
            default:
                state = .unknown
            }
        }

        self.init(
            runId: runId,
            state: state,
            startedAt: startedAt,
            endedAt: endedAt,
            errorMessage: normalizedError,
            stopReason: normalizedStopReason,
            timeoutPhase: normalizedTimeoutPhase,
            livenessState: normalizedLivenessState,
            providerStarted: providerStarted,
            yielded: yielded,
            pendingError: pendingError,
            aborted: aborted
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isCancellation(
        gatewayStatus: String?,
        stopReason: String?,
        aborted: Bool
    ) -> Bool {
        guard let normalized = stopReason?.lowercased() else { return false }
        let tokens = normalized.split { !$0.isLetter && !$0.isNumber }
        let cancellationTokens: Set<Substring> = [
            "abort", "aborted", "cancel", "canceled", "cancelled", "kill", "killed"
        ]
        if tokens.contains(where: cancellationTokens.contains) {
            return true
        }

        // Current OpenClaw agent.wait responses do not forward the lifecycle's
        // `aborted` flag. Both chat.abort and the chat stop command are exposed
        // as status=timeout with an exact `rpc` or `stop` reason. Restricting
        // those generic words to the timeout shape preserves successful model
        // completions whose provider stop reason is also `stop`.
        guard gatewayStatus == "timeout" else { return false }
        return normalized == "rpc" || normalized == "stop" ||
            (aborted && (tokens.contains("rpc") || tokens.contains("stop")))
    }

    /// `agent.wait` uses `status=timeout` both for a nonterminal wait expiry and
    /// for a terminal runtime/provider timeout. OpenClaw attaches lifecycle
    /// evidence only to the latter. `pendingError` is an explicit retry-grace
    /// marker and therefore keeps the observation nonterminal.
    private static func isTerminalTimeout(
        endedAt: Date?,
        errorMessage: String?,
        stopReason: String?,
        timeoutPhase: String?,
        livenessState: String?,
        providerStarted: Bool?,
        yielded: Bool,
        pendingError: Bool,
        aborted: Bool
    ) -> Bool {
        guard !pendingError else { return false }
        let terminalTimeoutPhases = Set(["preflight", "provider", "post_turn"])
        return endedAt != nil
            || errorMessage != nil
            || stopReason != nil
            || livenessState != nil
            || providerStarted == true
            || yielded
            || aborted
            || timeoutPhase.map { terminalTimeoutPhases.contains($0.lowercased()) } == true
    }
}

enum GatewayProtocolTimestamp {
    private static let millisecondsThreshold = 100_000_000_000.0

    static func date(from value: Any?) -> Date? {
        guard let value, !(value is Bool) else { return nil }

        if let number = value as? NSNumber {
            let rawValue = number.doubleValue
            guard rawValue.isFinite else { return nil }
            let seconds = abs(rawValue) >= millisecondsThreshold
                ? rawValue / 1_000
                : rawValue
            return Date(timeIntervalSince1970: seconds)
        }

        guard let string = value as? String else { return nil }
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: normalized) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: normalized)
    }
}

struct GatewayAssistantMessageSnapshot: Codable, Equatable, Sendable {
    let text: String
    let timestamp: Date?
}

struct GatewayInFlightRunSnapshot: Codable, Equatable, Sendable {
    let runId: String
    let text: String?
}

enum GatewayChatRecoveryDecision: Equatable, Sendable {
    case resume(bufferedText: String?)
    case complete(text: String)
    case awaitingAuthoritativeState
    case failed(message: String?)
    case cancelled
}

struct GatewayChatRecoverySnapshot: Codable, Equatable, Sendable {
    let assistantMessages: [GatewayAssistantMessageSnapshot]
    let inFlightRun: GatewayInFlightRunSnapshot?
    let hasActiveRun: Bool

    func decision(
        expectedRunId: String,
        expectedRunStatus: GatewayChatRunStatusSnapshot,
        fallbackStartedAt: Date? = nil
    ) -> GatewayChatRecoveryDecision {
        guard expectedRunStatus.runId == expectedRunId else {
            return .awaitingAuthoritativeState
        }

        switch expectedRunStatus.state {
        case .failed:
            return .failed(message: expectedRunStatus.errorMessage)
        case .cancelled:
            return .cancelled
        case .completed:
            guard let startedAt = expectedRunStatus.startedAt ?? fallbackStartedAt,
                  let endedAt = expectedRunStatus.endedAt,
                  startedAt <= endedAt,
                  let message = latestAssistantMessage(from: startedAt, through: endedAt) else {
                return .awaitingAuthoritativeState
            }
            return .complete(text: message.text)
        case .running, .unknown:
            if let inFlightRun, inFlightRun.runId == expectedRunId {
                let bufferedText = inFlightRun.text?.isEmpty == false ? inFlightRun.text : nil
                return .resume(bufferedText: bufferedText)
            }
            return .awaitingAuthoritativeState
        }
    }

    private func latestAssistantMessage(
        from startedAt: Date,
        through endedAt: Date
    ) -> GatewayAssistantMessageSnapshot? {
        var latestMatch: (index: Int, message: GatewayAssistantMessageSnapshot)?

        for (index, message) in assistantMessages.enumerated() {
            guard let timestamp = message.timestamp,
                  timestamp >= startedAt,
                  timestamp <= endedAt,
                  !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            guard let current = latestMatch,
                  let currentTimestamp = current.message.timestamp else {
                latestMatch = (index, message)
                continue
            }

            if timestamp > currentTimestamp || (timestamp == currentTimestamp && index > current.index) {
                latestMatch = (index, message)
            }
        }

        return latestMatch?.message
    }
}

enum GatewayChatSendResult: Equatable, Sendable {
    case acknowledged(runId: String)
    case deliveryUnconfirmed(expectedRunId: String)
    case rejected(message: String?)

    var expectedRunId: String? {
        switch self {
        case .acknowledged(let runId): runId
        case .deliveryUnconfirmed(let expectedRunId): expectedRunId
        case .rejected: nil
        }
    }
}
