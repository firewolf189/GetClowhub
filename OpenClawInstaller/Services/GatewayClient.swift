import Foundation
import Combine
import os.log

private let gwLog = Logger(subsystem: "com.openclaw.installer", category: "GatewayClient")

/// Events emitted by the gateway for chat sessions.
enum GatewayChatEvent {
    case delta(runId: String, sessionKey: String, text: String)
    case final_(runId: String, sessionKey: String, text: String)
    case aborted(runId: String, sessionKey: String)
    case error(runId: String, sessionKey: String, message: String)
}

/// Lightweight WebSocket client for the OpenClaw gateway.
/// Uses native `URLSessionWebSocketTask` (macOS 13+), no third-party dependencies.
class GatewayClient: ObservableObject {
    @Published var isConnected = false

    private var port: Int
    private var authToken: String
    /// Called before each connection attempt to get fresh port and token from config file
    private var credentialsProvider: (() -> (port: Int, authToken: String))?
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let delegateHandler = WebSocketDelegate()
    private var reconnectAttempt = 0
    private let maxReconnectDelay: TimeInterval = 15
    private var isIntentionalDisconnect = false
    private var pendingResponses: [String: CheckedContinuation<Bool, Never>] = [:]
    private var pendingChatSendResponses: [String: CheckedContinuation<String?, Never>] = [:]
    private var pendingChatHistoryResponses: [String: CheckedContinuation<String?, Never>] = [:]
    private let responseLock = NSLock()
    private var eventContinuations: [String: AsyncStream<GatewayChatEvent>.Continuation] = [:]
    private let eventLock = NSLock()

    /// Timestamp of the last WebSocket message received (any type: tick, chat, etc.).
    /// Used by the ViewModel to distinguish "gateway is alive but agent is busy with tools"
    /// from "gateway connection is dead".
    private(set) var lastMessageReceivedAt = Date()

    init(port: Int, authToken: String, credentialsProvider: (() -> (port: Int, authToken: String))? = nil) {
        self.port = port
        self.authToken = authToken
        self.credentialsProvider = credentialsProvider
    }

    // MARK: - Public API

    func connect() {
        isIntentionalDisconnect = false
        reconnectAttempt = 0
        establishConnection()
    }

    func disconnect() {
        isIntentionalDisconnect = true
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        DispatchQueue.main.async { self.isConnected = false }
    }

    /// Send `chat.abort` to the gateway. Returns `true` if the abort was acknowledged.
    func abortChat(sessionKey: String, runId: String? = nil) async -> Bool {
        guard let ws = webSocketTask else { return false }

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
            return false
        }

        // Register a continuation to wait for the response
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

            // Timeout after 5 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
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

