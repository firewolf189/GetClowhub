import Foundation
import Combine
import os.log

private let gwLog = Logger(subsystem: "com.openclaw.installer", category: "GatewayClient")

/// Last gateway-side rejection seen on the connect handshake. Carries the raw
/// error envelope so the UI can show *why* the WS won't connect (e.g.
/// `NOT_PAIRED` / `DEVICE_IDENTITY_REQUIRED` vs `token_mismatch`) instead of
/// the generic "Gateway is not connected".
struct GatewayConnectError: Equatable {
    let code: String          // e.g. "NOT_PAIRED", "INVALID_REQUEST"
    let detailCode: String?   // e.g. "DEVICE_IDENTITY_REQUIRED", "token_mismatch"
    let message: String
}

/// Lightweight WebSocket client for the OpenClaw gateway.
/// Uses native `URLSessionWebSocketTask` (macOS 13+), no third-party dependencies.
class GatewayClient: ObservableObject {
    private struct PendingChatSendRequest {
        let continuation: CheckedContinuation<GatewayChatSendResult, Never>
        let expectedRunId: String
        let startedAt: ContinuousClock.Instant
    }

    @Published private(set) var connectionState: GatewayConnectionState = .disconnected
    @Published private(set) var isConnected = false
    @Published private(set) var lastConnectError: GatewayConnectError?

    private var port: Int
    private var authToken: String
    /// Called before each connection attempt to get fresh port and token from config file
    private var credentialsProvider: (() -> (port: Int, authToken: String))?
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let delegateHandler = WebSocketDelegate()
    private let reconnectPolicy = GatewayReconnectPolicy()
    private var reconnectAttempt = 0
    private var isIntentionalDisconnect = false
    private var pendingResponses: [String: CheckedContinuation<Bool, Never>] = [:]
    private var pendingChatSendResponses: [String: PendingChatSendRequest] = [:]
    private var observedPendingChatSendRunIds: Set<String> = []
    private let chatAbortRequestRegistry = GatewayChatAbortRequestRegistry()
    private let chatRunStatusRequestRegistry = GatewayChatRunStatusRequestRegistry()
    private var pendingChatHistoryResponses: [String: CheckedContinuation<GatewayChatRecoverySnapshot?, Never>] = [:]
    /// The only RPC response allowed to complete the current gateway handshake.
    /// Access is serialized by `stateQueue`, along with the WebSocket generation.
    private var pendingConnectRequestId: String?
    private let responseLock = NSLock()
    private let eventHub = GatewayChatEventHub()

    /// Serializes all mutations of `webSocketTask` / `urlSession` / `reconnectAttempt` /
    /// `isIntentionalDisconnect` / `reconnectPending`.
    ///
    /// Without this, failure callbacks from `URLSessionWebSocketTask.receive`, send-callback
    /// errors, and the auth-failure handler can fire concurrently on different queues and
    /// each call `scheduleReconnect()`, racing to teardown/rebuild the URLSession. That race
    /// produces a double-release on the previous CF-backed URLSession and crashes the app
    /// with `malloc_zone_error` → `abort()` inside `_CFRelease`. See crash report
    /// 2026-05-12 (v1.1.46) Thread 9: `GatewayClient.establishConnection() + 330`.
    private let stateQueue = DispatchQueue(label: "com.openclaw.gateway.state")
    private let stateQueueKey = DispatchSpecificKey<Void>()

    /// True between the moment a reconnect is scheduled and the moment a new connection
    /// has been established. Prevents concurrent failure callbacks from each kicking off
    /// their own reconnect timer.
    private var reconnectPending = false

    /// Remains true from the first transport failure until a later authenticated
    /// connection succeeds. It lets us distinguish the initial app connection
    /// from a recovered connection that active chat runs must reconcile.
    private var recoveryCycleActive = false

    /// Invalidates callbacks from URLSessionWebSocketTask instances that were
    /// torn down before their asynchronous receive callback returned.
    private var connectionGeneration: UInt64 = 0

    /// Identifies the connection generation whose protocol handshake is still
    /// awaiting challenge/ack completion. This covers the full gateway
    /// handshake, not only URLSession's HTTP upgrade.
    private var pendingHandshakeGeneration: UInt64?

    /// Timestamp of the last WebSocket message received (any chat event, response, etc.).
    /// Used by the ViewModel as a coarse "WebSocket is alive" signal — note the gateway
    /// itself does NOT emit periodic tick/heartbeat broadcasts today (the older comment
    /// claiming it did was aspirational), so for a real liveness probe we run a separate
    /// client heartbeat below.
    private(set) var lastMessageReceivedAt = Date()

    /// Repeating `DispatchSourceTimer` that fires `sendPing` while the WS is up.
    /// Created on `stateQueue` after a successful connect ack, cancelled in
    /// `teardownSession()`. nil while disconnected.
    ///
    /// Why: macOS TCP keepalive defaults to ~2 hours of idle before the kernel sends
    /// its first probe, which means a silently half-open WS (Wi-Fi router flake / VPN
    /// reconnect / cell handoff) goes undetected for hours until the user next tries
    /// to `chat.send`. A 30s WS-protocol ping closes that gap — the server stack
    /// (per RFC 6455) auto-responds with a pong, so no gateway change is required.
    private var heartbeatTimer: DispatchSourceTimer?

    /// Set when a ping is in flight (we asked URLSession to send one, the pong hasn't
    /// arrived yet). nil otherwise. Read/written only on `stateQueue`.
    private var outstandingPingSentAt: Date?

    private let pingInterval: TimeInterval = 30
    private let pingTimeout: TimeInterval = 30  // pong must arrive within this window
    /// Recovery is infrequent and correctness-sensitive. Match the gateway's
    /// default history window so a completed background run is not lost after
    /// the user continues the same session while it is running.
    private static let chatRecoveryHistoryMessageLimit = 200

    // MARK: - Device pairing state

    /// Ed25519 keypair lazily loaded from (or generated into)
    /// `~/.openclaw/identity/device.json`. Carries the deviceId we present
    /// to the gateway and the private key we sign connect challenges with.
    /// See `DeviceIdentity.swift` for full rationale.
    private let deviceIdentity = DeviceIdentityStore.loadOrCreate()

    /// Stores the per-role `deviceToken` returned by `helloOk.auth.deviceToken`
    /// after a successful pair. Reused on reconnect to skip the full pairing
    /// flow and to land back on the SAME server-side device record (so its
    /// existing `approvedScopes` are reused, not reset).
    private let tokenStore = DeviceAuthTokenStore()

    /// Most recent connect-challenge nonce, captured by `handleMessage` when
    /// the gateway sends `event: "connect.challenge"`. Used as the `nonce`
    /// component of the v3 sign payload. nil until the challenge arrives —
    /// `sendConnectRequest()` falls back to no-device mode if nil so we
    /// keep working against older gateways that don't issue challenges.
    private var pendingChallengeNonce: String?

    /// Role we connect under. Hard-coded here because we always behave as the
    /// macOS operator UI; sub-agent / talk roles aren't in scope for this
    /// client. Pulling it into a property mostly so the v3 payload + token
    /// lookup don't drift apart from one literal.
    private let connectRole = "operator"

    init(port: Int, authToken: String, credentialsProvider: (() -> (port: Int, authToken: String))? = nil) {
        self.port = port
        self.authToken = authToken
        self.credentialsProvider = credentialsProvider
        stateQueue.setSpecific(key: stateQueueKey, value: ())
    }

