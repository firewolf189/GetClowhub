import Foundation
import Combine

/// Owns the chat send/cancel/stream pipeline and chat-local runtime
/// dependencies (gateway transport handle, run coordinator, attachments,
/// message maps). DashboardViewModel remains the composition root and
/// attaches itself so the pipeline can reach sessions, composer, and UI
/// toasts without becoming a second god object.
@MainActor
final class ChatViewModel: ObservableObject {
    let runtimeState: ChatRuntimeState
    let taskState: TaskActivityState
    let chatRunLifecycleCoordinator: ChatRunLifecycleCoordinator
    let attachmentProcessor: AttachmentProcessor
    private var injectedGateway: GatewayClient?
    private(set) weak var dashboard: DashboardViewModel?

    var gatewayClient: GatewayClient {
        guard let injectedGateway else {
            preconditionFailure("ChatViewModel.attach(dashboard:) must run before the chat pipeline is used")
        }
        return injectedGateway
    }

    init(
        runtimeState: ChatRuntimeState? = nil,
        taskState: TaskActivityState? = nil,
        chatRunLifecycleCoordinator: ChatRunLifecycleCoordinator? = nil,
        attachmentProcessor: AttachmentProcessor? = nil
    ) {
        self.runtimeState = runtimeState ?? ChatRuntimeState()
        self.taskState = taskState ?? TaskActivityState()
        self.chatRunLifecycleCoordinator = chatRunLifecycleCoordinator ?? ChatRunLifecycleCoordinator()
        self.attachmentProcessor = attachmentProcessor ?? AttachmentProcessor()
    }

    func attach(dashboard: DashboardViewModel) {
        self.dashboard = dashboard
        injectedGateway = dashboard.gatewayClient
    }

    fileprivate var host: DashboardViewModel {
        guard let dashboard else {
            preconditionFailure("ChatViewModel.attach(dashboard:) must run before the chat pipeline is used")
        }
        return dashboard
    }
}

extension ChatViewModel {
    var collabViewModel: CollabViewModel? { host.collabViewModel }

    var selectedAgentId: String {
        get { host.selectedAgentId }
        set { host.selectedAgentId = newValue }
    }

    var selectedSessionIdByAgent: [String: UUID] { host.selectedSessionIdByAgent }
    var availableAgents: [AgentOption] { host.availableAgents }
    var pendingSessionMetadataByAgent: [String: ChatSessionMetadata] { host.pendingSessionMetadataByAgent }
    var projectsById: [String: ProjectRecord] { host.projectsById }
    var activeProjectIdByAgent: [String: String?] { host.activeProjectIdByAgent }
    var backgroundTaskIds: Set<UUID> { taskState.backgroundTaskIds }
    var chatSessionStore: ChatSessionStore { host.chatSessionStore }
    var chatState: ChatRuntimeState { runtimeState }

    var isSendingMessage: Bool {
        get { taskState.isSendingMessage }
        set { taskState.isSendingMessage = newValue }
    }

    var chatMessagesByAgent: [String: [ChatMessage]] {
        get { runtimeState.chatMessagesByAgent }
        set { runtimeState.chatMessagesByAgent = newValue }
    }

    var chatMessages: [ChatMessage] {
        get { runtimeState.chatMessages(for: selectedAgentId) }
        set { runtimeState.setChatMessages(newValue, for: selectedAgentId) }
    }

    var chatMessagesByInactiveSession: [UUID: [ChatMessage]] {
        get { runtimeState.chatMessagesByInactiveSession }
        set { runtimeState.chatMessagesByInactiveSession = newValue }
    }

    var appliedSessionModels: [String: String] {
        get { host.appliedSessionModels }
        set { host.appliedSessionModels = newValue }
    }

    var appliedSessionThinking: [String: ThinkingEffort] {
        get { host.appliedSessionThinking }
        set { host.appliedSessionThinking = newValue }
    }

    var activeComposerModel: String { host.activeComposerModel }

    var activeComposerEffort: ThinkingEffort {
        get { host.activeComposerEffort }
        set { host.activeComposerEffort = newValue }
    }

    func logChat(_ message: String) { host.logChat(message) }
    func showErrorMessage(_ message: String) { host.showErrorMessage(message) }
    func showSuccessMessage(_ message: String) { host.showSuccessMessage(message) }
    func ensureActiveSessionId(forAgent agentId: String, seedMessages: [ChatMessage] = []) -> UUID {
        host.ensureActiveSessionId(forAgent: agentId, seedMessages: seedMessages)
    }

    /// Seconds an in-flight foreground task spins before it auto-flips to
    /// background (unlocking the input). Off by default; a positive
    /// UserDefaults value under `chat.autoBackgroundAfterSeconds` opts in.
    var autoBackgroundAfterSeconds: Int? {
        let key = "chat.autoBackgroundAfterSeconds"
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        let val = UserDefaults.standard.integer(forKey: key)
        return val > 0 ? val : nil
    }