    /// Send a chat message via `chat.send`. Returns the runId on success, nil on failure.
    func chatSend(sessionKey: String, message: String, attachments: [[String: Any]]? = nil) async -> String? {
        guard let ws = webSocketTask else { return nil }

        let requestId = UUID().uuidString
        let idempotencyKey = UUID().uuidString

        var params: [String: Any] = [
            "sessionKey": sessionKey,
            "idempotencyKey": idempotencyKey,
            "message": message
        ]
        if let attachments = attachments, !attachments.isEmpty {
            params["attachments"] = attachments
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
            return nil
        }

        gwLog.info("chatSend: JSON size = \(jsonString.count) bytes, attachments = \(attachments?.count ?? 0)")

        // Use a separate continuation map for chat.send responses to extract runId
        let runId: String? = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            responseLock.lock()
            pendingChatSendResponses[requestId] = continuation
            responseLock.unlock()

            ws.send(.string(jsonString)) { [weak self] error in
                if let error = error {
                    gwLog.error("chatSend: WebSocket send error: \(error.localizedDescription)")
                    self?.responseLock.lock()
                    if let cont = self?.pendingChatSendResponses.removeValue(forKey: requestId) {
                        self?.responseLock.unlock()
                        cont.resume(returning: nil)
                    } else {
                        self?.responseLock.unlock()
                    }
                } else {
                    gwLog.info("chatSend: WebSocket send succeeded")
                }
            }

            // Timeout after 10 seconds for the send acknowledgement
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.responseLock.lock()
                if let cont = self?.pendingChatSendResponses.removeValue(forKey: requestId) {
                    self?.responseLock.unlock()
                    cont.resume(returning: nil)
                } else {
                    self?.responseLock.unlock()
                }
            }
        }

        return runId
    }

    /// Subscribe to chat events. Returns an AsyncStream that yields `GatewayChatEvent` values.
    /// The caller should filter events by runId as needed.
    func subscribeToEvents(subscriberId: String) -> AsyncStream<GatewayChatEvent> {
        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.eventLock.lock()
                self?.eventContinuations.removeValue(forKey: subscriberId)
                self?.eventLock.unlock()
            }
            eventLock.lock()
            eventContinuations[subscriberId] = continuation
            eventLock.unlock()
        }
    }

    /// Remove a subscriber and terminate its event stream.
    func unsubscribe(subscriberId: String) {
        eventLock.lock()
        let continuation = eventContinuations.removeValue(forKey: subscriberId)
        eventLock.unlock()
        continuation?.finish()
    }

    /// Fetch the last assistant message from chat history for a given session.
    /// Used as a fallback when the final event has no message content.
    func fetchLastAssistantMessage(sessionKey: String) async -> String? {
        guard let ws = webSocketTask else { return nil }

        let requestId = UUID().uuidString
        let payload: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "chat.history",
            "params": [
                "sessionKey": sessionKey,
                "limit": 5
            ] as [String: Any]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Reuse pendingChatSendResponses to get the full response payload
        let result: String? = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
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

        return result
    }

    // MARK: - Connection Management

    private func establishConnection() {
        guard !isIntentionalDisconnect else { return }

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

        let session = URLSession(configuration: .default, delegate: delegateHandler, delegateQueue: nil)
        self.urlSession = session

        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        listenForMessages()
    }

    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

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
                // Continue listening
                self.listenForMessages()

            case .failure:
                DispatchQueue.main.async { self.isConnected = false }
                // Only reconnect if socket wasn't already cleaned up by auth failure handler
                guard self.webSocketTask != nil else { return }
                self.scheduleReconnect()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Track that the WebSocket is alive (tick, chat, heartbeat — any message counts)
        lastMessageReceivedAt = Date()

        let type = json["type"] as? String

        if type == "event", let event = json["event"] as? String, event == "connect.challenge" {
            // Respond with connect request
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

        if type == "res" {
            if let id = json["id"] as? String {
                // Check if there is a pending chat.send request (returns runId)
                responseLock.lock()
                let chatSendCont = pendingChatSendResponses.removeValue(forKey: id)
                responseLock.unlock()

                if let chatSendCont = chatSendCont {
                    let isError = json["error"] != nil
                    if isError {
                        gwLog.error("chatSend response ERROR: \(String(describing: json["error"]))")
                    }
                    if !isError, let payloadDict = json["payload"] as? [String: Any],
                       let runId = payloadDict["runId"] as? String {
                        chatSendCont.resume(returning: runId)
                    } else {
                        chatSendCont.resume(returning: nil)
                    }
                    return
                }

                // Check if there is a pending chat.history request (returns last assistant text)
                responseLock.lock()
                let chatHistoryCont = pendingChatHistoryResponses.removeValue(forKey: id)
                responseLock.unlock()

                if let chatHistoryCont = chatHistoryCont {
                    let isError = json["error"] != nil
                    if !isError, let payloadDict = json["payload"] as? [String: Any],
                       let messages = payloadDict["messages"] as? [[String: Any]] {
                        // Find the last assistant message
                        let lastAssistant = messages.last(where: { ($0["role"] as? String) == "assistant" })
                        if let lastAssistant = lastAssistant {
                            let text = self.extractTextFromMessage(lastAssistant)
                            chatHistoryCont.resume(returning: text.isEmpty ? nil : text)
                        } else {
                            chatHistoryCont.resume(returning: nil)
                        }
                    } else {
                        chatHistoryCont.resume(returning: nil)
                    }
                    return
                }

                // Check if there is a pending Bool request (abort, etc.)
                responseLock.lock()
                let continuation = pendingResponses.removeValue(forKey: id)
                responseLock.unlock()

                if let continuation = continuation {
                    let isError = json["error"] != nil
                    continuation.resume(returning: !isError)
                    return
                }
            }

            // No pending response matched — treat as connect ack or connect error
            let isError = json["error"] != nil
            if !isError {
                gwLog.info("Gateway connected successfully")
                DispatchQueue.main.async {
                    self.isConnected = true
                    self.reconnectAttempt = 0
                }
            } else {
                // Connect auth failed (e.g. stale token after gateway restart).
                // Close this dead socket and reconnect with fresh credentials.
                gwLog.error("Gateway connect auth failed: \(String(describing: json["error"])). Will reconnect with fresh credentials.")
                self.webSocketTask?.cancel(with: .goingAway, reason: nil)
                self.webSocketTask = nil
                self.urlSession?.invalidateAndCancel()
                self.urlSession = nil
                DispatchQueue.main.async { self.isConnected = false }
                self.scheduleReconnect()
            }
        }
    }

    private func sendConnectRequest() {
        let requestId = UUID().uuidString
        let instanceId = UUID().uuidString
        let locale = Locale.current.language.languageCode?.identifier ?? "en"

        let payload: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "connect",
            "params": [
                "minProtocol": 3,
                "maxProtocol": 3,
                "client": [
                    "id": "openclaw-macos",
                    "version": "1.1.16",
                    "platform": "macos",
                    "mode": "webchat",
                    "instanceId": instanceId
                ],
                "role": "operator",
                "scopes": ["operator.admin", "operator.approvals", "operator.pairing"],
                "caps": [] as [String],
                "auth": [
                    "token": authToken
                ],
                "locale": locale
            ] as [String: Any]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }

        webSocketTask?.send(.string(jsonString)) { [weak self] error in
            if error != nil {
                self?.scheduleReconnect()
            }
        }
    }

    private func scheduleReconnect() {
        guard !isIntentionalDisconnect else { return }

        // Finish all active event streams so consumers don't hang forever
        eventLock.lock()
        let activeContinuations = eventContinuations
        eventContinuations.removeAll()
        eventLock.unlock()
        for (_, continuation) in activeContinuations {
            continuation.finish()
        }

        reconnectAttempt += 1
        // Exponential backoff: 1s, 2s, 4s, 8s, capped at maxReconnectDelay
        let delay = min(pow(2.0, Double(reconnectAttempt - 1)), maxReconnectDelay)

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.isIntentionalDisconnect else { return }
            self.webSocketTask?.cancel(with: .goingAway, reason: nil)
            self.webSocketTask = nil
            self.urlSession?.invalidateAndCancel()
            self.urlSession = nil
            self.establishConnection()
        }
    }

    // MARK: - Chat Event Helpers

    private func handleChatEventPayload(_ payload: [String: Any]) {
        guard let state = payload["state"] as? String,
              let runId = payload["runId"] as? String ?? payload["idempotencyKey"] as? String,
              let sessionKey = payload["sessionKey"] as? String else {
            gwLog.warning("chat event missing required fields: state/runId/sessionKey")
            return
        }

        let event: GatewayChatEvent
        switch state {
        case "delta":
            let text = extractTextFromMessage(payload["message"])
            gwLog.debug("chat event: state=delta, runId=\(runId), textLen=\(text.count), subscribers=\(self.eventContinuations.count)")
            event = .delta(runId: runId, sessionKey: sessionKey, text: text)
        case "final":
            let text = extractTextFromMessage(payload["message"])
            let hasMessage = payload["message"] != nil
            gwLog.info("chat event: state=final, runId=\(runId), textLen=\(text.count), hasMessage=\(hasMessage), subscribers=\(self.eventContinuations.count)")
            event = .final_(runId: runId, sessionKey: sessionKey, text: text)
        case "aborted":
            event = .aborted(runId: runId, sessionKey: sessionKey)
        case "error":
            var message = ""

            // Try to extract from payload.message.errorMessage (gateway error response format)
            if let msgDict = payload["message"] as? [String: Any],
               let errorMsg = msgDict["errorMessage"] as? String {
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
        eventLock.lock()
        let continuations = Array(eventContinuations.values)
        eventLock.unlock()

        // Broadcast event to all active subscribers
        // Using DispatchQueue to avoid blocking if a subscriber is slow to consume
        DispatchQueue.global().async { [continuations] in
            for continuation in continuations {
                continuation.yield(event)
            }
        }
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