    private static func elapsedMillisecondsText(since start: ContinuousClock.Instant) -> String {
        let duration = start.duration(to: ContinuousClock.now)
        let components = duration.components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.1f", milliseconds)
    }

    private func registerPendingChatSend(
        requestId: String,
        request: PendingChatSendRequest
    ) {
        responseLock.withLock {
            pendingChatSendResponses[requestId] = request
            observedPendingChatSendRunIds.remove(request.expectedRunId)
        }
    }

    private func takePendingChatSend(
        requestId: String
    ) -> (request: PendingChatSendRequest, deliveryObserved: Bool)? {
        responseLock.withLock {
            guard let request = pendingChatSendResponses.removeValue(forKey: requestId) else {
                return nil
            }
            let observed = observedPendingChatSendRunIds.remove(request.expectedRunId) != nil
            return (request, observed)
        }
    }

    private func recordPendingChatSendDelivery(runId: String) {
        responseLock.withLock {
            guard pendingChatSendResponses.values.contains(where: { $0.expectedRunId == runId }) else {
                return
            }
            observedPendingChatSendRunIds.insert(runId)
        }
    }

    // MARK: - Public API

    func connect() {
        stateQueue.async { [weak self] in
            guard let self = self else { return }
            self.isIntentionalDisconnect = false
            self.reconnectAttempt = 0
            self.reconnectPending = false
            if self.hasEventSubscribers() {
                self.recoveryCycleActive = true
            }
            self.publishConnectionState(.connecting)
            self.establishConnection()
        }
    }

    func disconnect() {
        stateQueue.async { [weak self] in
            guard let self = self else { return }
            self.isIntentionalDisconnect = true
            self.reconnectPending = false
            self.reconnectAttempt = 0
            let hasSubscribers = self.hasEventSubscribers()
            self.recoveryCycleActive = hasSubscribers
            self.teardownSession()
            self.publishConnectionState(.disconnected)
            if hasSubscribers {
                self.broadcastEvent(.transport(.disconnected))
            }
            DispatchQueue.main.async { self.lastConnectError = nil }
        }
    }

    /// Send `chat.abort` and preserve the gateway's semantic outcome. A valid
    /// RPC response may still report `aborted=false` when the run is no longer
    /// active, so callers must not treat transport acknowledgement as terminal.
    func abortChat(sessionKey: String, runId: String? = nil) async -> GatewayChatAbortResult {
        guard let ws = currentWebSocketTask() else { return .transportUnavailable }

        let requestId = UUID().uuidString
        var params: [String: Any] = [
            "sessionKey": sessionKey
        ]
        if let runId = runId {
            params["runId"] = runId
        }
        let payload: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "chat.abort",
            "params": params
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return .rejected(message: "Unable to encode chat.abort request")
        }

        return await withCheckedContinuation { continuation in
            chatAbortRequestRegistry.register(
                requestId: requestId,
                expectedRunId: runId,
                continuation: continuation
            )

            ws.send(.string(jsonString)) { [weak self] error in
                if error != nil {
                    self?.chatAbortRequestRegistry.cancel(requestId: requestId)
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.chatAbortRequestRegistry.cancel(requestId: requestId)
            }
        }
    }

    /// Apply a session-only model override through `sessions.patch`.
    /// This updates gateway session state without changing agent defaults in openclaw.json.
    func patchSessionModel(sessionKey: String, model: String) async -> Bool {
        guard let ws = currentWebSocketTask() else { return false }

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { return false }

        let requestId = UUID().uuidString
        let payload: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "sessions.patch",
            "params": [
                "key": sessionKey,
                "model": trimmedModel
            ] as [String: Any]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return false
        }

        let result: Bool = await withCheckedContinuation { continuation in
            responseLock.lock()
            pendingResponses[requestId] = continuation
            responseLock.unlock()

            ws.send(.string(jsonString)) { [weak self] error in
                if error != nil {
                    self?.responseLock.lock()
                    if let cont = self?.pendingResponses.removeValue(forKey: requestId) {
                        self?.responseLock.unlock()
                        cont.resume(returning: false)
                    } else {
                        self?.responseLock.unlock()
                    }
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.responseLock.lock()
                if let cont = self?.pendingResponses.removeValue(forKey: requestId) {
                    self?.responseLock.unlock()
                    cont.resume(returning: false)
                } else {
                    self?.responseLock.unlock()
                }
            }
        }

        return result
    }

    /// Apply a session-scoped reasoning level via `sessions.patch`.
    ///
    /// This is the switch the gateway actually honours. The per-request
    /// `chat.send.thinking` field passes schema validation but loses to the
    /// agent's `thinkingDefault` (e.g. deepseek ships `thinking=medium`), so the
    /// composer's effort has to be patched onto the session exactly the way the
    /// model override is. Pass `nil` to clear the override and fall back to the
    /// agent default (our `.auto`).
    ///
    /// Returns false when the gateway rejects the level — its error names the
    /// levels that model does accept, which is what drives the adaptive tiers.
    func patchSessionThinkingLevel(sessionKey: String, level: String?) async -> Bool {
        guard let ws = currentWebSocketTask() else { return false }

        let requestId = UUID().uuidString
        let payload: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "sessions.patch",
            "params": [
                "key": sessionKey,
                "thinkingLevel": level ?? NSNull()
            ] as [String: Any]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return false
        }

        gwLog.info("phase=session_thinking_patch session=\(sessionKey, privacy: .public) level=\(level ?? "auto(clear)", privacy: .public)")

        return await withCheckedContinuation { continuation in
            responseLock.lock()
            pendingResponses[requestId] = continuation
            responseLock.unlock()

            ws.send(.string(jsonString)) { [weak self] error in
                if error != nil {
                    self?.responseLock.lock()
                    if let cont = self?.pendingResponses.removeValue(forKey: requestId) {
                        self?.responseLock.unlock()
                        cont.resume(returning: false)
                    } else {
                        self?.responseLock.unlock()
                    }
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.responseLock.lock()
                if let cont = self?.pendingResponses.removeValue(forKey: requestId) {
                    self?.responseLock.unlock()
                    cont.resume(returning: false)
                } else {
                    self?.responseLock.unlock()
                }
            }
        }
    }

    /// Submit one idempotent chat run. An acknowledgement timeout is not an
    /// authoritative failure: the gateway may have accepted the request, so
    /// callers keep the same expected run id and reconcile instead of resending.
    func chatSend(
        sessionKey: String,
        message: String,
        idempotencyKey: String,
        attachments: [[String: Any]]? = nil,
        thinking: String? = nil
    ) async -> GatewayChatSendResult {
        guard let ws = currentWebSocketTask() else {
            return .rejected(message: "Gateway is not connected")
        }

        let requestId = UUID().uuidString
        let chatSendStartedAt = ContinuousClock.now

        var params: [String: Any] = [
            "sessionKey": sessionKey,
            "idempotencyKey": idempotencyKey,
            "message": message
        ]
        if let attachments = attachments, !attachments.isEmpty {
            params["attachments"] = attachments
        }
        // Per-request reasoning effort (string enum). Absent for `.auto`.
        if let thinking = thinking, !thinking.isEmpty {
            params["thinking"] = thinking
        }

        let payload: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "chat.send",
            "params": params
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            gwLog.error("chatSend: failed to serialize payload to JSON")
            if let attachments = attachments {
                for (i, att) in attachments.enumerated() {
                    let contentLen = (att["content"] as? String)?.count ?? 0
                    gwLog.error("  attachment[\(i)] content length: \(contentLen)")
                }
            }
            return .rejected(message: "Failed to serialize chat.send payload")
        }