    /// Recompute `isSendingMessage` from the currently visible session.
    /// Safe before `attach`: Dashboard's init sink can fire while `dashboard`
    /// is still nil, in which case there is no visible session lock.
    func recomputeIsSendingMessage() {
        guard let dashboard else {
            isSendingMessage = false
            return
        }
        guard let sid = dashboard.selectedSessionIdByAgent[dashboard.selectedAgentId] else {
            isSendingMessage = false
            return
        }
        isSendingMessage = taskState.hasForegroundTask(inSession: sid)
    }

    func updateActiveStreamState(
        msgId: UUID,
        visibleDraftText: String,
        activityEvents: [ChatActivityEvent]
    ) {
        runtimeState.updateActiveStreamState(
            messageId: msgId,
            visibleDraftText: visibleDraftText,
            activityEvents: activityEvents
        )
    }

    func clearActiveStreamState(_ msgId: UUID) {
        runtimeState.clearActiveStreamState(msgId)
    }

    /// Single-point removal of runtime presentation plus the typed run state.
    func clearTaskTracking(_ msgId: UUID) {
        chatRunLifecycleCoordinator.finish(messageId: msgId)
        clearActiveStreamState(msgId)
        taskState.removeRun(messageId: msgId)
        recomputeIsSendingMessage()
    }

    func scheduleAutomaticBackground(for messageId: UUID) {
        guard let run = taskState.run(for: messageId),
              let seconds = autoBackgroundAfterSeconds else {
            chatRunLifecycleCoordinator.cancelAutomaticBackground(messageId: messageId)
            return
        }
        let deadline = run.startedAt.addingTimeInterval(TimeInterval(seconds))
        chatRunLifecycleCoordinator.scheduleAutomaticBackground(
            messageId: messageId,
            deadline: deadline
        ) { [weak self] in
            self?.moveTaskToBackground(messageId)
        }
    }

    /// Look up a message by id in whichever bucket currently holds it —
    /// the active per-agent map, or the inactive-sessions map for tasks
    /// whose owning session the user has navigated away from.
    func findMessage(byId msgId: UUID) -> ChatMessage? {
        for messages in chatMessagesByAgent.values {
            if let msg = messages.first(where: { $0.id == msgId }) {
                return msg
            }
        }
        if let sessionId = taskState.run(for: msgId)?.identity.sessionId,
           let msg = chatMessagesByInactiveSession[sessionId]?.first(where: { $0.id == msgId }) {
            return msg
        }
        return nil
    }

    /// Retry the shared gateway transport after bounded automatic recovery
    /// was exhausted. The clicked row only authorizes the command; every
    /// unresolved run transitions together and reconciles after one connect.
    func retryChatConnection(for messageId: UUID) {
        guard let run = taskState.run(for: messageId) else { return }
        switch run.phase {
        case .recoveryUnavailable:
            guard taskState.requestRunReconciliationRetry(messageId: messageId) else { return }
            scheduleChatRunReconciliation(messageId: messageId)

        case .connectionLost:
            guard taskState.requestTransportRecoveryRetry() > 0 else { return }
            gatewayClient.connect()

        default:
            return
        }
    }

    /// Applies transport lifecycle to active chat runs. Dashboard owns the
    /// gateway-wide observers and forwards the resulting state here.
    /// Safe before `attach`: the connection-state sink fires `.disconnected`
    /// immediately, and that branch does not touch the injected gateway.
    func handleGatewayConnectionState(_ state: GatewayConnectionState) {
        switch state {
        case .connected:
            taskState.applyRunEventToActiveRuns(.transportReconnected)
            let conversationRunIds: [UUID] = taskState.runsByMessageId.values.compactMap { run in
                guard !run.phase.isTerminal,
                      run.executionKind == .conversation,
                      !gatewayClient.hasEventSubscription(
                          subscriberId: run.identity.messageId.uuidString
                      ) else { return nil }
                return run.identity.messageId
            }
            for messageId in conversationRunIds {
                scheduleChatRunReconciliation(messageId: messageId)
            }

        case .reconnecting(let attempt, let maximum):
            taskState.applyRunEventToActiveRuns(
                .transportReconnecting(attempt: attempt, maxAttempts: maximum)
            )

        case .recoveryExhausted(let attempts):
            taskState.applyRunEventToActiveRuns(.recoveryExhausted(attempts: attempts))

        case .disconnected:
            guard taskState.runsByMessageId.values.contains(where: { !$0.phase.isTerminal }) else {
                return
            }
            taskState.applyRunEventToActiveRuns(.recoveryExhausted(attempts: 0))

        case .connecting:
            break
        }
    }

    static func elapsedMillisecondsText(since start: ContinuousClock.Instant) -> String {
        let duration = start.duration(to: ContinuousClock.now)
        let components = duration.components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.1f", milliseconds)
    }
}
