import Foundation

/// Events emitted by the gateway for chat sessions. Transport lifecycle is
/// intentionally part of the same ordered stream but is not a run terminal.
enum GatewayChatEvent: Sendable {
    case delta(runId: String, sessionKey: String, text: String)
    case final_(runId: String, sessionKey: String, text: String)
    case aborted(runId: String, sessionKey: String)
    case error(runId: String, sessionKey: String, message: String)
    case activity(runId: String, sessionKey: String?, event: GatewayActivityEvent)
    case transport(GatewayConnectionState)
}

extension GatewayChatEvent {
    /// The gateway run id carried by a chat run event; nil for transport events.
    var runId: String? {
        switch self {
        case .delta(let runId, _, _),
             .final_(let runId, _, _),
             .error(let runId, _, _),
             .activity(let runId, _, _):
            return runId
        case .aborted(let runId, _):
            return runId
        case .transport:
            return nil
        }
    }

    /// The session key carried by a chat run event; nil for transport events and
    /// for session-agnostic activity events.
    var sessionKey: String? {
        switch self {
        case .delta(_, let sessionKey, _),
             .final_(_, let sessionKey, _),
             .error(_, let sessionKey, _):
            return sessionKey
        case .aborted(_, let sessionKey):
            return sessionKey
        case .activity(_, let sessionKey, _):
            return sessionKey
        case .transport:
            return nil
        }
    }
}

struct GatewayActivityEvent: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case loadedTools
        case searchedCode
        case readFiles
        case ranCommands
        case editedFiles
        case createdFiles
        case selectedModel
        case agentUsed
        case agentRecruited
        case toolFailed
    }

    let kind: Kind
    let detail: String?
    let dedupeKey: String
}

/// Lock-owned fan-out for chat and transport events. `AsyncStream.yield` is
/// thread-safe and enqueues without waiting for consumers, so yielding in the
/// caller's order preserves delta/activity/final ordering without dispatching
/// separate global-queue blocks that can overtake one another.
nonisolated final class GatewayChatEventHub: @unchecked Sendable {
    static let bufferLimit = 128

    private typealias Continuation = AsyncStream<GatewayChatEvent>.Continuation
    private struct Subscription {
        let token: UUID
        let continuation: Continuation
        var runIds: Set<String>
        var sessionKey: String
        // False until the gateway's own run id is bound via `bindRun`. Before that
        // the subscription only knows the client idempotency key it sent — not the
        // run id the gateway actually assigned — so it is routed by session. Once a
        // real run id is bound we switch to strict run-id matching to keep
        // concurrent runs in the same session from cross-delivering.
        var hasConfirmedGatewayRun: Bool
    }

    private struct RoutedEvent {
        let runId: String
        let sessionKey: String?
        let isTerminal: Bool
    }

    private let lock = NSLock()
    private var subscriptions: [String: Subscription] = [:]

    var count: Int {
        lock.withLock { subscriptions.count }
    }

    var isEmpty: Bool {
        count == 0
    }

    func contains(subscriberId: String) -> Bool {
        lock.withLock { subscriptions[subscriberId] != nil }
    }

    func stream(
        subscriberId: String,
        runId: String,
        sessionKey: String
    ) -> AsyncStream<GatewayChatEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(Self.bufferLimit)) { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            let token = UUID()
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(subscriberId: subscriberId, token: token)
            }

            let previous = self.lock.withLock {
                self.subscriptions.updateValue(
                    Subscription(
                        token: token,
                        continuation: continuation,
                        runIds: [runId],
                        sessionKey: sessionKey,
                        hasConfirmedGatewayRun: false
                    ),
                    forKey: subscriberId
                )
            }
            previous?.continuation.finish()
        }
    }

    func bindRun(subscriberId: String, runId: String, sessionKey: String) {
        lock.withLock {
            guard var subscription = subscriptions[subscriberId] else { return }
            subscription.runIds.insert(runId)
            subscription.sessionKey = sessionKey
            subscription.hasConfirmedGatewayRun = true
            subscriptions[subscriberId] = subscription
        }
    }

    func unsubscribe(subscriberId: String) {
        let subscription = lock.withLock {
            subscriptions.removeValue(forKey: subscriberId)
        }
        subscription?.continuation.finish()
    }

    func broadcast(_ event: GatewayChatEvent) {
        let routedEvent = Self.routedEvent(for: event)
        let recipients = lock.withLock { () -> [Continuation] in
            let matchingIds: [String] = subscriptions.compactMap { subscriberId, subscription in
                guard Self.matches(subscription, routedEvent: routedEvent) else { return nil }
                return subscriberId
            }
            let continuations = matchingIds.compactMap { subscriptions[$0]?.continuation }
            if routedEvent?.isTerminal == true {
                for subscriberId in matchingIds {
                    subscriptions.removeValue(forKey: subscriberId)
                }
            }
            return continuations
        }
        for recipient in recipients {
            recipient.yield(event)
            if routedEvent?.isTerminal == true {
                recipient.finish()
            }
        }
    }

    private static func matches(
        _ subscription: Subscription,
        routedEvent: RoutedEvent?
    ) -> Bool {
        guard let routedEvent else { return true }
        let sessionMatches = routedEvent.sessionKey == nil
            || routedEvent.sessionKey == subscription.sessionKey
        guard sessionMatches else { return false }
        // Provisional subscriptions (no gateway run id bound yet) are routed by
        // session: the gateway stamps events with the run id it assigned, which is
        // never the client idempotency key we subscribed with, so a strict run-id
        // gate here would silently drop every reply. Once the real run id is bound
        // (from the chat.send ack or the first observed event) we match strictly.
        guard subscription.hasConfirmedGatewayRun else { return true }
        return subscription.runIds.contains(routedEvent.runId)
    }

    private static func routedEvent(for event: GatewayChatEvent) -> RoutedEvent? {
        switch event {
        case .delta(let runId, let sessionKey, _):
            RoutedEvent(runId: runId, sessionKey: sessionKey, isTerminal: false)
        case .final_(let runId, let sessionKey, _):
            RoutedEvent(runId: runId, sessionKey: sessionKey, isTerminal: true)
        case .aborted(let runId, let sessionKey):
            RoutedEvent(runId: runId, sessionKey: sessionKey, isTerminal: true)
        case .error(let runId, let sessionKey, _):
            RoutedEvent(runId: runId, sessionKey: sessionKey, isTerminal: true)
        case .activity(let runId, let sessionKey, _):
            RoutedEvent(runId: runId, sessionKey: sessionKey, isTerminal: false)
        case .transport:
            nil
        }
    }

    private func removeContinuation(subscriberId: String, token: UUID) {
        lock.withLock {
            guard subscriptions[subscriberId]?.token == token else { return }
            subscriptions.removeValue(forKey: subscriberId)
        }
    }
}