        gwLog.info("chatSend: JSON size = \(jsonString.count) bytes, attachments = \(attachments?.count ?? 0)")

        return await withCheckedContinuation { continuation in
            registerPendingChatSend(
                requestId: requestId,
                request: PendingChatSendRequest(
                    continuation: continuation,
                    expectedRunId: idempotencyKey,
                    startedAt: chatSendStartedAt
                )
            )

            ws.send(.string(jsonString)) { [weak self] error in
                guard let error else {
                    gwLog.info("phase=chat_send_ws_send request=\(requestId, privacy: .public) bytes=\(jsonString.count, privacy: .public) elapsed_ms=\(Self.elapsedMillisecondsText(since: chatSendStartedAt), privacy: .public)")
                    return
                }
                guard let self else { return }

                gwLog.error("chatSend: WebSocket send error: \(error.localizedDescription)")
                if let pending = self.takePendingChatSend(requestId: requestId) {
                    pending.request.continuation.resume(
                        returning: pending.deliveryObserved
                            ? .acknowledged(runId: pending.request.expectedRunId)
                            : .deliveryUnconfirmed(expectedRunId: pending.request.expectedRunId)
                    )
                    if !pending.deliveryObserved {
                        self.scheduleReconnect()
                    }
                }
            }

            // Timeout after 10 seconds for the send acknowledgement
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self else { return }
                let pending = self.takePendingChatSend(requestId: requestId)
                guard let pending else { return }

                gwLog.warning("phase=chat_send_ack_timeout request=\(requestId, privacy: .public) elapsed_ms=\(Self.elapsedMillisecondsText(since: pending.request.startedAt), privacy: .public) delivery_observed=\(pending.deliveryObserved, privacy: .public)")
                pending.request.continuation.resume(
                    returning: pending.deliveryObserved
                        ? .acknowledged(runId: pending.request.expectedRunId)
                        : .deliveryUnconfirmed(expectedRunId: pending.request.expectedRunId)
                )
                if !pending.deliveryObserved {
                    self.scheduleReconnect()
                }
            }
        }
    }

    /// Subscribe to one run's chat events plus shared transport lifecycle.
    /// Filtering before buffering prevents each active row from retaining every
    /// other run's high-frequency deltas while the main actor is busy.
    func subscribeToEvents(
        subscriberId: String,
        runId: String,
        sessionKey: String
    ) -> AsyncStream<GatewayChatEvent> {
        eventHub.stream(
            subscriberId: subscriberId,
            runId: runId,
            sessionKey: sessionKey
        )
    }

    func bindEventSubscription(
        subscriberId: String,
        runId: String,
        sessionKey: String
    ) {
        eventHub.bindRun(
            subscriberId: subscriberId,
            runId: runId,
            sessionKey: sessionKey
        )
    }

    /// Remove a subscriber and terminate its event stream.
    func unsubscribe(subscriberId: String) {
        eventHub.unsubscribe(subscriberId: subscriberId)
    }

    private func hasEventSubscribers() -> Bool {
        !eventHub.isEmpty
    }

    private func eventSubscriberCount() -> Int {
        eventHub.count
    }

    func hasEventSubscription(subscriberId: String) -> Bool {
        eventHub.contains(subscriberId: subscriberId)
    }

    /// Publishes the canonical lifecycle and keeps the legacy Bool as a
    /// read-only compatibility projection.
    private func publishConnectionState(_ state: GatewayConnectionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.connectionState != state {
                self.connectionState = state
            }
            let connected = state.isConnected
            if self.isConnected != connected {
                self.isConnected = connected
            }
        }
    }

    func fetchChatRunStatus(runId: String) async -> GatewayChatRunStatusSnapshot? {
        guard let ws = currentWebSocketTask() else { return nil }

        let requestId = UUID().uuidString
        let payload: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "agent.wait",
            "params": [
                "runId": runId,
                "timeoutMs": 0
            ] as [String: Any]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            chatRunStatusRequestRegistry.register(
                requestId: requestId,
                expectedRunId: runId,
                continuation: continuation
            )

            ws.send(.string(jsonString)) { [weak self] error in
                guard error != nil, let self else { return }
                self.chatRunStatusRequestRegistry.cancel(requestId: requestId)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.chatRunStatusRequestRegistry.cancel(requestId: requestId)
            }
        }
    }

    func fetchChatRecoverySnapshot(sessionKey: String) async -> GatewayChatRecoverySnapshot? {
        guard let ws = currentWebSocketTask() else { return nil }

        let requestId = UUID().uuidString
        let payload: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "chat.history",
            "params": [
                "sessionKey": sessionKey,
                "limit": Self.chatRecoveryHistoryMessageLimit
            ] as [String: Any]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            responseLock.lock()
            pendingChatHistoryResponses[requestId] = continuation
            responseLock.unlock()

            ws.send(.string(jsonString)) { [weak self] error in
                if error != nil {
                    self?.responseLock.lock()
                    if let cont = self?.pendingChatHistoryResponses.removeValue(forKey: requestId) {
                        self?.responseLock.unlock()
                        cont.resume(returning: nil)
                    } else {
                        self?.responseLock.unlock()
                    }
                }
            }

            // Timeout after 10 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.responseLock.lock()
                if let cont = self?.pendingChatHistoryResponses.removeValue(forKey: requestId) {
                    self?.responseLock.unlock()
                    cont.resume(returning: nil)
                } else {
                    self?.responseLock.unlock()
                }
            }
        }
    }

    // MARK: - Connection Management

    /// Returns a generation-local task reference without racing teardown or
    /// replacement. The socket may still close after this snapshot; send
    /// callbacks already map that transport outcome into retryable semantics.
    private func currentWebSocketTask() -> URLSessionWebSocketTask? {
        if DispatchQueue.getSpecific(key: stateQueueKey) != nil {
            return webSocketTask
        }
        return stateQueue.sync { webSocketTask }
    }

    /// Tear down the current session/task. **Caller must be on `stateQueue`.**
    private func teardownSession() {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        stopHeartbeat()
        pendingConnectRequestId = nil
        pendingHandshakeGeneration = nil
        connectionGeneration &+= 1
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    /// Build a fresh URLSession + WebSocket task. **Caller must be on `stateQueue`.**
    ///
    /// Defensively tears down any stale session first so the property write below cannot
    /// stomp on a still-live URLSession owned by another in-flight reconnect.
    private func establishConnection() {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        guard !isIntentionalDisconnect else { return }

        // Defensive: any prior session must be torn down before we overwrite the property,
        // otherwise the old strong reference is dropped without `invalidateAndCancel`.
        teardownSession()

        // Refresh credentials from config file before each connection attempt
        if let provider = credentialsProvider {
            let creds = provider()
            self.port = creds.port
            self.authToken = creds.authToken
        }

        let urlString = "ws://127.0.0.1:\(port)/"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("http://127.0.0.1:\(port)", forHTTPHeaderField: "Origin")

        // Explicit bounds on the WS handshake — `timeoutIntervalForRequest` applies to
        // the initial HTTP upgrade; the WS stream itself is open-ended (long-running
        // tasks can stream for hours and that's fine). macOS defaults to 60s here,
        // which is unhelpfully generous given our 30s client heartbeat already proves
        // post-handshake liveness — drop to 30s so a stuck handshake surfaces fast
        // enough to schedule a reconnect rather than blocking for a minute.
        //
        // `timeoutIntervalForResource` defaults to ~7 days (DT_RESOURCE_TIMEOUT) which
        // matches what we want — a streaming WS is a long-lived resource by design.
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = reconnectPolicy.handshakeTimeout

        let session = URLSession(configuration: config, delegate: delegateHandler, delegateQueue: nil)
        self.urlSession = session

        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        let generation = connectionGeneration
        pendingHandshakeGeneration = generation
        scheduleHandshakeTimeout(for: generation)
        listenForMessages(on: task, generation: generation)
    }

    /// Bounds challenge/ack negotiation as well as the HTTP WebSocket upgrade.
    /// A stale timer cannot affect a newer socket because both generation
    /// identities must still match when it fires.
    private func scheduleHandshakeTimeout(for generation: UInt64) {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        stateQueue.asyncAfter(deadline: .now() + reconnectPolicy.handshakeTimeout) { [weak self] in
            guard let self,
                  !self.isIntentionalDisconnect,
                  self.pendingHandshakeGeneration == generation,
                  self.connectionGeneration == generation else {
                return
            }

            gwLog.warning("Gateway protocol handshake timed out after \(Int(self.reconnectPolicy.handshakeTimeout))s")
            self.pendingHandshakeGeneration = nil
            self.pendingConnectRequestId = nil
            self.scheduleReconnect()
        }
    }

    private func listenForMessages(on task: URLSessionWebSocketTask, generation: UInt64) {
        task.receive { [weak self] result in
            guard let self else { return }
            self.stateQueue.async { [weak self] in
                guard let self,
                      generation == self.connectionGeneration,
                      self.webSocketTask === task else {
                    return
                }

                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                    self.listenForMessages(on: task, generation: generation)

                case .failure:
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Track that the WebSocket is alive (any inbound message counts: chat events,
        // response acks, etc. — gateway does not emit periodic ticks today; client-side
        // ping/pong is what actively probes the link).
        lastMessageReceivedAt = Date()

        let type = json["type"] as? String

        if type == "event", let event = json["event"] as? String, event == "connect.challenge" {
            // Capture nonce for the v3 device signature. Older gateways may
            // omit the payload — we fall through with nonce=nil and
            // sendConnectRequest will skip the device field (i.e. behave like
            // pre-pairing clients did, working against legacy gateways).
            if let payload = json["payload"] as? [String: Any],
               let nonce = payload["nonce"] as? String,
               !nonce.trimmingCharacters(in: .whitespaces).isEmpty {
                self.pendingChallengeNonce = nonce
            } else {
                self.pendingChallengeNonce = nil
            }
            sendConnectRequest()
            return
        }

        // Handle chat events
        if type == "event", let event = json["event"] as? String, event == "chat" {
            if let payload = json["payload"] as? [String: Any] {
                handleChatEventPayload(payload)
            }
            return
        }

        if type == "event", let event = json["event"] as? String, event == "agent" {
            if let payload = json["payload"] as? [String: Any] {
                handleAgentEventPayload(payload)
            }
            return
        }

        if type == "res" {
            guard let id = json["id"] as? String else {
                gwLog.warning("Ignoring gateway response without a request id")
                return
            }
                // Check if there is a pending chat.send request.
                let pendingChatSend = takePendingChatSend(requestId: id)

                if let pendingChatSend {
                    if pendingChatSend.deliveryObserved {
                        pendingChatSend.request.continuation.resume(
                            returning: .acknowledged(runId: pendingChatSend.request.expectedRunId)
                        )
                        return
                    }
                    let isError = json["error"] != nil
                    if isError {
                        let elapsedText = Self.elapsedMillisecondsText(since: pendingChatSend.request.startedAt)
                        gwLog.error("phase=chat_send_ack_error request=\(id, privacy: .public) elapsed_ms=\(elapsedText, privacy: .public) error=\(String(describing: json["error"]), privacy: .public)")
                        pendingChatSend.request.continuation.resume(
                            returning: .rejected(message: String(describing: json["error"] ?? "Unknown gateway rejection"))
                        )
                    }
                    if !isError, let payloadDict = json["payload"] as? [String: Any],
                       let runId = payloadDict["runId"] as? String {
                        let elapsedText = Self.elapsedMillisecondsText(since: pendingChatSend.request.startedAt)
                        gwLog.info("phase=chat_send_ack request=\(id, privacy: .public) runId=\(runId, privacy: .public) elapsed_ms=\(elapsedText, privacy: .public)")
                        pendingChatSend.request.continuation.resume(returning: .acknowledged(runId: runId))
                    } else if !isError {
                        pendingChatSend.request.continuation.resume(
                            returning: .deliveryUnconfirmed(expectedRunId: pendingChatSend.request.expectedRunId)
                        )
                    }
                    return
                }

                let abortPayload = json["payload"] as? [String: Any]
                let abortResponse = (abortPayload?["aborted"] as? Bool).map {
                    GatewayChatAbortResponse(
                        aborted: $0,
                        runIds: abortPayload?["runIds"] as? [String] ?? []
                    )
                }
                if chatAbortRequestRegistry.resolve(
                    requestId: id,
                    response: abortResponse,
                    rejectionMessage: json["error"].flatMap(self.gatewayErrorMessage)
                ) {
                    return
                }

                let runStatusPayload = json["payload"] as? [String: Any]
                let responseRunId = runStatusPayload?["runId"] as? String
                let runStatusSnapshot: GatewayChatRunStatusSnapshot?
                if json["error"] == nil,
                   let runStatusPayload,
                   let responseRunId {
                    runStatusSnapshot = GatewayChatRunStatusSnapshot(
                        runId: responseRunId,
                        gatewayStatus: runStatusPayload["status"] as? String,
                        startedAt: GatewayProtocolTimestamp.date(from: runStatusPayload["startedAt"]),
                        endedAt: GatewayProtocolTimestamp.date(from: runStatusPayload["endedAt"]),
                        errorMessage: self.gatewayErrorMessage(
                            runStatusPayload["error"] ?? runStatusPayload["errorMessage"]
                        ),
                        stopReason: runStatusPayload["stopReason"] as? String,
                        timeoutPhase: runStatusPayload["timeoutPhase"] as? String,
                        livenessState: runStatusPayload["livenessState"] as? String,
                        providerStarted: runStatusPayload["providerStarted"] as? Bool,
                        yielded: self.boolValue(runStatusPayload["yielded"]),
                        pendingError: self.boolValue(runStatusPayload["pendingError"]),
                        aborted: self.boolValue(runStatusPayload["aborted"])
                    )
                } else {
                    runStatusSnapshot = nil
                }
                if chatRunStatusRequestRegistry.resolve(
                    requestId: id,
                    responseRunId: responseRunId,
                    snapshot: runStatusSnapshot
                ) {
                    return
                }

                // Check if there is a pending typed chat.history request.
                responseLock.lock()
                let chatHistoryCont = pendingChatHistoryResponses.removeValue(forKey: id)
                responseLock.unlock()

                if let chatHistoryCont = chatHistoryCont {
                    let isError = json["error"] != nil
                    if !isError, let payloadDict = json["payload"] as? [String: Any] {
                        let messages = payloadDict["messages"] as? [[String: Any]] ?? []
                        let assistantMessages = messages.compactMap { message -> GatewayAssistantMessageSnapshot? in
                            guard (message["role"] as? String) == "assistant" else { return nil }
                            return GatewayAssistantMessageSnapshot(
                                text: self.extractTextFromMessage(message),
                                timestamp: GatewayProtocolTimestamp.date(
                                    from: message["timestamp"] ?? message["ts"]
                                )
                            )
                        }

                        var inFlightRun: GatewayInFlightRunSnapshot?
                        if let rawInFlight = payloadDict["inFlightRun"] as? [String: Any],
                           let runId = rawInFlight["runId"] as? String {
                            let rawText = rawInFlight["text"] as? String
                            inFlightRun = GatewayInFlightRunSnapshot(
                                runId: runId,
                                text: rawText?.isEmpty == false ? rawText : nil
                            )
                        }

                        let sessionInfo = payloadDict["sessionInfo"] as? [String: Any]
                        let hasActiveRun = self.boolValue(sessionInfo?["hasActiveRun"])
                            || inFlightRun != nil
                        chatHistoryCont.resume(returning: GatewayChatRecoverySnapshot(
                            assistantMessages: assistantMessages,
                            inFlightRun: inFlightRun,
                            hasActiveRun: hasActiveRun
                        ))
                    } else {
                        chatHistoryCont.resume(returning: nil)
                    }
                    return
                }

                // Check if there is a pending generic Bool request.
                responseLock.lock()
                let continuation = pendingResponses.removeValue(forKey: id)
                responseLock.unlock()

                if let continuation = continuation {
                    let isError = json["error"] != nil
                    continuation.resume(returning: !isError)
                    return
                }

            guard id == pendingConnectRequestId else {
                gwLog.warning("Ignoring unmatched or late gateway response id=\(id, privacy: .public)")
                return
            }
            pendingConnectRequestId = nil
            pendingHandshakeGeneration = nil

            // Only the response to this connection generation's explicit connect
            // request is allowed to transition the transport to connected.
            let isError = json["error"] != nil
            if !isError {
                gwLog.info("Gateway connected successfully")
                // Persist the deviceToken from `helloOk.auth.deviceToken` if
                // present — lets the next connect re-bind to the same paired
                // device record (and its `approvedScopes`) without re-signing.
                self.persistDeviceTokenFromHello(json["payload"] as? [String: Any])
                let recoveredTransport = recoveryCycleActive
                reconnectAttempt = 0
                reconnectPending = false
                recoveryCycleActive = false
                startHeartbeat()
                publishConnectionState(.connected)
                DispatchQueue.main.async { [weak self] in
                    self?.lastConnectError = nil
                }
                if recoveredTransport {
                    broadcastEvent(.transport(.connected))
                }
            } else {
                // Connect auth failed (e.g. stale token after gateway restart).
                // Close this dead socket and reconnect with fresh credentials. The teardown
                // touches `webSocketTask` / `urlSession` so it must run on stateQueue,
                // otherwise it can race with scheduleReconnect()'s reconnect timer and
                // double-free the URLSession (crash on `_CFRelease` inside establishConnection).
                let parsedError = Self.parseConnectError(from: json["error"])
                gwLog.error("Gateway connect failed: code=\(parsedError.code) detail=\(parsedError.detailCode ?? "-") msg=\(parsedError.message). Will reconnect.")
                // If the failure looks token-related, drop our stored deviceToken
                // so the next reconnect re-pairs from scratch. Without this we'd
                // loop forever sending the same bad token. Heuristic: gateway
                // surfaces these as `detail-code` strings (see
                // connect-error-details-BuyNSAkw.js on server side).
                if Self.isDeviceTokenAuthFailure(parsedError) {
                    self.clearStoredDeviceTokenForCurrentRole()
                    gwLog.info("Cleared stored deviceToken due to token-related auth failure")
                }
                teardownSession()
                publishConnectionState(.disconnected)
                DispatchQueue.main.async { [weak self] in
                    self?.lastConnectError = parsedError
                }
                scheduleReconnect()
            }
        }
    }

    /// Pull `code` / `message` / `details.code` out of the gateway error envelope.
    /// Tolerant of unknown shapes: never throws, always yields something the UI
    /// can show even when the server's payload is unfamiliar.
    private static func parseConnectError(from raw: Any?) -> GatewayConnectError {
        let dict = raw as? [String: Any] ?? [:]
        let code = (dict["code"] as? String) ?? "UNKNOWN"
        let message = (dict["message"] as? String) ?? "Gateway rejected the connection"
        let detailCode = (dict["details"] as? [String: Any])?["code"] as? String
        return GatewayConnectError(code: code, detailCode: detailCode, message: message)
    }

    /// Whether `err` is the gateway saying our stored deviceToken is no good
    /// (revoked, mismatched, doesn't cover the requested scopes). When yes we
    /// drop the stored token so the next connect re-pairs from scratch.
    ///
    /// Strings derived from openclaw's `connect-error-details-BuyNSAkw.js`
    /// `ConnectErrorDetailCodes` enum + `formatGatewayAuthFailureMessage` —
    /// matched loosely on detailCode keywords so we don't pin to one exact
    /// spelling that the server might rename across versions.
    /// Every keyword the client treats as "stored device token is bad" lives
    /// in this ONE table. When a gateway upgrade renames an error code, add
    /// the new spelling here — do not scatter ad-hoc `contains` checks at
    /// call sites (guarded by scripts/verify_gateway_protocol_string_tables.swift).
    static let deviceTokenFailureSignals: [String] = [
        "device_token", "device-token",
        "token_revoked", "token-revoked",
        "token_mismatch", "token-mismatch",
        "scope_mismatch", "scope-mismatch",
        "device_token_mismatch",
    ]

    private static func isDeviceTokenAuthFailure(_ err: GatewayConnectError) -> Bool {
        let detail = (err.detailCode ?? "").lowercased()
        let msg = err.message.lowercased()
        for s in deviceTokenFailureSignals {
            if detail.contains(s) || msg.contains(s) { return true }
        }
        return false
    }

    private func sendConnectRequest() {
        let requestId = UUID().uuidString
        let instanceId = UUID().uuidString
        let locale = Locale.current.language.languageCode?.identifier ?? "en"

        // Static descriptors for the v3 signed payload. Must match the
        // strings we send in `params.client.*` and `params.role` exactly —
        // the gateway re-derives the payload from those request fields and
        // verifies the signature against it. Drift here → server reports
        // "invalid device signature" and 1008-closes the socket.
        let clientId = "openclaw-macos"
        // CRITICAL: "ui" is the gateway's canonical mode for native apps
        // (paired with the "openclaw-macos" client id). Do NOT use "webchat":
        // openclaw 2026.6.10 classifies mode=webchat connections as the public
        // webchat surface and rejects `sessions.patch` from them
        // ("webchat clients cannot patch sessions"), which breaks the composer
        // model override applied before every chat.send.
        let clientMode = "ui"
        // CRITICAL: use "darwin" (Node's `process.platform` on macOS), NOT
        // "macos". When the openclaw CLI / setup wizard ran on this same
        // machine, it auto-paired using `process.platform = "darwin"`, so
        // the server's `paired.platform` is "darwin". If our client claims
        // "macos", server detects `platformMismatch` and demands a
        // metadata-upgrade re-approval (preview-58 v2 hit exactly this on
        // 2026-05-15 19:22 — `reason=pairing required: device identity
        // changed and must be re-approved`). Aligning to "darwin" lets the
        // server match the existing record on the first try.
        let platformForAuth = "darwin"
        let deviceFamilyForAuth = ""
        let scopes = [
            // operator.write: required for chat.send / chat.abort / node.invoke
            // (the actual write-class RPCs we use). Older clients relied on
            // gateway's `if (scopes.includes("operator.admin")) return null`
            // bypass, but newer openclaw filters requested scopes against the
            // paired device's `approvedScopes`, so admin-only no longer works.
            // operator.admin: kept for cron.* / sessions.patch / etc admin RPCs.
            // operator.approvals: tool-approval RPCs.
            // operator.pairing: needed to do the device-pair handshake itself.
            "operator.admin",
            "operator.write",
            "operator.approvals",
            "operator.pairing",
        ]

        // Build auth payload from the gateway bootstrap token in
        // ~/.openclaw/openclaw.json. We intentionally do not prefer
        // device-auth.json here: a stale low-scope device token can block the
        // operator UI from reconnecting with the admin/write scopes it needs.
        let signatureToken: String? = authToken.isEmpty ? nil : authToken
        var auth: [String: Any] = [:]
        if let tok = signatureToken {
            auth["token"] = tok
        }

        // Build the v3 signed device descriptor. Skip silently if (a) the
        // gateway didn't send a connect-challenge nonce (legacy server, or
        // server crashed between accept and challenge) or (b) signing fails
        // for any reason — better to attempt a no-device connect (might still
        // succeed under admin-bypass on older gateways) than to deadlock the
        // app on an unsignable handshake.
        var device: [String: Any]? = nil
        if let nonce = pendingChallengeNonce, !nonce.isEmpty {
            let signedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
            // Use the SAME single token we put in `auth.token`. Empty string
            // when no auth available (server's resolveSignatureToken falls
            // through to "" too in that case).
            let tokenForSignature = signatureToken ?? ""
            let signPayload = [
                "v3",
                deviceIdentity.deviceId,
                clientId,
                clientMode,
                connectRole,
                scopes.joined(separator: ","),
                String(signedAtMs),
                tokenForSignature,
                nonce,
                platformForAuth,
                deviceFamilyForAuth,
            ].joined(separator: "|")
            if let signature = DeviceIdentityStore.sign(signPayload, with: deviceIdentity),
               let publicKeyB64 = DeviceIdentityStore.publicKeyRawBase64Url(deviceIdentity) {
                device = [
                    "id": deviceIdentity.deviceId,
                    "publicKey": publicKeyB64,
                    "signature": signature,
                    "signedAt": signedAtMs,
                    "nonce": nonce,
                ]
                gwLog.info("Connect: signing v3 device payload deviceId=\(self.deviceIdentity.deviceId.prefix(12), privacy: .public)… usingBootstrapToken=\(signatureToken != nil)")
            } else {
                gwLog.warning("Connect: device payload could not be signed — falling back to non-device connect")
            }
        } else {
            gwLog.warning("Connect: no challenge nonce — falling back to non-device connect (legacy gateway?)")
        }

        // Nonce is single-use; clear so a forced reconnect that arrives
        // before the next challenge doesn't reuse a stale value.
        pendingChallengeNonce = nil

        var params: [String: Any] = [
            "minProtocol": 3,
            "maxProtocol": 4,                   // gateway accepts highest mutual; v4 unlocks newer event shapes
            "client": [
                "id": clientId,
                // Real app version; client.version is informational only —
                // it is NOT part of the v3 signature payload above.
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
                "platform": platformForAuth,
                "mode": clientMode,
                "instanceId": instanceId,
            ],
            "role": connectRole,
            "scopes": scopes,
            "caps": ["tool-events"],
            "auth": auth,
            "locale": locale,
        ]
        if let device = device {
            params["device"] = device
        }

        let payload: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "connect",
            "params": params,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }

        let generation = connectionGeneration
        pendingConnectRequestId = requestId
        guard let webSocketTask else {
            pendingConnectRequestId = nil
            scheduleReconnect()
            return
        }
        webSocketTask.send(.string(jsonString)) { [weak self] error in
            guard error != nil else { return }
            self?.stateQueue.async { [weak self] in
                guard let self,
                      self.connectionGeneration == generation,
                      self.pendingConnectRequestId == requestId else {
                    return
                }
                self.pendingConnectRequestId = nil
                self.scheduleReconnect()
            }
        }
    }

    /// Persist the `deviceToken` returned in `helloOk.auth.deviceToken` after
    /// a successful pair. Subsequent connects use it (see `sendConnectRequest`)
    /// so the gateway matches us back to the same paired-device record.
    /// Returning nil here is a no-op — older gateways or fallback paths may
    /// not include `auth` in the hello payload at all.
    private func persistDeviceTokenFromHello(_ helloPayload: [String: Any]?) {
        guard let authDict = helloPayload?["auth"] as? [String: Any],
              let token = authDict["deviceToken"] as? String,
              !token.isEmpty else {
            return
        }
        let scopes = (authDict["scopes"] as? [String]) ?? []
        let role = (authDict["role"] as? String) ?? connectRole
        tokenStore.save(role: role,
                        deviceId: deviceIdentity.deviceId,
                        token: StoredDeviceAuthToken(
                            token: token,
                            scopes: scopes,
                            updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000)
                        ))
        let scopeList = scopes.joined(separator: ",")
        gwLog.info("Persisted deviceToken for role=\(role, privacy: .public), scopes=\(scopeList, privacy: .public)")
    }

    /// Clear a stored deviceToken (typically because the gateway just told us
    /// it's revoked / mismatched). Next connect will fall back to the
    /// bootstrap-token + sign path and re-pair.
    private func clearStoredDeviceTokenForCurrentRole() {
        tokenStore.remove(role: connectRole, deviceId: deviceIdentity.deviceId)
    }

    /// Schedule a reconnect after exponential backoff.
    ///
    /// Can be invoked from any queue (URLSession delegate queue, send-callback queue,
    /// main, etc.). Coalesces concurrent invocations via `reconnectPending` — only the
    /// first call within a reconnect cycle actually arms a timer; subsequent calls are
    /// no-ops until the new connection is established (or torn down by `disconnect()`).
    ///
    /// Was: dispatched the reconnect body to `DispatchQueue.global()`, which let multiple
    /// failure callbacks each rebuild the URLSession in parallel and race on releasing
    /// the previous one — root cause of the v1.1.46 `_CFRelease` crash.
    private func scheduleReconnect() {
        stateQueue.async { [weak self] in
            guard let self,
                  !self.isIntentionalDisconnect,
                  !self.reconnectPending else { return }
            self.recoveryCycleActive = true

            guard self.reconnectPolicy.canScheduleAttempt(
                afterCompletedAttempts: self.reconnectAttempt
            ) else {
                self.reconnectPending = false
                self.teardownSession()
                let exhausted = GatewayConnectionState.recoveryExhausted(attempts: self.reconnectAttempt)
                self.publishConnectionState(exhausted)
                self.broadcastEvent(.transport(exhausted))
                gwLog.error("Gateway recovery exhausted after \(self.reconnectAttempt) attempts")
                return
            }

            let attempt = self.reconnectAttempt + 1
            guard let delay = self.reconnectPolicy.delayBeforeAttempt(attempt) else {
                assertionFailure("Reconnect policy accepted attempt without a delay")
                return
            }
            self.reconnectAttempt = attempt
            self.reconnectPending = true
            self.teardownSession()
            let scheduledGeneration = self.connectionGeneration

            let reconnecting = GatewayConnectionState.reconnecting(attempt: attempt, maxAttempts: self.reconnectPolicy.maximumAttempts)
            self.publishConnectionState(reconnecting)
            self.broadcastEvent(.transport(reconnecting))
            gwLog.warning("Gateway reconnect attempt \(attempt)/\(self.reconnectPolicy.maximumAttempts) in \(delay)s")

            self.stateQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      !self.isIntentionalDisconnect,
                      scheduledGeneration == self.connectionGeneration else {
                    return
                }
                // Stays inside stateQueue: teardown + rebuild are both serial.
                // reconnectPending flips false at the moment we begin establishing —
                // a fresh failure from the new socket is allowed to re-arm the timer.
                self.reconnectPending = false
                self.establishConnection()
            }
        }
    }

    // MARK: - Heartbeat (client → gateway WS-protocol ping)

    /// Start the heartbeat timer. **Caller must be on `stateQueue`.**
    ///
    /// Idempotent — any prior timer is cancelled and the outstanding-ping marker
    /// is reset before the new timer arms. Safe to call after each successful
    /// connect even if a previous heartbeat was still in some half-state.
    private func startHeartbeat() {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        stopHeartbeat()

        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + pingInterval, repeating: pingInterval)
        timer.setEventHandler { [weak self] in
            self?.heartbeatTick()
        }
        timer.resume()
        heartbeatTimer = timer
    }

    /// Cancel the heartbeat timer and clear the outstanding-ping marker.
    /// Safe to call from any queue (DispatchSourceTimer.cancel is thread-safe).
    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        outstandingPingSentAt = nil
    }

    /// Fires every `pingInterval` seconds while connected.
    ///
    /// Two cases per tick:
    ///   1. A previous ping is still outstanding AND it was sent more than
    ///      `pingTimeout` ago — the gateway never pong'd, presume dead and
    ///      force a reconnect. Without this branch we'd happily keep firing
    ///      pings into the void forever.
    ///   2. No outstanding ping — send a fresh one and record the timestamp.
    ///      The pong handler clears the marker. If the handler is invoked
    ///      with an error, the WS is provably bad and we reconnect immediately
    ///      rather than waiting for the next tick.
    private func heartbeatTick() {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        guard let ws = webSocketTask, !isIntentionalDisconnect else { return }

        if let sentAt = outstandingPingSentAt {
            let elapsed = Date().timeIntervalSince(sentAt)
            if elapsed >= pingTimeout {
                gwLog.warning("Heartbeat: pong overdue by \(Int(elapsed))s, forcing reconnect")
                stopHeartbeat()
                scheduleReconnect()
            }
            // Else: still within the timeout window — wait, don't pile on extra pings.
            return
        }

        let generation = connectionGeneration
        outstandingPingSentAt = Date()
        ws.sendPing { [weak self] error in
            // Pong handler runs on URLSession's internal queue; bounce back to
            // stateQueue so we mutate `outstandingPingSentAt` under the same
            // serialization that everything else uses.
            self?.stateQueue.async {
                guard let self,
                      generation == self.connectionGeneration,
                      self.webSocketTask === ws else { return }
                if let error = error {
                    gwLog.warning("Heartbeat ping send/pong error: \(error.localizedDescription) — reconnecting")
                    self.stopHeartbeat()
                    self.scheduleReconnect()
                } else {
                    // Pong received cleanly. Clear the marker so the next tick
                    // fires a fresh ping.
                    self.outstandingPingSentAt = nil
                }
            }
        }
    }

    // MARK: - Chat Event Helpers

    private func handleAgentEventPayload(_ payload: [String: Any]) {
        guard let runId = payload["runId"] as? String else { return }
        let sessionKey = payload["sessionKey"] as? String
        guard let event = parseGatewayActivity(from: payload) else { return }
        broadcastEvent(.activity(runId: runId, sessionKey: sessionKey, event: event))
    }

    private func parseGatewayActivity(from payload: [String: Any]) -> GatewayActivityEvent? {
        let stream = payload["stream"] as? String
        let data = payload["data"] as? [String: Any] ?? [:]

        if let modelEvent = parseModelActivity(data: data, payload: payload) {
            return modelEvent
        }
        if let agentEvent = parseAgentActivity(data: data, payload: payload) {
            return agentEvent
        }

        guard stream == "tool" else {
            if stream == "error" {
                let key = stableActivityKey(prefix: "agent-error", payload: payload, data: data)
                return GatewayActivityEvent(kind: .toolFailed, detail: nil, dedupeKey: key)
            }
            return nil
        }

        let toolName = firstString(in: data, keys: ["toolName", "name", "tool", "commandName"])
            ?? firstString(in: payload, keys: ["toolName", "name", "tool"])
        let normalizedTool = toolName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isError = boolValue(data["isError"])
            || ["error", "failed", "failure"].contains((firstString(in: data, keys: ["status", "state", "phase"]) ?? "").lowercased())

        let detail = sanitizedActivityDetail(for: normalizedTool, data: data)
        let key = stableActivityKey(prefix: "tool", payload: payload, data: data, fallback: "\(normalizedTool ?? "unknown"):\(detail ?? "")")

        if isError {
            return GatewayActivityEvent(kind: .toolFailed, detail: detail ?? toolName, dedupeKey: key)
        }

        guard let normalizedTool else { return nil }
        guard let kind = Self.activityKindByToolName[normalizedTool] else {
            return GatewayActivityEvent(kind: .loadedTools, detail: toolName, dedupeKey: key)
        }
        let usesToolNameFallback = kind == .agentUsed || kind == .agentRecruited
        return GatewayActivityEvent(
            kind: kind,
            detail: usesToolNameFallback ? (detail ?? toolName) : detail,
            dedupeKey: key
        )
    }

    /// Every gateway tool name → activity kind mapping lives in this ONE
    /// table. Gateway upgrades that add or rename tools should extend it
    /// here; unknown names degrade to `.loadedTools` with the raw tool name
    /// as detail, so drift stays visible in the activity feed instead of
    /// disappearing (guarded by scripts/verify_gateway_protocol_string_tables.swift).
    static let activityKindByToolName: [String: GatewayActivityEvent.Kind] = [
        "read": .readFiles, "read_file": .readFiles, "file_read": .readFiles,
        "exec": .ranCommands, "bash": .ranCommands, "shell": .ranCommands,
        "command": .ranCommands, "run_command": .ranCommands,
        "write": .createdFiles, "create_file": .createdFiles,
        "edit": .editedFiles, "patch": .editedFiles, "apply_patch": .editedFiles,
        "str_replace": .editedFiles, "replace": .editedFiles, "write_file": .editedFiles,
        "grep": .searchedCode, "rg": .searchedCode, "search": .searchedCode,
        "glob": .searchedCode, "find": .searchedCode, "list": .searchedCode,
        "ls": .searchedCode, "list_dir": .searchedCode,
        "agent": .agentUsed, "agents": .agentUsed, "subagent": .agentUsed,
        "subagents": .agentUsed, "delegate": .agentUsed, "dispatch_agent": .agentUsed,
        "recruit": .agentRecruited, "recruit_agent": .agentRecruited,
        "agent_recruit": .agentRecruited, "marketplace_agent": .agentRecruited,
    ]

    private func parseModelActivity(data: [String: Any], payload: [String: Any]) -> GatewayActivityEvent? {
        let provider = firstString(in: data, keys: ["provider"])
        let model = firstString(in: data, keys: ["model", "modelId"])
        guard provider != nil || model != nil else { return nil }
        let detail = [provider, model]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        guard !detail.isEmpty else { return nil }
        let key = stableActivityKey(prefix: "model", payload: payload, data: data, fallback: detail)
        return GatewayActivityEvent(kind: .selectedModel, detail: detail, dedupeKey: key)
    }

    private func parseAgentActivity(data: [String: Any], payload: [String: Any]) -> GatewayActivityEvent? {
        let phase = (
            firstString(in: data, keys: ["phase", "action", "event", "status", "state"])
            ?? firstString(in: payload, keys: ["phase", "action", "event", "status", "state"])
            ?? ""
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

        let agentId = firstString(in: data, keys: ["agentId", "agent", "subagent", "subAgentId", "name"])
            ?? firstString(in: payload, keys: ["agentId", "agent", "subagent", "subAgentId", "name"])
        let detail = agentId.flatMap { clippedDetail($0) }
        let key = stableActivityKey(prefix: "agent", payload: payload, data: data, fallback: "\(phase):\(detail ?? "")")

        if phase.contains("recruit") || phase.contains("install") {
            return GatewayActivityEvent(kind: .agentRecruited, detail: detail, dedupeKey: key)
        }
        guard detail != nil else { return nil }
        if phase.contains("agent") || phase.contains("delegate") || phase.contains("dispatch") || phase.contains("subagent") {
            return GatewayActivityEvent(kind: .agentUsed, detail: detail, dedupeKey: key)
        }
        return nil
    }

    private func sanitizedActivityDetail(for toolName: String?, data: [String: Any]) -> String? {
        // Resolve through the same activityKindByToolName table as the
        // classifier so tool-name spellings live in exactly one place.
        let kind = toolName.flatMap { Self.activityKindByToolName[$0] }
        let argumentKeys: [String]
        switch kind {
        case .readFiles, .createdFiles, .editedFiles:
            argumentKeys = ["path", "file", "filePath", "target", "resolvedPath"]
        case .ranCommands:
            argumentKeys = ["command", "cmd"]
        case .searchedCode:
            argumentKeys = ["query", "pattern", "path", "cwd", "command"]
        case .agentUsed, .agentRecruited:
            argumentKeys = ["agentId", "agent", "subagent", "subAgentId", "name", "role"]
        default:
            argumentKeys = ["path", "command", "query", "name", "agentId", "agent"]
        }

        if let direct = firstString(in: data, keys: argumentKeys) {
            return clippedDetail(direct)
        }
        if let arguments = data["arguments"] as? [String: Any],
           let nested = firstString(in: arguments, keys: argumentKeys) {
            return clippedDetail(nested)
        }
        if let input = data["input"] as? [String: Any],
           let nested = firstString(in: input, keys: argumentKeys) {
            return clippedDetail(nested)
        }
        if let args = data["args"] as? [String: Any],
           let nested = firstString(in: args, keys: argumentKeys) {
            return clippedDetail(nested)
        }
        return nil
    }

    private func stableActivityKey(prefix: String, payload: [String: Any], data: [String: Any], fallback: String = "") -> String {
        let id = firstString(in: data, keys: ["toolCallId", "callId", "id"])
            ?? firstString(in: payload, keys: ["toolCallId", "callId", "id"])
        if let id, !id.isEmpty {
            return "\(prefix):\(id)"
        }
        let runId = payload["runId"] as? String ?? ""
        let seq = payload["seq"].map { String(describing: $0) } ?? ""
        return "\(prefix):\(runId):\(seq):\(fallback)"
    }

    private func firstString(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
            if let value = dict[key] {
                let description = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
                if !description.isEmpty, description != "Optional(nil)" {
                    return description
                }
            }
        }
        return nil
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let string = value as? String {
            return ["true", "yes", "1"].contains(string.lowercased())
        }
        return false
    }

    private func gatewayErrorMessage(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let dictionary = value as? [String: Any] {
            return firstString(in: dictionary, keys: ["message", "errorMessage", "code"])
        }
        guard let value else { return nil }
        let description = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? nil : description
    }

    private func clippedDetail(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= 160 {
            return trimmed
        }
        return String(trimmed.prefix(157)) + "..."
    }

    private func handleChatEventPayload(_ payload: [String: Any]) {
        guard let state = payload["state"] as? String,
              let runId = payload["runId"] as? String ?? payload["idempotencyKey"] as? String,
              let sessionKey = payload["sessionKey"] as? String else {
            gwLog.warning("chat event missing required fields: state/runId/sessionKey")
            return
        }

        recordPendingChatSendDelivery(runId: runId)

        let event: GatewayChatEvent
        switch state {
        case "delta":
            let text = extractTextFromMessage(payload["message"])
            gwLog.debug("chat event: state=delta, runId=\(runId, privacy: .public), sessionKey=\(sessionKey, privacy: .public), textLen=\(text.count), subscribers=\(self.eventSubscriberCount())")
            event = .delta(runId: runId, sessionKey: sessionKey, text: text)
        case "final":
            let text = extractTextFromMessage(payload["message"])
            let hasMessage = payload["message"] != nil
            gwLog.info("chat event: state=final, runId=\(runId, privacy: .public), sessionKey=\(sessionKey, privacy: .public), textLen=\(text.count), hasMessage=\(hasMessage), subscribers=\(self.eventSubscriberCount())")
            event = .final_(runId: runId, sessionKey: sessionKey, text: text)
        case "aborted":
            event = .aborted(runId: runId, sessionKey: sessionKey)
        case "error":
            var message = ""

            // Try to extract from payload.message.errorMessage (nested-dict format)
            if let msgDict = payload["message"] as? [String: Any],
               let errorMsg = msgDict["errorMessage"] as? String {
                message = errorMsg
            }
            // Flat format: gateway also emits errorMessage directly on payload.
            // Was missing — user-visible bug: LLM-timeout errors showed up as
            // ⚠️ ["errorMessage": LLM request timed out., "seq": 2, "runId": ...,
            // "state": error, "sessionKey": ...] (whole payload dumped via
            // String(describing:) because none of the legacy paths matched).
            else if let errorMsg = payload["errorMessage"] as? String {
                message = errorMsg
            }
            // Fallback to payload.message if it's a string
            else if let msg = payload["message"] as? String {
                message = msg
            }
            // Fallback to payload.error.message
            else if let errDict = payload["error"] as? [String: Any],
                    let errMsg = errDict["message"] as? String {
                message = errMsg
            }

            // Check the full payload description for known error patterns
            let payloadDesc = String(describing: payload)
            if message.contains("Key is blocked") || payloadDesc.contains("Key is blocked") {
                message = "Your API key has exceeded its budget. For details, please visit: https://www.getclawhub.com/member/billing/"
            } else if message.contains("Unable to find token") || payloadDesc.contains("Unable to find token")
                        || message.contains("Invalid proxy server token") || payloadDesc.contains("Invalid proxy server token") {
                message = "Your API key may not exist or has been deleted. Please check: https://www.getclawhub.com/member/api-keys/"
            } else if message.isEmpty {
                // No known extraction path matched — show raw payload
                message = payloadDesc
            }

            gwLog.warning("chat error event: runId=\(runId), message=\(message)")
            event = .error(runId: runId, sessionKey: sessionKey, message: message)
        default:
            return
        }

        broadcastEvent(event)
    }

    private func extractTextFromMessage(_ message: Any?) -> String {
        guard let message = message else { return "" }

        // Direct string
        if let text = message as? String {
            return text
        }

        // Dict with content array: { content: [{type:"text", text:"..."}] }
        if let dict = message as? [String: Any] {
            if let contentArray = dict["content"] as? [[String: Any]] {
                let texts = contentArray.compactMap { block -> String? in
                    guard block["type"] as? String == "text" else { return nil }
                    return block["text"] as? String
                }
                return texts.joined()
            }
            // Dict with text property
            if let text = dict["text"] as? String {
                return text
            }
        }

        return ""
    }

    private func broadcastEvent(_ event: GatewayChatEvent) {
        eventHub.broadcast(event)
    }
}

// MARK: - URLSession WebSocket Delegate

private class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        // Connection opened — challenge will arrive as a message
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        // Handled by receive failure path
    }
}
