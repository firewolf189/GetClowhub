import Foundation
import Combine
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import os.log

private let chatLog = Logger(subsystem: "com.openclaw.installer", category: "Chat")
private let sessionSwitchPerfLog = Logger(subsystem: "com.openclaw.installer", category: "SessionSwitchPerformance")

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var openclawService: OpenClawService
    @Published var settings: AppSettingsManager
    @Published var systemEnvironment: SystemEnvironment

    // Debug logging
    private let chatDebugLog = OSLog(subsystem: "com.openclaw.chat", category: "debug")
    private func logChat(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date()).suffix(12)
        let fullMsg = "[\(timestamp)] \(message)"
        print(fullMsg)
        os_log("[CHAT] %{public}@", log: chatDebugLog, type: .debug, fullMsg)
    }

    // UI State
    @Published var selectedTab: DashboardTab = .chat
    @Published var isPerformingAction = false
    @Published var showError = false
    @Published var errorMessage: String = ""
    @Published var showSuccess = false
    @Published var successMessage: String = ""

    // Configuration
    @Published var editedPort: String = ""
    @Published var editedAuthToken: String = ""
    @Published var editedModelBaseUrl: String = ""
    @Published var editedModelApiKey: String = ""

    // Provider Preset
    let presetManager = ProviderPresetManager()
    @Published var availableProviders: [ProviderPreset] = []
    @Published var editedSelectedProviderKey: String = ""
    @Published var editedProviderApi: String = "openai-completions"
    @Published var editedConfiguredModels: [PresetModel] = []
    @Published var showProviderSwitchConfirm = false
    @Published var editedActiveServiceSource: String = "custom" // "getclawhub" or "custom"
    @Published var editedGetClawHubApiKey: String = "" // Editable API key for GetClawHub
    @Published var isFetchingProviderModels = false
    @Published var providerModelFetchMessage: String = ""
    var pendingProviderKey: String = ""
    private let providerModelFetchService = ProviderModelFetchService()
    private let attachmentProcessor = AttachmentProcessor()

    /// Computed: true when any edited field differs from saved settings.
    /// Works because editedXxx are @Published — any change triggers SwiftUI re-render,
    /// which re-evaluates this property.
    var hasUnsavedChanges: Bool {
        let s = settings.settings
        return editedPort != String(s.gatewayPort)
            || editedAuthToken != s.gatewayAuthToken
            || editedModelBaseUrl != s.modelBaseUrl
            || editedModelApiKey != s.modelApiKey
            || editedSelectedProviderKey != s.selectedProviderKey
            || editedProviderApi != s.providerApi
            || editedConfiguredModels != s.configuredModels
            || editedActiveServiceSource != s.activeServiceSource
    }

    // Gateway logs
    @Published var gatewayLogs: [String] = []
    @Published var isLoadingLogs = false

    // Collab
    @Published var collabViewModel: CollabViewModel?
    @Published var showCollabPanel = false
    @Published var collabPanelCollapsed = false

    // Budget
    @Published var budgetService = BudgetService()
    @Published var budgetSnapshots: [BudgetSnapshot] = []
    @Published var budgetRules: [BudgetRule] = []
    @Published var isLoadingBudgets = false

    // Diagnostics
    @Published var diagnosticReport: String = ""
    @Published var showDiagnostics = false
    private var logRefreshTimer: Timer?
    var budgetMonitorTimer: Timer?  // internal: used by BudgetManagement extension (P1.4)

    private let _commandExecutor: CommandExecutor
    private let projectWorkspaceService = ProjectWorkspaceService()
    private var cancellables = Set<AnyCancellable>()

    #if REQUIRE_LOGIN
    // MembershipManager reference for GetClawHub save logic
    weak var membershipManager: MembershipManager?
    #endif
    // Gateway WebSocket client for chat
    @Published var gatewayClient: GatewayClient

    // Maps msgId → runId for active WebSocket chat runs
    private var activeChatRuns: [UUID: String] = [:]
    private var taskSessionKeyOverride: [UUID: String] = [:]

    init(
        openclawService: OpenClawService,
        settings: AppSettingsManager,
        systemEnvironment: SystemEnvironment,
        commandExecutor: CommandExecutor
    ) {
        self.openclawService = openclawService
        self.settings = settings
        self.systemEnvironment = systemEnvironment
        self._commandExecutor = commandExecutor

        // Initialize gateway WebSocket client for chat abort
        self.gatewayClient = GatewayClient(
            port: settings.settings.gatewayPort,
            authToken: settings.settings.gatewayAuthToken,
            credentialsProvider: {
                // Must equal `AppSettings.gatewayPort` default — a drift here lets the
                // WS connect a dead port while the UI still shows the service running.
                let defaultPort = 18789
                let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
                let configPath = "\(homeDir)/.openclaw/openclaw.json"
                guard let data = FileManager.default.contents(atPath: configPath),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let gateway = dict["gateway"] as? [String: Any] else {
                    return (port: defaultPort, authToken: "")
                }
                let port = gateway["port"] as? Int ?? defaultPort
                let token = (gateway["auth"] as? [String: Any])?["token"] as? String ?? ""
                return (port: port, authToken: token)
            }
        )

        // Initialize edited values from real config
        self.editedPort = String(settings.settings.gatewayPort)
        self.editedAuthToken = settings.settings.gatewayAuthToken
        self.editedModelBaseUrl = settings.settings.modelBaseUrl
        self.editedModelApiKey = settings.settings.modelApiKey
        self.editedSelectedProviderKey = settings.settings.selectedProviderKey
        self.editedProviderApi = settings.settings.providerApi
        self.editedConfiguredModels = settings.settings.configuredModels
        self.editedActiveServiceSource = settings.settings.activeServiceSource

        // Load available providers from preset (exclude getclawhub — it has its own section)
        self.availableProviders = presetManager.loadPresets().filter { $0.key != "getclawhub" }

        // If no config file exists, populate from preset defaults
        if editedModelBaseUrl.isEmpty,
           let preset = availableProviders.first(where: { $0.key == editedSelectedProviderKey }) {
            editedModelBaseUrl = preset.baseUrl
            editedProviderApi = preset.api
            editedConfiguredModels = preset.models
        }
        refreshAvailableModelsForCurrentProvider()

        // Forward nested ObservableObject changes so SwiftUI views re-render
        // (@Published on reference types only fires when the reference is replaced,
        //  not when the inner object's properties change)
        openclawService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Initialize budget rules mirror from BudgetService
        self.budgetRules = budgetService.config.rules

        // Connect gateway WebSocket when service is running
        if openclawService.status == .running {
            gatewayClient.connect()
        }

        // Auto-connect/disconnect gateway WS based on service status
        openclawService.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                if status == .running && !self.gatewayClient.isConnected {
                    self.gatewayClient.connect()
                } else if status != .running {
                    self.gatewayClient.disconnect()
                }
            }
            .store(in: &cancellables)

        // ─── Chat session persistence ───
        loadProjectRegistry()
        // 1. Build the metadata mirror from disk so the sidebar can render
        //    history immediately, before the user ever opens chat.
        rebuildSessionsMirror()
        // 2. For every agent that already has stored sessions, restore the
        //    most-recent one into chatMessagesByAgent so reopening chat shows
        //    the previous conversation rather than an empty state.
        restoreActiveSessionsFromStore()
        // 3. Watch chatMessagesByAgent and persist the in-memory view back to
        //    the active session on disk — debounced so a streamed assistant
        //    reply collapses into one disk write.
        $chatMessagesByAgent
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] dict in
                self?.persistChangedSessions(from: dict)
            }
            .store(in: &cancellables)
        // 4. Mirror updates from the store back into the published sidebar
        //    list. The store's debounced writes (assistant streaming, lazy
        //    save of newly-created sessions) land asynchronously; without
        //    this sink the sidebar would lag behind disk until the next
        //    explicit rebuild.
        chatSessionStore.$index
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildSessionsMirror()
            }
            .store(in: &cancellables)
        // 5. Recompute `isSendingMessage` whenever the user switches agent
        //    or the foreground task set changes, AND lazy-load that agent's
        //    most-recent session messages if `restoreActiveSessionsFromStore`
        //    skipped it at startup (only the initially-visible agent gets
        //    eager-loaded — every other agent's messages are parsed the
        //    first time the user switches into it).
        //
        //    Switching session is handled inline in `switchSession` /
        //    `createNewSession` / `promoteNextSession` (since those mutate
        //    `selectedSessionIdByAgent` dict in-place — SwiftUI doesn't
        //    publish per-key dict mutations reliably).
        Publishers.CombineLatest($selectedAgentId, $foregroundTaskIds)
            .receive(on: RunLoop.main)
            .sink { [weak self] agentId, _ in
                guard let self = self else { return }
                self.ensureMessagesLoaded(forAgent: agentId)
                self.recomputeIsSendingMessage()
            }
            .store(in: &cancellables)
        // 6. Persist updates landing in inactive sessions (background
        //    streaming). Same debounce window as the active sink so
        //    streaming completions in a hidden session still hit disk —
        //    otherwise the user sees the old state until next switch.
        $chatMessagesByInactiveSession
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] dict in
                self?.persistInactiveSessions(from: dict)
            }
            .store(in: &cancellables)
        // 7. App Nap suppression — when ANY task is in flight, mark the
        //    process as doing user-initiated work so macOS doesn't
        //    coalesce our timers / throttle networking / defer
        //    callbacks. Without this, hiding the app while a long task
        //    streams causes:
        //      - ThinkingIndicator timer ticks merged to ~1 min intervals
        //      - timeoutTask poll skipped (10s → arbitrary)
        //      - stream callback delivery delayed when receiving deltas
        //    Energy cost is the trade-off — only held while tasks are
        //    actually running, released the moment all tasks finish.
        Publishers.CombineLatest($foregroundTaskIds, $backgroundTaskIds)
            .map { !$0.isEmpty || !$1.isEmpty }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] anyActive in
                self?.updateActivityAssertion(active: anyActive)
            }
            .store(in: &cancellables)
        // 8. macOS system sleep / wake observers. When the user closes
        //    the lid or the Mac sleeps, all timers and network callbacks
        //    are frozen — including our WS receive callback. On wake,
        //    the WS may have been silently closed by the gateway side
        //    (idle timeout) but the client doesn't immediately notice
        //    until the next send fails. We pre-empt this by forcing a
        //    reconnect on wake, so any in-flight task gets a fresh
        //    eventStream as fast as possible (and our recover-via-
        //    history logic can kick in if the run completed during
        //    sleep).
        let nc = NSWorkspace.shared.notificationCenter
        sleepObserver = nc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemWillSleep()
        }
        wakeObserver = nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemDidWake()
        }

        // 9. Recover any in-flight chat runs left over from a previous
        //    launch (app crash / force-quit). Fires in the background
        //    once WS connects, walks the persisted run registry, and
        //    pulls completed replies via chat.history.
        recoverInFlightRunsOnLaunch()
    }

    /// Sleep/wake observer tokens — removed in deinit to avoid leaking
    /// the listener after the view model is gone. macOS keeps strong
    /// refs to the observer block so even without weak self this would
    /// hold the VM alive forever.
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    private func handleSystemWillSleep() {
        chatLog.info("System will sleep — flushing in-flight task state")
        // Persist any in-memory updates so a worst-case "lid closed +
        // Mac unplugged" survives. The persist sinks are debounced
        // (500ms), so we explicitly walk the in-flight sessions and
        // flush them synchronously through ChatSessionStore's flush.
        for (agentId, _) in chatMessagesByAgent {
            flushActiveSession(forAgent: agentId)
        }
    }

    private func handleSystemDidWake() {
        chatLog.info("System did wake — forcing WS reconnect for in-flight tasks")
        // If any task was in flight when we slept, the WS receive
        // callback for it is almost certainly stuck on a dead socket
        // (gateway side closed during sleep). Forcing a teardown +
        // reconnect makes scheduleReconnect run immediately rather
        // than waiting for the OS to surface the I/O error, which
        // can take 30+ seconds in practice.
        if !foregroundTaskIds.isEmpty || !backgroundTaskIds.isEmpty {
            gatewayClient.disconnect()
            gatewayClient.connect()
        }
    }

    // MARK: - In-Flight Run Persistence

    /// Persisted record of an in-flight chat run, written on chat.send
    /// success and removed on terminal event (completed/cancelled/error/
    /// timeout) or stream cleanup. Survives app crash / force-quit so
    /// the next launch can attempt recovery via `chat.history`.
    ///
    /// Without this, killing the app mid-task leaves the placeholder
    /// stuck at `.loading` or `.background` on disk forever, with no
    /// way to reattach to the gateway-side run (the runId is gone from
    /// memory). The user sees a permanent "Thinking…" / "Running in
    /// background…" UI for a task that's actually long since finished.
    private struct PersistedInFlightRun: Codable {
        let runId: String
        let sessionKey: String
        let msgId: UUID
        let sessionId: UUID
        let agentId: String
        let agentEmoji: String?
        let startedAt: Date
    }

    private var inFlightRunsFileURL: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let bundleId = Bundle.main.bundleIdentifier ?? "com.cc.OpenClawInstaller"
        let dir = appSupport
            .appendingPathComponent(bundleId)
            .appendingPathComponent("chat-sessions")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("in-flight-runs.json")
    }

    private func readInFlightRuns() -> [PersistedInFlightRun] {
        guard let data = try? Data(contentsOf: inFlightRunsFileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PersistedInFlightRun].self, from: data)) ?? []
    }

    private func writeInFlightRuns(_ runs: [PersistedInFlightRun]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(runs) {
            try? data.write(to: inFlightRunsFileURL, options: .atomic)
        }
    }

    /// Append a fresh in-flight record. Called from `sendChatMessage`
    /// right after `chat.send` returns a runId.
    private func registerInFlightRun(runId: String, sessionKey: String, msgId: UUID,
                                      sessionId: UUID, agentId: String, agentEmoji: String?) {
        var runs = readInFlightRuns()
        runs.append(PersistedInFlightRun(
            runId: runId, sessionKey: sessionKey, msgId: msgId,
            sessionId: sessionId, agentId: agentId, agentEmoji: agentEmoji,
            startedAt: Date()
        ))
        writeInFlightRuns(runs)
    }

    /// Remove an in-flight record after the task terminates (any reason
    /// — completed, cancelled, errored, timed out, or stream cleanup).
    private func unregisterInFlightRun(msgId: UUID) {
        var runs = readInFlightRuns()
        runs.removeAll { $0.msgId == msgId }
        writeInFlightRuns(runs)
    }

    /// On app launch, look at leftover entries in `in-flight-runs.json`
    /// — they represent tasks the user started but the app died before
    /// they finished. For each, ask the gateway for the session's last
    /// assistant message (via `chat.history`); if found, update the
    /// disk-side placeholder to `.completed` so the user sees the
    /// recovered reply when they next open the session. If history
    /// has nothing, mark `.timedOut` with an explanatory note.
    ///
    /// Runs as a background Task after WS connects (waits up to 30s).
    /// Doesn't block init or the chat UI.
    private func recoverInFlightRunsOnLaunch() {
        let allEntries = readInFlightRuns()
        guard !allEntries.isEmpty else { return }

        // Freshness guard: anything older than 1 hour is presumed to
        // be either truly lost (gateway no longer running it / no
        // longer in history) or worse — its sessionKey may have been
        // reused since by other channels (DingTalk / Weixin share the
        // same `agent:X:<sid>` namespace). Recovering against a stale
        // entry would attribute someone ELSE's reply to our crashed
        // task. Safer to just mark these timed out and let the user
        // re-send.
        let now = Date()
        let cutoff = now.addingTimeInterval(-3600)
        var fresh: [PersistedInFlightRun] = []
        var stale: [PersistedInFlightRun] = []
        for entry in allEntries {
            if entry.startedAt >= cutoff {
                fresh.append(entry)
            } else {
                stale.append(entry)
            }
        }

        // Multi-entry-per-session guard: if the user fired off N sends
        // in the same session before the crash, fetchLastAssistantMessage
        // returns ONE reply (the most recent one gateway completed) but
        // we'd otherwise attribute it to all N placeholders. Recover
        // only the LATEST entry per sessionId; mark earlier ones timed
        // out (their reply, if any, is no longer addressable from
        // history without per-runId metadata).
        var latestBySession: [UUID: PersistedInFlightRun] = [:]
        var supersededByLater: [PersistedInFlightRun] = []
        for entry in fresh {
            if let existing = latestBySession[entry.sessionId] {
                if entry.startedAt > existing.startedAt {
                    supersededByLater.append(existing)
                    latestBySession[entry.sessionId] = entry
                } else {
                    supersededByLater.append(entry)
                }
            } else {
                latestBySession[entry.sessionId] = entry
            }
        }
        let recoverable = Array(latestBySession.values)
        let unrecoverable = stale + supersededByLater

        chatLog.info("In-flight recovery: \(recoverable.count) recoverable, \(unrecoverable.count) marked timed-out (\(stale.count) stale + \(supersededByLater.count) superseded)")

        Task { [weak self] in
            guard let self = self else { return }

            // Stale + superseded: no recovery attempt, straight to timedOut.
            for entry in unrecoverable {
                await self.markEntryTimedOut(entry, reason: .stale)
            }

            // Wait for WS for the recoverable batch.
            let deadline = Date().addingTimeInterval(30)
            while !self.gatewayClient.isConnected && Date() < deadline {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            for entry in recoverable {
                await self.recoverSingleInFlightRun(entry)
            }

            // Clear the file — recovered or not, we tried.
            await MainActor.run {
                self.writeInFlightRuns([])
            }
        }
    }

    private enum RecoveryFailReason {
        case stale            // > 1h old, didn't try history
        case superseded       // newer entry exists for same session
        case noHistory        // history fetch returned nothing useful
    }

    private func markEntryTimedOut(_ entry: PersistedInFlightRun, reason: RecoveryFailReason) async {
        await MainActor.run {
            guard var session = self.chatSessionStore.loadSession(id: entry.sessionId),
                  let idx = session.messages.firstIndex(where: { $0.id == entry.msgId }) else {
                return
            }
            let msg = session.messages[idx]
            guard msg.taskStatus == .loading || msg.taskStatus == .background else { return }

            let noteText: String
            switch reason {
            case .stale:
                noteText = "Task started over an hour ago and result is no longer recoverable. Please re-send."
            case .superseded:
                noteText = "A more recent task in the same session was recovered instead. Please re-send if needed."
            case .noHistory:
                noteText = "Task was interrupted by app restart. Result could not be recovered."
            }
            let note = String(localized: String.LocalizationValue(noteText), bundle: LanguageManager.shared.localizedBundle)
            let content = msg.content.isEmpty
                ? note
                : msg.content + "\n\n---\n> ⚠️ " + note

            session.messages[idx] = ChatMessage(
                role: .assistant,
                content: content,
                agentId: msg.agentId,
                agentEmoji: msg.agentEmoji,
                taskStatus: .timedOut,
                id: entry.msgId,
                timestamp: msg.timestamp
            )
            session.updatedAt = Date()
            self.chatSessionStore.saveSession(session)

            if self.selectedSessionIdByAgent[entry.agentId] == entry.sessionId,
               var messages = self.chatMessagesByAgent[entry.agentId],
               let memIdx = messages.firstIndex(where: { $0.id == entry.msgId }) {
                messages[memIdx] = session.messages[idx]
                self.chatMessagesByAgent[entry.agentId] = messages
            }
        }
    }

    private func recoverSingleInFlightRun(_ entry: PersistedInFlightRun) async {
        guard var session = chatSessionStore.loadSession(id: entry.sessionId),
              let idx = session.messages.firstIndex(where: { $0.id == entry.msgId }) else {
            chatLog.warning("recovery: session \(entry.sessionId) or msg \(entry.msgId) not found, skipping")
            return
        }

        let msg = session.messages[idx]
        // Only touch placeholders that are still in non-terminal state.
        // If the user already saw it complete in a previous session
        // (somehow), don't overwrite.
        guard msg.taskStatus == .loading || msg.taskStatus == .background else {
            return
        }

        let recovered = await gatewayClient.fetchLastAssistantMessage(sessionKey: entry.sessionKey)

        await MainActor.run {
            let newStatus: ChatMessage.TaskStatus
            let newContent: String

            if let text = recovered, !text.isEmpty, text.count > msg.content.count {
                // History has more content than the disk placeholder —
                // the run completed gateway-side while we were dead.
                newStatus = .completed
                newContent = text
                chatLog.info("recovery: session \(entry.sessionId.uuidString.prefix(8)) msg \(entry.msgId.uuidString.prefix(8)) → restored \(text.count) chars")
            } else {
                // Nothing useful — mark timed out with note so the user
                // knows the previous run was lost and can resend.
                newStatus = .timedOut
                let note = String(localized: "Task was interrupted by app restart. Result could not be recovered.",
                                  bundle: LanguageManager.shared.localizedBundle)
                newContent = msg.content.isEmpty
                    ? note
                    : msg.content + "\n\n---\n> ⚠️ " + note
                chatLog.warning("recovery: session \(entry.sessionId.uuidString.prefix(8)) msg \(entry.msgId.uuidString.prefix(8)) — no usable history, marked timed out")
            }

            session.messages[idx] = ChatMessage(
                role: .assistant,
                content: newContent,
                agentId: msg.agentId,
                agentEmoji: msg.agentEmoji,
                taskStatus: newStatus,
                id: entry.msgId,
                timestamp: msg.timestamp
            )
            session.updatedAt = Date()
            self.chatSessionStore.saveSession(session)

            // Mirror into in-memory state if this session happens to be
            // currently loaded for an agent — otherwise the user would
            // see the stale state until they switched away and back.
            if self.selectedSessionIdByAgent[entry.agentId] == entry.sessionId,
               var messages = self.chatMessagesByAgent[entry.agentId],
               let memIdx = messages.firstIndex(where: { $0.id == entry.msgId }) {
                messages[memIdx] = session.messages[idx]
                self.chatMessagesByAgent[entry.agentId] = messages
            }
        }
    }

    /// Token returned by `ProcessInfo.beginActivity`. nil when no
    /// assertion is currently held. Released via `endActivity` when the
    /// last in-flight task settles.
    private var activityToken: NSObjectProtocol?

    // MARK: - Tunable chat thresholds (UserDefaults-backed)

    /// Seconds of zero WebSocket traffic before declaring a task timed
    /// out. Default 3600 (1 hour). Override with
    /// `defaults write com.cc.OpenClawInstaller chat.inactivityTimeoutSeconds <N>`
    /// (a settings UI can come later).
    var inactivityTimeoutSeconds: TimeInterval {
        let raw = UserDefaults.standard.integer(forKey: "chat.inactivityTimeoutSeconds")
        return raw > 0 ? TimeInterval(raw) : 3600
    }

    /// Seconds an in-flight foreground task spins before the
    /// ThinkingIndicator auto-flips it to background (unlocking the input).
    /// Auto-background is OFF by default in this build: the product is a
    /// synchronous human-in-the-loop flow (generate → review → send), so a
    /// task stays foreground until it finishes or is cancelled — no
    /// auto-background, fewer multi-task edge cases. A POSITIVE UserDefaults
    /// value under `chat.autoBackgroundAfterSeconds` opts back in; 0/negative
    /// (or unset) keeps it off.
    var autoBackgroundAfterSeconds: Int? {
        let key = "chat.autoBackgroundAfterSeconds"
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        let val = UserDefaults.standard.integer(forKey: key)
        return val > 0 ? val : nil
    }

    /// Begin / end the App Nap suppression assertion based on whether
    /// any foreground or background task is in flight. Idempotent —
    /// repeated calls with the same `active` value are no-ops.
    private func updateActivityAssertion(active: Bool) {
        if active && activityToken == nil {
            // .userInitiated suppresses App Nap + timer coalescing for
            // our process without preventing system sleep (closing the
            // lid still puts the Mac to sleep — that's handled by the
            // willSleep / didWake observers separately).
            activityToken = ProcessInfo.processInfo.beginActivity(
                options: .userInitiated,
                reason: "Streaming chat response (in-flight task)"
            )
            chatLog.info("App Nap suppression engaged")
        } else if !active, let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
            chatLog.info("App Nap suppression released")
        }
    }

    /// Mirror updates from `chatMessagesByInactiveSession` to disk. Used
    /// when a streaming task completes for a session the user is not
    /// currently viewing — without this, the on-disk file stays at
    /// `.loading` (or whatever state it was in at the moment of switch)
    /// until the user navigates back.
    ///
    /// We deliberately do NOT evict entries from
    /// `chatMessagesByInactiveSession` here even when they have no more
    /// in-flight tasks. Eviction would race with `saveSessionDebounced`
    /// (it queues; the actual disk write happens later) — if the user
    /// flips back to a just-evicted session before the queued write
    /// flushes, `switchSession`'s disk-fallback path reads stale data
    /// and the assistant's reply appears to vanish. The cost of NOT
    /// evicting is one extra `[ChatMessage]` per session in memory,
    /// which is negligible; entries get reclaimed naturally when the
    /// user navigates back into the session (`switchSession`'s
    /// `removeValue(forKey:)`).
    private func persistInactiveSessions(from dict: [UUID: [ChatMessage]]) {
        for (sid, messages) in dict where !messages.isEmpty {
            // `loadSession` is now cache-backed; in the streaming-update
            // hot path it returns from memory (the cache was warmed when
            // the user opened this session originally), so this is no
            // longer a full disk parse on every debounce fire.
            guard var session = chatSessionStore.loadSession(id: sid) else { continue }
            let memMessages = Self.stripStaleLoadingPlaceholders(messages)
            // Cheap skip: if the trailing message's id+status+content-length
            // already matches what's on (cached) disk, don't queue a write.
            // Mirror of the same guard in `persistChangedSessions` — covers
            // the case where streaming has paused but the sink keeps firing
            // because of unrelated map mutations elsewhere.
            if session.messages.count == memMessages.count,
               session.messages.last?.id == memMessages.last?.id,
               session.messages.last?.taskStatus == memMessages.last?.taskStatus,
               session.messages.last?.content.count == memMessages.last?.content.count,
               Self.messagesHaveSameActivityEvents(session.messages.last, memMessages.last) {
                continue
            }
            session.messages = memMessages
            session.updatedAt = Date()
            if session.title == ChatSession.defaultTitle {
                session.title = ChatSession.deriveTitle(from: memMessages)
            }
            chatSessionStore.saveSessionDebounced(session)
        }
    }

    deinit {
        // System sleep/wake observers — must remove explicitly,
        // NSWorkspace retains the observer block. Same for App Nap
        // assertion: leaking the token leaks the assertion (system
        // would think we still have work to do).
        let nc = NSWorkspace.shared.notificationCenter
        if let sleep = sleepObserver { nc.removeObserver(sleep) }
        if let wake = wakeObserver { nc.removeObserver(wake) }
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
        }
        Task { @MainActor in
            openclawService.stopMonitoring()
            gatewayClient.disconnect()
            logRefreshTimer?.invalidate()
            logRefreshTimer = nil
        }
    }

    // MARK: - Public Access to CommandExecutor

    var commandExecutor: CommandExecutor {
        self._commandExecutor
    }

    // Plugins
    @Published var plugins: [PluginInfo] = []
    @Published var isLoadingPlugins = false
    @Published var pluginCatalog: [PluginCatalogItem] = []
    @Published var isLoadingPluginCatalog = false
    @Published var installingCatalogPluginName: String?
    @Published var pluginCatalogError: String?

    var hasLoadedPluginCatalog = false  // internal: used by the PluginManagement extension (P1.3)

    // Channels
    @Published var channels: [ChannelInfo] = []
    @Published var isLoadingChannels = false

    // Weixin QR Login
    @Published var weixinQRImage: NSImage?
    @Published var weixinLoginStatus: WeixinLoginStatus = .idle
    var weixinLoginProcess: Process?

    enum WeixinLoginStatus: Equatable {
        case idle
        case waitingScan
        case success
        case failed(String)
    }

    // Models
    @Published var models: [ModelInfo] = []
    @Published var modelOverview: ModelOverview = ModelOverview()
    @Published var activeComposerModel: String = ""
    /// Last model successfully applied to each gateway session via
    /// `sessions.patch`, keyed by sessionKey. Lets the send path skip the
    /// patch round-trip when the composer model hasn't changed. Safe to keep
    /// in memory only: the gateway persists the override in its session
    /// store, and a fresh app launch starts with an empty cache anyway.
    private var appliedSessionModels: [String: String] = [:]

    /// Gateway `Main` lane concurrency cap — the number of agent runs the
    /// backend will execute in parallel before the rest start queueing.
    /// Read from `agents.defaults.maxConcurrent` in `~/.openclaw/openclaw.json`;
    /// falls back to the gateway's own default (4) when missing.
    ///
    /// Re-read whenever `loadAvailableAgents` runs so config edits flow
    /// through without an app restart.
    @Published var maxConcurrentTasks: Int = 4

    /// Number of foreground tasks currently in flight across all visible
    /// and inactive sessions. Mirrors `foregroundTaskIds.count` but
    /// exposed as a stable computed property so views can observe via
    /// `$foregroundTaskIds` without reading the underlying set directly.
    var concurrentForegroundCount: Int { foregroundTaskIds.count }

    /// Total tasks (foreground + background) currently in flight. Used by
    /// the chat header's concurrency badge — gateway's Main lane cap
    /// applies to both kinds (a `.background` task still occupies a slot
    /// on the LLM proxy), so the badge needs to count both to give the
    /// user an accurate "how close to the queueing cutoff am I" picture.
    var concurrentTaskCount: Int { foregroundTaskIds.count + backgroundTaskIds.count }
    @Published var fallbackModels: [String] = []
    @Published var imageFallbackModels: [String] = []
    @Published var isLoadingModels = false

    // Cron Jobs
    @Published var cronJobs: [CronJobInfo] = []
    @Published var isLoadingCronJobs = false
    @Published var hasLoadedCronJobs = false
    @Published var cronJobsLoadError: String?

    // Sessions Summary (for Status tab monitoring)
    @Published var sessionsSummary: SessionsSummary?
    @Published var isLoadingSessionsSummary = false

    // MARK: - Sidebar Mode

    enum SidebarMode: String {
        case config = "config"
        case teams = "teams"
        case market = "market"
    }

    @Published var sidebarMode: SidebarMode = .config
    @Published var selectedMarketplaceAgent: MarketplaceAgent?
    @Published var isRecruitingMarketplaceAgent = false

    // MARK: - Tab Management

    enum DashboardTab: String, CaseIterable, Hashable {
        case chat = "Chat"
        case status = "Status"
        case budget = "Budget"
        case billing = "Billing"
        case persona = "Persona"
        case subAgents = "Multi-Agent"
        case market = "AgentsMarket"    // agent marketplace (was sidebarMode)
        case tasksLogs = "Automation"
        case config = "Configuration"
        case skills = "Skills"
        case models = "Models"
        case outputs = "Outputs"
        case channels = "Channels"
        case plugins = "Plugins"
        case cron = "Cron"
        case logs = "Logs"

        var icon: String {
            switch self {
            case .chat: return "message.fill"
            case .status: return "chart.bar.fill"
            case .budget: return "dollarsign.gauge.chart.lefthalf.righthalf"
            case .billing: return "creditcard.fill"
            case .persona: return "person.text.rectangle"
            case .subAgents: return "person.3.fill"
            case .market: return "storefront"
            case .tasksLogs: return "clock.badge"
            case .config: return "gearshape"
            case .skills: return AppSystemSymbol.skills
            case .models: return "cube.fill"
            case .outputs: return "tray.full.fill"
            case .channels: return "bubble.left.and.bubble.right.fill"
            case .plugins: return "powerplug.portrait"
            case .cron: return "clock.badge"
            case .logs: return "doc.text.magnifyingglass"
            }
        }
    }

    func selectTab(_ tab: DashboardTab) {
        selectedTab = tab
    }

    // MARK: - Service Control

    func startService() async {
        isPerformingAction = true

        do {
            try await openclawService.start()
            showSuccessMessage("Service started successfully")
        } catch {
            showErrorMessage("Failed to start service: \(error.localizedDescription)")
        }

        isPerformingAction = false
    }

    func stopService() async {
        isPerformingAction = true

        do {
            try await openclawService.stop()
            showSuccessMessage("Service stopped successfully")
        } catch {
            showErrorMessage("Failed to stop service: \(error.localizedDescription)")
        }

        isPerformingAction = false
    }

    func restartService() async {
        isPerformingAction = true

        do {
            try await openclawService.restart()
            showSuccessMessage("Service restarted successfully")
        } catch {
            showErrorMessage("Failed to restart service: \(error.localizedDescription)")
        }

        isPerformingAction = false
    }

    func refreshStatus() async {
        await openclawService.checkStatus()
    }

    // MARK: - Configuration Management

    /// Sync the edited text fields from in-memory settings (no file I/O).
    /// Safe to call from onAppear — does not trigger @Published on AppSettingsManager.
    func syncEditedFieldsFromSettings() {
        editedPort = String(settings.settings.gatewayPort)
        editedAuthToken = settings.settings.gatewayAuthToken
        editedModelBaseUrl = settings.settings.modelBaseUrl
        editedModelApiKey = settings.settings.modelApiKey
        editedSelectedProviderKey = settings.settings.selectedProviderKey
        editedProviderApi = settings.settings.providerApi
        editedConfiguredModels = settings.settings.configuredModels
        editedActiveServiceSource = settings.settings.activeServiceSource
        availableProviders = presetManager.loadPresets().filter { $0.key != "getclawhub" }

        // If no config file exists yet, populate from preset defaults
        if editedModelBaseUrl.isEmpty,
           let preset = availableProviders.first(where: { $0.key == editedSelectedProviderKey }) {
            editedModelBaseUrl = preset.baseUrl
            editedProviderApi = preset.api
            editedConfiguredModels = preset.models
        }
        refreshAvailableModelsForCurrentProvider()
    }

    /// Reload from disk and sync fields.
    func loadConfiguration() {
        settings.loadFromFile()
        syncEditedFieldsFromSettings()
    }

    func saveConfiguration() async {
        isPerformingAction = true

        // Validate port
        guard let port = Int(editedPort), port > 0, port < 65536 else {
            showErrorMessage("Invalid port number. Must be between 1 and 65535")
            isPerformingAction = false
            return
        }

        // Update settings in memory
        settings.settings.gatewayPort = port
        settings.settings.gatewayAuthToken = editedAuthToken
        settings.settings.modelBaseUrl = editedModelBaseUrl
        settings.settings.modelApiKey = editedModelApiKey
        settings.settings.selectedProviderKey = editedSelectedProviderKey
        settings.settings.providerApi = editedProviderApi
        settings.settings.configuredModels = editedConfiguredModels
        settings.settings.activeServiceSource = editedActiveServiceSource

        // Write to ~/.openclaw/openclaw.json
        if settings.saveToFile() {
            // If GetClawHub is active and user edited the API key, update getclawhub provider
            if editedActiveServiceSource == "getclawhub" && !editedGetClawHubApiKey.isEmpty {
                let baseUrl = presetManager.findProvider(byKey: "getclawhub")?.baseUrl ?? "https://ai.getclawhub.com/v1"
                let allPresetModels = presetManager.findProvider(byKey: "getclawhub")?.models ?? []
                #if REQUIRE_LOGIN
                // Filter by membership allowed models if available. Case-insensitive
                // to absorb backend ↔ preset casing drift (e.g. `MiniMax-M2.7-highspeed`
                // vs `minimax-m2.7-highspeed`); see MembershipManager.applyKeyToConfig.
                let models: [PresetModel]
                if let allowedModels = membershipManager?.membership?.models, !allowedModels.isEmpty {
                    let allowedLowercased = Set(allowedModels.map { $0.lowercased() })
                    models = allPresetModels.filter { allowedLowercased.contains($0.id.lowercased()) }
                } else {
                    models = allPresetModels
                }
                #else
                let models = allPresetModels
                #endif
                AppSettingsManager.writeGetClawHubProvider(apiKey: editedGetClawHubApiKey, models: models, baseUrl: baseUrl, activate: true)
            }
            settings.loadFromFile()
            syncEditedFieldsFromSettings()
            loadAvailableAgents()
            await loadModels()
            await loadModelsForSettings()
            showSuccessMessage("Configuration saved to openclaw.json")
        } else {
            showErrorMessage("Failed to save configuration file")
        }

        isPerformingAction = false
    }

    func saveAndRestartService() async {
        await saveConfiguration()

        if openclawService.status == .running {
            await restartService()
        }
    }

    func resetConfiguration() {
        loadConfiguration()
    }

    func openConfigFile() {
        settings.openConfigFile()
    }

    // MARK: - Provider Switching

    /// Request to switch provider — shows confirmation alert
    func requestSwitchProvider(to key: String) {
        if key == editedSelectedProviderKey { return }
        pendingProviderKey = key
        showProviderSwitchConfirm = true
    }

    /// Confirm provider switch — fills baseUrl, api, models from preset
    func confirmSwitchProvider() {
        let key = pendingProviderKey
        editedSelectedProviderKey = key
        providerModelFetchMessage = ""
        if let preset = presetManager.findProvider(byKey: key) {
            editedModelBaseUrl = preset.baseUrl
            editedProviderApi = preset.api
            editedConfiguredModels = preset.models
            editedModelApiKey = ""
        }
        pendingProviderKey = ""
        showProviderSwitchConfirm = false
    }

    func fetchModelsForSelectedProvider() async {
        guard !isFetchingProviderModels else { return }
        isFetchingProviderModels = true
        providerModelFetchMessage = ""
        defer { isFetchingProviderModels = false }

        do {
            let models = try await providerModelFetchService.fetchModels(
                baseURL: editedModelBaseUrl,
                apiKey: editedModelApiKey
            )
            editedConfiguredModels = models
            providerModelFetchMessage = "Fetched \(models.count) model\(models.count == 1 ? "" : "s")."
            refreshAvailableModelsForCurrentProvider()
        } catch {
            providerModelFetchMessage = error.localizedDescription
        }
    }

    /// Cancel provider switch
    func cancelSwitchProvider() {
        pendingProviderKey = ""
        showProviderSwitchConfirm = false
    }

    // MARK: - Model List Editing

    /// Add a model to the edited models list
    func addModel(_ model: PresetModel) {
        editedConfiguredModels.append(model)
    }

    /// Remove a model at the given index
    func removeModel(at index: Int) {
        guard index >= 0, index < editedConfiguredModels.count else { return }
        editedConfiguredModels.remove(at: index)
        refreshAvailableModelsForCurrentProvider()
    }

    /// Open the providers preset file in TextEdit
    func openProviderPresetFile() {
        presetManager.openPresetFile()
    }

    // MARK: - Logs Management

    /// Load gateway logs from file
    func loadGatewayLogs() async {
        isLoadingLogs = true
        gatewayLogs = await openclawService.readGatewayLogs(lines: 200)
        isLoadingLogs = false
    }

    /// Start auto-refreshing logs every few seconds
    func startLogRefresh(interval: TimeInterval = 3.0) {
        stopLogRefresh()
        Task {
            await loadGatewayLogs()
        }
        logRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.loadGatewayLogs()
            }
        }
    }

    /// Stop auto-refreshing logs
    func stopLogRefresh() {
        logRefreshTimer?.invalidate()
        logRefreshTimer = nil
    }

    func clearLogs() {
        openclawService.clearLogs()
        showSuccessMessage("Logs cleared")
    }

    func exportLogs() -> String {
        return openclawService.getLogsString()
    }

    func openLogFile() {
        openclawService.openLogs()
    }

    // MARK: - Dashboard Actions

    func openDashboard() {
        openclawService.openDashboard(authToken: settings.settings.gatewayAuthToken)
    }

    // MARK: - Collab

    func getOrCreateCollabViewModel() -> CollabViewModel {
        if let existing = collabViewModel {
            return existing
        }
        let vm = CollabViewModel(dashboardViewModel: self)
        collabViewModel = vm
        return vm
    }

    func runDiagnostics() async {
        isPerformingAction = true

        let output = await openclawService.runDoctor()
        diagnosticReport = output
        showDiagnostics = true

        isPerformingAction = false
    }

    // MARK: - Quick Actions

    func performQuickAction(_ action: QuickAction) async {
        switch action {
        case .start:
            await startService()
        case .stop:
            await stopService()
        case .restart:
            await restartService()
        case .openDashboard:
            openDashboard()
        case .viewLogs:
            openLogFile()
        case .runDiagnostics:
            await runDiagnostics()
        }
    }

    enum QuickAction {
        case start
        case stop
        case restart
        case openDashboard
        case viewLogs
        case runDiagnostics
    }

    // MARK: - UI Helpers

    func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true

        // Auto-hide after 5 seconds
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            showError = false
        }
    }

    func showSuccessMessage(_ message: String) {
        successMessage = message
        showSuccess = true

        // Auto-hide after 3 seconds
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            showSuccess = false
        }
    }

    // MARK: - Skills Management

    @Published var skills: [SkillInfo] = []
    @Published var skillsSummary: SkillsSummary = SkillsSummary()
    @Published var isLoadingSkills = false
    @Published var selectedSkillDetail: SkillDetailInfo?
    @Published var isLoadingSkillDetail = false
    @Published var removingSkillName: String?
    @Published var skillCatalog: [SkillCatalogItem] = []
    @Published var isLoadingSkillCatalog = false
    @Published var installingCatalogSkillName: String?
    @Published var isInstallingManualSkill = false
    @Published var skillCatalogError: String?

    var hasLoadedSkillCatalog = false  // internal: used by SkillsManagement extension (P1.5)


    // MARK: - Chat

    @Published var chatMessagesByAgent: [String: [ChatMessage]] = [:]
    /// Computed view into the currently selected agent's messages.
    var chatMessages: [ChatMessage] {
        get { chatMessagesByAgent[selectedAgentId] ?? [] }
        set { chatMessagesByAgent[selectedAgentId] = newValue }
    }

    // MARK: - Chat Session Persistence
    //
    // M1 of the chat-history feature: persist every per-agent conversation to
    // disk so it survives app restart, and surface session metadata to the
    // sidebar (M2 will render it). The "active" session is always the most
    // recent one per agent — multi-session UX comes in later milestones.
    //
    // chatMessagesByAgent stays the live source of truth for the chat view;
    // we mirror its changes (debounced) into the active ChatSession on disk.
    let chatSessionStore = ChatSessionStore()
    /// Per-agent metadata of every session, sorted newest-first.
    /// Filtered to exclude archived sessions; archived ones live in the store.
    @Published var sessionsByAgent: [String: [ChatSessionMetadata]] = [:]
    /// Global derived list for pinned sessions. The sessions still retain their
    /// original agent/project ownership; this is only a sidebar presentation.
    @Published var pinnedSessions: [ChatSessionMetadata] = []
    @Published var projectBindingsByAgent: [String: [AgentProjectBinding]] = [:]
    @Published var projectSessionsByAgent: [String: [ProjectSessionGroup]] = [:]
    @Published var generalSessionsByAgent: [String: [ChatSessionMetadata]] = [:]
    @Published var projectsById: [String: ProjectRecord] = [:]
    /// The currently visible session for each agent. Switching this swaps
    /// chatMessagesByAgent[agentId] to the loaded session's messages.
    @Published var selectedSessionIdByAgent: [String: UUID] = [:]
    private var activeProjectIdByAgent: [String: String?] = [:]
    /// Empty sessions created by the sidebar plus button before the user sends
    /// a first message. They should be visible/clickable in the sidebar, but
    /// should not be persisted unless the user actually types into them.
    private var pendingSessionMetadataByAgent: [String: ChatSessionMetadata] = [:]

    /// Refresh `sessionsByAgent` from the store's index. Newest-first within
    /// each derived display group. Archived sessions are excluded so the
    /// sidebar list stays clean; the underlying file remains on disk.
    func rebuildSessionsMirror() {
        let persistedSessionIds = Set(chatSessionStore.index.map(\.id))
        pendingSessionMetadataByAgent = pendingSessionMetadataByAgent.filter {
            !persistedSessionIds.contains($0.value.id)
        }

        var grouped: [String: [ChatSessionMetadata]] = [:]
        for meta in chatSessionStore.index where !meta.isArchived {
            grouped[meta.agentId, default: []].append(meta)
        }
        for pending in pendingSessionMetadataByAgent.values where !pending.isArchived {
            grouped[pending.agentId, default: []].append(pending)
        }
        for key in grouped.keys {
            grouped[key] = Self.orderedSessionMetadata(grouped[key] ?? [])
        }
        sessionsByAgent = grouped
        pinnedSessions = Self.orderedSessionMetadata(grouped.values.flatMap { $0 }.filter(\.isPinned))
        rebuildProjectSessionGroups(from: grouped)
    }

    private static func orderedSessionMetadata(_ sessions: [ChatSessionMetadata]) -> [ChatSessionMetadata] {
        sessions.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func rebuildProjectSessionGroups(from grouped: [String: [ChatSessionMetadata]]) {
        var projectGroups: [String: [ProjectSessionGroup]] = [:]
        var generalGroups: [String: [ChatSessionMetadata]] = [:]

        for (agentId, sessions) in grouped {
            let unpinnedSessions = Self.orderedSessionMetadata(sessions.filter { !$0.isPinned })
            let general = unpinnedSessions.filter { $0.projectId == nil }
            if !general.isEmpty {
                generalGroups[agentId] = general
            }

            let projectSessions = Dictionary(grouping: unpinnedSessions.filter { $0.projectId != nil }) {
                $0.projectId ?? ""
            }
            var groups: [ProjectSessionGroup] = []
            for (projectId, metas) in projectSessions where !projectId.isEmpty {
                guard let project = projectsById[projectId] else { continue }
                let binding = projectBindingsByAgent[agentId]?.first { $0.projectId == projectId }
                    ?? AgentProjectBinding(agentId: agentId, projectId: projectId)
                groups.append(ProjectSessionGroup(project: project, binding: binding, sessions: metas))
            }

            for binding in projectBindingsByAgent[agentId] ?? [] where groups.allSatisfy({ $0.project.id != binding.projectId }) {
                guard let project = projectsById[binding.projectId] else { continue }
                groups.append(ProjectSessionGroup(project: project, binding: binding, sessions: []))
            }

            groups.sort { lhs, rhs in
                if lhs.binding.sortOrder != rhs.binding.sortOrder {
                    return lhs.binding.sortOrder < rhs.binding.sortOrder
                }
                return lhs.project.sortKey < rhs.project.sortKey
            }
            if !groups.isEmpty {
                projectGroups[agentId] = groups
            }
        }

        projectSessionsByAgent = projectGroups
        generalSessionsByAgent = generalGroups
    }

    /// Remove in-memory UI state that belonged to an agent after the CLI has
    /// deleted it from config/workspace. This keeps the sidebar and chat view
    /// from holding onto sessions or task placeholders for an agent that is no
    /// longer selectable.
    func removeDeletedAgentState(agentId: String) {
        let mirroredSessionIds = sessionsByAgent[agentId]?.map(\.id) ?? []
        let storeSessionIds = chatSessionStore.index
            .filter { $0.agentId == agentId }
            .map(\.id)
        let sessionIds = Set(mirroredSessionIds + storeSessionIds)

        for sessionId in sessionIds {
            cancelTasks(inSession: sessionId)
            chatMessagesByInactiveSession.removeValue(forKey: sessionId)
            loadingSessionIds.remove(sessionId)
        }

        chatMessagesByAgent.removeValue(forKey: agentId)
        selectedSessionIdByAgent.removeValue(forKey: agentId)
        pendingSessionMetadataByAgent.removeValue(forKey: agentId)
        sessionsByAgent.removeValue(forKey: agentId)

        if selectedAgentId == agentId {
            selectedAgentId = "main"
            selectedTab = .chat
        }

        chatSessionStore.loadIndex()
        rebuildSessionsMirror()
        sessionsByAgent.removeValue(forKey: agentId)
        recomputeIsSendingMessage()
    }

    /// Strip transient in-flight placeholders with no content. These are
    /// only meaningful while a chat reply is actively streaming — if one
    /// survives onto disk (e.g. the user force-quit the app, or the
    /// `cancel` path's status-flip got coalesced into a "no-op" persist
    /// by a stale equality check), reopening the session would otherwise
    /// resurrect the spinner ("Thinking…" for `.loading`, "Running in
    /// background…" for `.background`) and look like the assistant is
    /// working on a message that no longer exists.
    ///
    /// Covers both statuses; before, only `.loading + empty` was stripped,
    /// so a `.background + empty` placeholder (left behind when a
    /// session was deleted / switched away from with bg in flight, and
    /// the in-memory stash later got lost) would persist forever and
    /// render as "Running in background…" with no actual task behind it.
    private static func stripStaleLoadingPlaceholders(_ messages: [ChatMessage]) -> [ChatMessage] {
        return messages.filter {
            !(($0.taskStatus == .loading || $0.taskStatus == .background)
              && $0.content.isEmpty)
        }
    }

    private func loadProjectRegistry() {
        guard let snapshot = projectWorkspaceService.loadRegistry() else { return }
        projectsById = Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0) })
        projectBindingsByAgent = Dictionary(grouping: snapshot.bindings, by: \.agentId)
    }

    private func saveProjectRegistry() {
        do {
            try projectWorkspaceService.saveRegistry(
                projects: Array(projectsById.values),
                bindingsByAgent: projectBindingsByAgent
            )
        } catch {
            logChat("PROJECT_REGISTRY_SAVE_FAILED: \(error.localizedDescription)")
        }
    }

    func openProject(forAgent agentId: String) {
        let agentName = agentDisplayName(for: agentId)
        let panel = ProjectWorkspacePicker.makePanel(agentName: agentName)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.attachProject(url, toAgent: agentId)
            }
        }
    }

    private func attachProject(_ url: URL, toAgent agentId: String) {
        let attachment = projectWorkspaceService.attachProject(
            url: url,
            toAgent: agentId,
            projectsById: projectsById,
            bindingsByAgent: projectBindingsByAgent
        )
        projectsById = attachment.projectsById
        projectBindingsByAgent = attachment.bindingsByAgent

        saveProjectRegistry()
        rebuildSessionsMirror()
        createNewSession(forAgent: agentId, projectId: attachment.project.id)

        Task { [projectWorkspaceService] in
            await projectWorkspaceService.bootstrapProject(attachment.project)
        }

        showSuccessMessage("\(agentDisplayName(for: agentId)) is now working in \(attachment.project.displayName)")
    }

    private func agentDisplayName(for agentId: String) -> String {
        availableAgents.first(where: { $0.id == agentId })?.name ?? agentId
    }

    func toggleProjectCollapse(agentId: String, projectId: String) {
        projectBindingsByAgent = projectWorkspaceService.toggleCollapse(
            agentId: agentId,
            projectId: projectId,
            bindingsByAgent: projectBindingsByAgent
        )
        saveProjectRegistry()
        rebuildSessionsMirror()
    }

    func revealProjectInFinder(_ projectId: String) {
        guard let project = projectsById[projectId] else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.rootPath)])
    }

    func removeProject(_ projectId: String, fromAgent agentId: String) {
        projectBindingsByAgent = projectWorkspaceService.removeProject(
            projectId,
            fromAgent: agentId,
            bindingsByAgent: projectBindingsByAgent
        )
        if activeProjectIdByAgent[agentId] == projectId {
            activeProjectIdByAgent.removeValue(forKey: agentId)
        }
        saveProjectRegistry()
        rebuildSessionsMirror()
    }

    /// Load `agentId`'s active session messages into `chatMessagesByAgent`
    /// if they haven't been parsed yet. Called from the `selectedAgentId`
    /// sink so switching to an agent that was deferred at startup parses
    /// its session on first access. Cache hit returns instantly; cache
    /// miss kicks off an async load (with `loadingSessionIds` flipped to
    /// flag the view) so the main thread isn't blocked on a big decode.
    private func ensureMessagesLoaded(forAgent agentId: String) {
        guard chatMessagesByAgent[agentId] == nil,
              let sid = selectedSessionIdByAgent[agentId] else {
            return
        }
        if let cached = chatSessionStore.cachedSession(id: sid) {
            chatMessagesByAgent[agentId] = Self.stripStaleLoadingPlaceholders(cached.messages)
            return
        }
        // Cold path — async decode.
        loadingSessionIds.insert(sid)
        Task { [weak self] in
            guard let self = self else { return }
            let target = await self.chatSessionStore.loadSessionAsync(id: sid)
            await MainActor.run {
                // Bail if the user has switched agent again in the
                // meantime — we don't want to clobber their current view.
                guard self.selectedAgentId == agentId,
                      self.selectedSessionIdByAgent[agentId] == sid else {
                    self.loadingSessionIds.remove(sid)
                    return
                }
                if let target = target {
                    self.chatMessagesByAgent[agentId] = Self.stripStaleLoadingPlaceholders(target.messages)
                }
                self.loadingSessionIds.remove(sid)
            }
        }
    }

    /// On launch, restore active sessions for each agent.
    ///
    /// Two-phase load:
    /// - **Eager** (synchronous, on main thread): load the currently-selected
    ///   agent's most-recent session. This is the one the user sees first
    ///   when the chat tab opens, so blocking the main thread for this one
    ///   parse is acceptable — anything else and the UI flashes empty.
    /// - **Lazy** (in a Task): note the session-id for every other agent so
    ///   the sidebar can show them and `selectedSessionIdByAgent` is
    ///   populated, but DON'T load their message bodies yet. Those parse
    ///   on demand when the user switches to that agent (cheap thanks to
    ///   the ChatSessionStore cache hitting once they've loaded once).
    ///
    /// Previously this iterated every agent synchronously and parsed each
    /// agent's full most-recent session, so users with several agents felt
    /// startup as 5+ blocking JSON decodes on the main thread before the
    /// chat view rendered anything.
    private func restoreActiveSessionsFromStore() {
        let currentAgent = selectedAgentId
        for (agentId, metas) in sessionsByAgent {
            guard let mostRecent = metas.first else { continue }
            selectedSessionIdByAgent[agentId] = mostRecent.id
            // Only synchronously parse messages for the visible agent.
            if agentId == currentAgent,
               let session = chatSessionStore.loadSession(id: mostRecent.id) {
                chatMessagesByAgent[agentId] = Self.stripStaleLoadingPlaceholders(session.messages)
            }
            // Non-visible agents: leave chatMessagesByAgent[agentId] unset.
            // It'll be populated lazily by switchSession the first time the
            // user clicks into that agent — at which point the parse cost
            // is paid once, then cached.
        }
    }

    /// Mirror every agent's in-memory messages back to its active session on
    /// disk. Called from a debounced sink, so token-by-token streaming
    /// produces one write per ~500ms idle window. Lazily creates a session
    /// the first time an agent gets a message.
    private func persistChangedSessions(from dict: [String: [ChatMessage]]) {
        for (agentId, messages) in dict where !messages.isEmpty {
            let sessionId = ensureActiveSessionId(forAgent: agentId, seedMessages: messages)
            let project = activeProject(forAgent: agentId)
            // Start from the on-disk copy when one exists (preserves
            // pin/archive state) or mint a fresh in-memory shell otherwise.
            let loaded = chatSessionStore.loadSession(id: sessionId)
            var session = loaded ?? ChatSession(
                id: sessionId,
                agentId: agentId,
                messages: messages,
                projectId: project?.id,
                projectRoot: project?.rootPath,
                projectDisplayName: project?.displayName
            )

            // Strip stale .loading + empty placeholders before comparing
            // to disk. We never want to persist a placeholder — and the
            // disk side might already have one from a previous app launch
            // that crashed before the placeholder got updated.
            let memMessages = Self.stripStaleLoadingPlaceholders(messages)
            let diskMessages = loaded.map { Self.stripStaleLoadingPlaceholders($0.messages) } ?? []

            // Skip the write only when disk already holds the same trailing
            // state. The check is gated on `loaded != nil` because a
            // freshly-minted pending session (from createNewSession) loads
            // to nil — the fallback constructor pre-populates `messages`,
            // which would make the equality check trivially pass and the
            // first message would never persist.
            //
            // Compare task status + content length in addition to id, so
            // that an in-place status flip (.loading → .cancelled, or a
            // streaming delta appending text) is not coalesced into a
            // no-op write — that was the source of the "session always
            // looks like it's thinking" bug (the spinner placeholder got
            // saved at .loading, then the cancel update was skipped, and
            // disk kept the .loading state forever).
            if let loaded = loaded,
               diskMessages.count == memMessages.count,
               diskMessages.last?.id == memMessages.last?.id,
               diskMessages.last?.taskStatus == memMessages.last?.taskStatus,
               diskMessages.last?.content.count == memMessages.last?.content.count,
               Self.messagesHaveSameActivityEvents(diskMessages.last, memMessages.last),
               !loaded.title.isEmpty {
                continue
            }

            session.messages = memMessages
            session.updatedAt = Date()
            if let project {
                session.projectId = project.id
                session.projectRoot = project.rootPath
                session.projectDisplayName = project.displayName
            }
            // Auto-derive title once, only while still on the placeholder.
            if session.title == ChatSession.defaultTitle {
                session.title = ChatSession.deriveTitle(from: memMessages)
            }
            chatSessionStore.saveSessionDebounced(session)
        }
        // Even if no messages changed, the index may have new metadata
        // (titles, message counts) — rebuild the published mirror.
        rebuildSessionsMirror()
    }

    private static func messagesHaveSameActivityEvents(_ lhs: ChatMessage?, _ rhs: ChatMessage?) -> Bool {
        (lhs?.activityEvents ?? []) == (rhs?.activityEvents ?? [])
    }

    private static func elapsedMillisecondsText(since start: ContinuousClock.Instant) -> String {
        let duration = start.duration(to: ContinuousClock.now)
        let components = duration.components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.1f", milliseconds)
    }

    // MARK: - Session UI Actions

    /// Switch the current agent's active session to `sessionId`. Flushes the
    /// in-memory thread of the previous session to disk first so partial
    /// state isn't lost when the user clicks back.
    func switchSession(to sessionId: UUID) {
        let switchStart = ContinuousClock.now
        let agentId = selectedAgentId
        let oldSid = selectedSessionIdByAgent[agentId]
        if let meta = sessionMetadata(for: sessionId) {
            activeProjectIdByAgent[agentId] = meta.projectId
        }
        sessionSwitchPerfLog.info("switchSession start agent=\(agentId, privacy: .public) session=\(sessionId.uuidString, privacy: .public) previous_session=\(oldSid?.uuidString ?? "none", privacy: .public)")
        if oldSid == sessionId {
            sessionSwitchPerfLog.info("switchSession skipped reason=same_session agent=\(agentId, privacy: .public) session=\(sessionId.uuidString, privacy: .public) elapsed_ms=\(Self.elapsedMillisecondsText(since: switchStart), privacy: .public)")
            return
        }

        // If the session we're LEAVING has an in-flight task (foreground
        // OR background), we can't just overwrite `chatMessagesByAgent[agentId]`
        // — subsequent stream events would find no msgId to update and
        // silently discard output. Instead, stash the current messages
        // into the inactive map keyed by the old sessionId. Stream
        // handlers know to look there too. When the user returns to
        // that session, we unstash.
        //
        // `hasInflightTask` covers both kinds: a task moved to bg via
        // moveTaskToBackground is still running on the gateway and
        // still needs its placeholder preserved so stream events can
        // land. (Earlier this was `hasForegroundTask` only — bg tasks
        // got silently dropped on session switch.)
        if let oldSid = oldSid, hasInflightTask(inSession: oldSid) {
            chatMessagesByInactiveSession[oldSid] = chatMessagesByAgent[agentId]
        }

        flushActiveSession(forAgent: agentId)
        discardEmptyPendingSessionIfNeeded(forAgent: agentId)
        selectedSessionIdByAgent[agentId] = sessionId

        // Source-of-truth precedence on a session switch:
        //  1. In-memory inactive stash (most current — includes any
        //     streaming that completed while the user was away).
        //  2. ChatSessionStore's LRU cache (warm hit, instant decode).
        //  3. Disk (cold load — kicked off async so we don't freeze the
        //     main thread on a multi-hundred-KB JSON parse). We set a
        //     loading flag the view watches to show a spinner during
        //     this window.
        //
        // IMPORTANT: do NOT `stripStaleLoadingPlaceholders` an in-memory
        // unstash. The strip would remove a still-running .loading + ""
        // placeholder, but the task IS still alive (foregroundTaskIds /
        // taskSessionMap still have its msgId). Once stripped, the next
        // stream event has nowhere to land — findMessage returns nil and
        // the output is silently dropped. The disk path strips because
        // we can't tell a live placeholder from a dead one left over by
        // a previous crash.
        if let stashed = chatMessagesByInactiveSession.removeValue(forKey: sessionId) {
            chatMessagesByAgent[agentId] = stashed
            loadingSessionIds.remove(sessionId)
            sessionSwitchPerfLog.info("switchSession source=inactive_stash agent=\(agentId, privacy: .public) session=\(sessionId.uuidString, privacy: .public) messages=\(stashed.count, privacy: .public) elapsed_ms=\(Self.elapsedMillisecondsText(since: switchStart), privacy: .public)")
        } else if let target = chatSessionStore.cachedSession(id: sessionId) {
            let messages = Self.stripStaleLoadingPlaceholders(target.messages)
            chatMessagesByAgent[agentId] = messages
            loadingSessionIds.remove(sessionId)
            sessionSwitchPerfLog.info("switchSession source=memory_cache agent=\(agentId, privacy: .public) session=\(sessionId.uuidString, privacy: .public) messages=\(messages.count, privacy: .public) elapsed_ms=\(Self.elapsedMillisecondsText(since: switchStart), privacy: .public)")
        } else {
            // Cold load — render a loading placeholder while we decode
            // the JSON off the main thread.
            chatMessagesByAgent[agentId] = []
            loadingSessionIds.insert(sessionId)
            sessionSwitchPerfLog.info("switchSession source=cold_disk_start agent=\(agentId, privacy: .public) session=\(sessionId.uuidString, privacy: .public) elapsed_ms=\(Self.elapsedMillisecondsText(since: switchStart), privacy: .public)")
            Task { [weak self] in
                guard let self = self else { return }
                let target = await self.chatSessionStore.loadSessionAsync(id: sessionId)
                await MainActor.run {
                    // If the user has navigated away again before the
                    // decode finished, drop the result rather than
                    // clobbering whatever they're looking at now.
                    guard self.selectedSessionIdByAgent[agentId] == sessionId else {
                        self.loadingSessionIds.remove(sessionId)
                        return
                    }
                    if let target = target {
                        let messages = Self.stripStaleLoadingPlaceholders(target.messages)
                        self.chatMessagesByAgent[agentId] = messages
                        sessionSwitchPerfLog.info("switchSession source=cold_disk_finish status=loaded agent=\(agentId, privacy: .public) session=\(sessionId.uuidString, privacy: .public) messages=\(messages.count, privacy: .public) elapsed_ms=\(Self.elapsedMillisecondsText(since: switchStart), privacy: .public)")
                    } else {
                        sessionSwitchPerfLog.info("switchSession source=cold_disk_finish status=missing agent=\(agentId, privacy: .public) session=\(sessionId.uuidString, privacy: .public) elapsed_ms=\(Self.elapsedMillisecondsText(since: switchStart), privacy: .public)")
                    }
                    self.loadingSessionIds.remove(sessionId)
                }
            }
        }
        rebuildSessionsMirror()
        recomputeIsSendingMessage()
    }

    /// Switch to a session that may belong to a different agent.
    func switchSessionGlobally(to sessionId: UUID) {
        guard let meta = chatSessionStore.index.first(where: { $0.id == sessionId }) else {
            return
        }
        if selectedAgentId != meta.agentId {
            selectedAgentId = meta.agentId
        }
        activeProjectIdByAgent[meta.agentId] = meta.projectId
        switchSession(to: sessionId)
    }

    /// Update the title of a stored session. Empty / whitespace-only strings
    /// are ignored so we never end up with an unreadable row.
    /// Set when a rewind attempt fails, so the chat view can surface it.
    @Published var rewindError: String?

    /// One-shot channel to push text back into the composer. On a successful
    /// "rewind = edit & resend", we drop the clicked message (and everything
    /// after) and stash its text here; the chat view observes this, copies it
    /// into its `inputText` field, and clears it. Lets the view model drive the
    /// view-owned composer without holding a reference to it.
    @Published var composerPrefill: String?

    /// Rewind = "edit & resend": drop the clicked user message and everything
    /// after it, put its text back in the composer, and move the session's
    /// branch point so the next send REPLACES that turn.
    ///
    /// Implemented entirely CLIENT-SIDE — no gateway protocol method. The
    /// gateway runs locally and re-reads the transcript on each run
    /// (SessionManager.open → fresh file read; the leaf is the file's last
    /// entry), so truncating the local `.jsonl` to before the clicked message
    /// moves the branch point for free. Verified against the gateway's own
    /// SessionManager on real multi-turn transcripts. Rewind is gated to user
    /// bubbles (see ChatBubble); user turns are single transcript entries (no
    /// tool sub-entries), so we anchor by user-message ordinal — robust against
    /// the assistant/tool entry drift that indexing over mixed turns would hit.
    func rewindToMessage(_ message: ChatMessage, replacementText: String? = nil) {
        let agentId = selectedAgentId
        guard let sessionId = selectedSessionIdByAgent[agentId] else {
            self.rewindError = "没有活动会话，无法回滚"
            return
        }
        let sessionKey = sessionKeyForAgent(agentId, sessionId: sessionId)
        let clientMessages = chatMessagesByAgent[agentId] ?? []
        guard clientMessages.contains(where: { $0.id == message.id }) else {
            self.rewindError = "找不到该消息，无法回滚"
            return
        }
        // Anchor by ordinal among USER messages (rewind only shows on user
        // bubbles). User turns are single transcript entries, so this lines up
        // 1:1 with the transcript's user entries — no drift from assistant/tool
        // sub-entries.
        let userMsgs = clientMessages.filter { $0.role == .user }
        guard let userIdx = userMsgs.firstIndex(where: { $0.id == message.id }) else {
            self.rewindError = "找不到该消息位置，无法回滚"
            return
        }

        Task { @MainActor in
            // 1. Tear down any in-flight run in THIS session (abort each by its
            //    runId + clear tracking) so we never truncate a transcript that's
            //    mid-write and never orphan `isSendingMessage`. Scoped to this
            //    session — other sessions/agents keep running untouched.
            self.cancelTasks(inSession: sessionId)
            _ = await gatewayClient.abortChat(sessionKey: sessionKey)
            // Let the abort + any final transcript write flush before we touch
            // the file.
            try? await Task.sleep(nanoseconds: 250_000_000)

            // 2. Client-side branch: truncate the local transcript to before the
            //    clicked user message (backs the file up first). No gateway call.
            if let err = self.truncateTranscriptForRewind(
                agentId: agentId,
                sessionKey: sessionKey,
                userOrdinal: userIdx,
                clickedText: message.content
            ) {
                self.rewindError = err
                return
            }

            // 3. Mirror locally: drop the clicked message and everything after.
            //    If the caller provided confirmed replacement text, immediately
            //    send it on the new branch. Otherwise preserve the legacy
            //    composer-prefill behavior.
            if let msgs = self.chatMessagesByAgent[agentId],
               let curIdx = msgs.firstIndex(where: { $0.id == message.id }) {
                self.chatMessagesByAgent[agentId] = Array(msgs.prefix(curIdx))
            }
            self.rewindError = nil
            if let editedText = replacementText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !editedText.isEmpty {
                await self.sendChatMessage(editedText, attachments: message.attachments)
            } else {
                self.composerPrefill = message.content
            }
        }
    }

    /// Truncate the local session transcript (`<sid>.jsonl`) so the user message
    /// at `userOrdinal` (and everything after) is dropped. Returns an error
    /// string on failure, nil on success. Backs the file up first
    /// (`.jsonl.rewind.<ts>`). This IS the rewind on the gateway side: the next
    /// run re-reads the file and the new last entry becomes the leaf — no
    /// gateway protocol method needed (the gateway is local).
    private func truncateTranscriptForRewind(
        agentId: String,
        sessionKey: String,
        userOrdinal: Int,
        clickedText: String
    ) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let sessionsDir = "\(home)/.openclaw/agents/\(agentId)/sessions"
        let sessionsJsonPath = "\(sessionsDir)/sessions.json"
        // Map the UI sessionKey → the gateway transcript's session id.
        guard let data = FileManager.default.contents(atPath: sessionsJsonPath),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "无法读取 sessions.json"
        }
        // Case-insensitive key match: the client builds sessionKey with Swift's
        // UPPERCASE `UUID.uuidString`, but the gateway stores keys with a
        // LOWERCASE uuid (e.g. agent:main:c4b9d48d-…). An exact match misses.
        let targetKey = sessionKey.lowercased()
        guard let entryVal = root.first(where: { $0.key.lowercased() == targetKey })?.value,
              let entry = entryVal as? [String: Any],
              let gwSessionId = entry["sessionId"] as? String else {
            return "找不到会话转录（sessions.json 无对应条目）"
        }
        let jsonlPath = "\(sessionsDir)/\(gwSessionId).jsonl"
        guard let content = try? String(contentsOfFile: jsonlPath, encoding: .utf8) else {
            return "无法读取会话转录文件"
        }
        let rawLines = content.components(separatedBy: "\n")

        // Line indices of user-role message entries, in order.
        var userLines: [(line: Int, text: String)] = []
        for (i, line) in rawLines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            guard let ld = t.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: ld) as? [String: Any],
                  (obj["type"] as? String) == "message",
                  let msg = obj["message"] as? [String: Any],
                  (msg["role"] as? String) == "user" else { continue }
            userLines.append((i, Self.jsonlMessageText(msg)))
        }

        // Resolve the cut line: prefer the ordinal (1:1 with user bubbles),
        // validate by content "contains" (the transcript can wrap user text in
        // an envelope), and fall back to nearest content match on any drift.
        let trimmed = clickedText.trimmingCharacters(in: .whitespacesAndNewlines)
        var cutLine: Int? = nil
        if userOrdinal < userLines.count,
           trimmed.isEmpty || userLines[userOrdinal].text.contains(trimmed) {
            cutLine = userLines[userOrdinal].line
        }
        if cutLine == nil, !trimmed.isEmpty {
            let matches = userLines.enumerated().filter { $0.element.text.contains(trimmed) }
            if let nearest = matches.min(by: { abs($0.offset - userOrdinal) < abs($1.offset - userOrdinal) }) {
                cutLine = nearest.element.line
            }
        }
        guard let cut = cutLine else {
            return "无法定位回滚锚点：本地用户消息#\(userOrdinal)/转录\(userLines.count)条"
        }

        // Back up, then keep everything BEFORE the cut line.
        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try? FileManager.default.copyItem(atPath: jsonlPath, toPath: "\(jsonlPath).rewind.\(ts)")
        let kept = rawLines.prefix(cut).joined(separator: "\n")
        let finalContent = kept.isEmpty ? "" : kept + "\n"
        do {
            try finalContent.write(toFile: jsonlPath, atomically: true, encoding: .utf8)
        } catch {
            return "写入截断后的转录失败：\(error.localizedDescription)"
        }
        return nil
    }

    /// Extract display text from a transcript message entry's `message` object
    /// (`text`, string `content`, or content-block array).
    private static func jsonlMessageText(_ msg: [String: Any]) -> String {
        if let t = msg["text"] as? String { return t }
        if let c = msg["content"] as? String { return c }
        if let blocks = msg["content"] as? [[String: Any]] {
            return blocks.compactMap { ($0["type"] as? String) == "text" ? ($0["text"] as? String) : nil }
                .joined(separator: "\n")
        }
        return ""
    }

    func renameSession(_ sessionId: UUID, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var session = chatSessionStore.loadSession(id: sessionId) else { return }
        session.title = trimmed
        session.updatedAt = Date()
        chatSessionStore.saveSession(session)
        rebuildSessionsMirror()
    }

    /// Permanently remove a session (file + index entry). If we're deleting
    /// the active session, automatically promote the next-newest session, or
    /// mint an empty one if none remain — never leave the chat view broken.
    func deleteSession(_ sessionId: UUID) {
        let agentId = sessionMetadata(for: sessionId)?.agentId ?? selectedAgentId
        let wasActive = selectedSessionIdByAgent[agentId] == sessionId
        // Cancel any in-flight task tied to this session BEFORE we drop the
        // file — without this, the run keeps streaming on the gateway with
        // nowhere to land (foregroundTaskIds / taskSessionMap entries
        // become orphans, isSendingMessage stays true forever).
        cancelTasks(inSession: sessionId)
        chatSessionStore.deleteSession(id: sessionId)
        // Drop any stashed in-memory copy too. Otherwise the entry sits in
        // chatMessagesByInactiveSession forever (until app restart), and the
        // 500ms persistInactiveSessions sink keeps firing for it — each tick
        // calls loadSession, gets nil (file is gone), skips. Wasted CPU and
        // memory for a session the user explicitly removed.
        chatMessagesByInactiveSession.removeValue(forKey: sessionId)
        if pendingSessionMetadataByAgent[agentId]?.id == sessionId {
            pendingSessionMetadataByAgent.removeValue(forKey: agentId)
        }
        if wasActive {
            promoteNextSession(forAgent: agentId)
        }
        rebuildSessionsMirror()
        recomputeIsSendingMessage()
    }

    /// Toggle pinned state. Pinning is a presentation change, so it should not
    /// bump `updatedAt` or affect the session's original recency position.
    func togglePinSession(_ sessionId: UUID) {
        guard var session = chatSessionStore.loadSession(id: sessionId) else { return }
        session.isPinned.toggle()
        chatSessionStore.saveSession(session)
        rebuildSessionsMirror()
    }

    /// Mark a session as archived. Archived sessions stay on disk but are
    /// hidden from the default sidebar list. Active session promotion is the
    /// same as delete — we don't want to leave the user staring at a row
    /// that was just hidden.
    func archiveSession(_ sessionId: UUID) {
        let agentId = sessionMetadata(for: sessionId)?.agentId ?? selectedAgentId
        let wasActive = selectedSessionIdByAgent[agentId] == sessionId
        guard var session = chatSessionStore.loadSession(id: sessionId) else { return }
        session.isArchived = true
        session.updatedAt = Date()
        chatSessionStore.saveSession(session)
        if wasActive {
            promoteNextSession(forAgent: agentId)
        }
        rebuildSessionsMirror()
    }

    /// Export a session to Markdown via NSSavePanel. The file uses the
    /// session title as the default name.
    func exportSession(_ sessionId: UUID) {
        guard let session = chatSessionStore.loadSession(id: sessionId) else { return }
        let markdown = Self.sessionMarkdown(session)
        let panel = NSSavePanel()
        panel.title = "Export Chat Session"
        panel.nameFieldStringValue = "\(session.title.replacingOccurrences(of: "/", with: "_")).md"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// After delete/archive of the active session, pick a successor from the
    /// remaining list, or mint a new empty session when nothing's left.
    private func promoteNextSession(forAgent agentId: String) {
        let projectId = activeProjectIdByAgent[agentId] ?? nil
        let candidates = chatSessionStore.sessions(forAgent: agentId).filter { $0.projectId == projectId }
        if let next = candidates.first {
            selectedSessionIdByAgent[agentId] = next.id
            if let loaded = chatSessionStore.loadSession(id: next.id) {
                chatMessagesByAgent[agentId] = Self.stripStaleLoadingPlaceholders(loaded.messages)
            }
        } else {
            // No surviving sessions — mint a fresh empty session in memory
            // only. Match createNewSession() in deferring the disk write
            // until the user actually types, so an immediately-discarded
            // empty session leaves no trace in the sidebar.
            let project = activeProject(forAgent: agentId)
            let new = ChatSession(
                agentId: agentId,
                projectId: project?.id,
                projectRoot: project?.rootPath,
                projectDisplayName: project?.displayName
            )
            selectedSessionIdByAgent[agentId] = new.id
            chatMessagesByAgent[agentId] = []
        }
        recomputeIsSendingMessage()
    }

    private static func sessionMarkdown(_ s: ChatSession) -> String {
        let df = ISO8601DateFormatter()
        var out = "# \(s.title)\n\n"
        out += "_Created: \(df.string(from: s.createdAt))_  \n"
        out += "_Updated: \(df.string(from: s.updatedAt))_\n\n"
        out += "---\n\n"
        for m in s.messages {
            let role = m.role == .user ? "**User**" : "**Assistant**"
            out += "\(role):\n\n\(m.content)\n\n---\n\n"
        }
        return out
    }

    /// Mint a fresh empty session for the current agent and switch to it.
    /// Used by the "New chat" sidebar button.
    ///
    /// The session is created in memory only — the disk write is deferred
    /// until the user actually adds a message (handled by
    /// `persistChangedSessions`). This way a "New chat" click followed
    /// by an immediate switch to another row leaves no orphan empty session
    /// in the sidebar.
    @discardableResult
    func createNewSession() -> UUID {
        createNewSession(forAgent: selectedAgentId, projectId: nil)
    }

    /// Mint a fresh empty session for a specific agent and switch the UI to it.
    /// Used by per-agent sidebar hover actions.
    @discardableResult
    func createNewSession(forAgent agentId: String) -> UUID {
        createNewSession(forAgent: agentId, projectId: nil)
    }

    @discardableResult
    func createNewSession(forAgent agentId: String, projectId: String?) -> UUID {
        if selectedAgentId != agentId {
            flushActiveSession(forAgent: selectedAgentId)
            selectedAgentId = agentId
        }
        activeProjectIdByAgent[agentId] = projectId

        let oldSid = selectedSessionIdByAgent[agentId]
        // Symmetric with switchSession: if a task is streaming in the old
        // session (foreground OR background), preserve its message list
        // in the inactive stash so stream events can still find their
        // target. We do NOT cancel.
        if let oldSid = oldSid, hasInflightTask(inSession: oldSid) {
            chatMessagesByInactiveSession[oldSid] = chatMessagesByAgent[agentId]
        }
        flushActiveSession(forAgent: agentId)
        let project = projectId.flatMap { projectsById[$0] }
        let new = ChatSession(
            agentId: agentId,
            projectId: project?.id,
            projectRoot: project?.rootPath,
            projectDisplayName: project?.displayName
        )
        selectedSessionIdByAgent[agentId] = new.id
        chatMessagesByAgent[agentId] = []
        pendingSessionMetadataByAgent[agentId] = ChatSessionMetadata(from: new)
        rebuildSessionsMirror()
        recomputeIsSendingMessage()
        return new.id
    }

    private func discardEmptyPendingSessionIfNeeded(forAgent agentId: String) {
        guard let sid = selectedSessionIdByAgent[agentId],
              pendingSessionMetadataByAgent[agentId]?.id == sid,
              (chatMessagesByAgent[agentId] ?? []).isEmpty,
              chatSessionStore.loadSession(id: sid) == nil else {
            return
        }
        pendingSessionMetadataByAgent.removeValue(forKey: agentId)
    }

    /// Cancel any pending debounced write for the agent's current session and
    /// commit its in-memory messages to disk synchronously. Safe to call
    /// when there is no active session — it's a no-op.
    ///
    /// Two short-circuits:
    /// - **Pending unsaved session with no content** (created by
    ///   `createNewSession` but never typed in): drop without persisting,
    ///   so the sidebar never sees an empty row.
    /// - **No actual change** vs what's on disk: cancel any pending
    ///   debounced write and bail, so a plain session switch doesn't bump
    ///   `updatedAt` and reorder the sidebar list.
    private func flushActiveSession(forAgent agentId: String) {
        guard let sid = selectedSessionIdByAgent[agentId] else { return }
        let messages = chatMessagesByAgent[agentId] ?? []
        let loaded = chatSessionStore.loadSession(id: sid)

        // Pending session that was minted in memory but never received any
        // input — discard.
        if loaded == nil && messages.isEmpty {
            discardEmptyPendingSessionIfNeeded(forAgent: agentId)
            return
        }

        // Strip .loading + empty placeholders — same rationale as in
        // persistChangedSessions: transient spinners must never hit disk.
        let memMessages = Self.stripStaleLoadingPlaceholders(messages)
        let diskMessages = loaded.map { Self.stripStaleLoadingPlaceholders($0.messages) } ?? []

        // Compare against the on-disk copy. If nothing changed, don't
        // rewrite the file (would bump updatedAt and reorder the list).
        // Include status + content length so an in-place message update
        // (.loading → .cancelled, streaming delta) is not coalesced into
        // a no-op. Was previously only count + last id, which let the
        // cancel-flip be silently dropped.
        let messagesChanged: Bool
        if loaded != nil {
            messagesChanged = diskMessages.count != memMessages.count
                || diskMessages.last?.id != memMessages.last?.id
                || diskMessages.last?.taskStatus != memMessages.last?.taskStatus
                || diskMessages.last?.content.count != memMessages.last?.content.count
        } else {
            messagesChanged = !memMessages.isEmpty
        }

        guard messagesChanged else {
            // Cancel any in-flight debounced write for this id but emit no
            // fresh write of our own.
            chatSessionStore.flush(id: sid, current: nil)
            return
        }

        let project = activeProject(forAgent: agentId)
        var current = loaded ?? ChatSession(
            id: sid,
            agentId: agentId,
            messages: memMessages,
            projectId: project?.id,
            projectRoot: project?.rootPath,
            projectDisplayName: project?.displayName
        )
        current.messages = memMessages
        current.updatedAt = Date()
        if let project {
            current.projectId = project.id
            current.projectRoot = project.rootPath
            current.projectDisplayName = project.displayName
        }
        if current.title == ChatSession.defaultTitle {
            current.title = ChatSession.deriveTitle(from: memMessages)
        }
        chatSessionStore.flush(id: sid, current: current)
    }

    /// Return the active session id for `agentId`, creating one if needed.
    /// `seedMessages` is the current in-memory thread; used to derive a title
    /// if we have to mint a fresh session.
    @discardableResult
    private func ensureActiveSessionId(forAgent agentId: String, seedMessages: [ChatMessage] = []) -> UUID {
        if let existing = selectedSessionIdByAgent[agentId] {
            return existing
        }
        let projectId = activeProjectId(forAgent: agentId)
        // Reuse the newest non-archived session for this agent if one exists
        // (e.g. the picker pointed at a known agent but selection wasn't seeded).
        if let recent = chatSessionStore.sessions(forAgent: agentId).first(where: { $0.projectId == projectId }) {
            selectedSessionIdByAgent[agentId] = recent.id
            return recent.id
        }
        // Mint a new session and persist it immediately so subsequent
        // lookups see it in the index.
        let title = ChatSession.deriveTitle(from: seedMessages)
        let project = activeProject(forAgent: agentId)
        let new = ChatSession(
            agentId: agentId,
            title: title,
            messages: seedMessages,
            projectId: project?.id,
            projectRoot: project?.rootPath,
            projectDisplayName: project?.displayName
        )
        chatSessionStore.saveSession(new)
        selectedSessionIdByAgent[agentId] = new.id
        return new.id
    }
    /// True only when the *currently visible* (agent + active session) has
    /// a foreground task in flight. Recomputed via `recomputeIsSendingMessage()`
    /// every time a task is added/removed, or when the user switches agent/
    /// session. Was previously "true if ANY foreground task exists across
    /// agents/sessions", which locked the input in a session that didn't
    /// actually have a task running.
    @Published var isSendingMessage = false
    @Published var foregroundTaskIds: Set<UUID> = []  // message IDs of foreground (blocking) tasks
    @Published var backgroundTaskIds: Set<UUID> = []  // message IDs of background tasks
    var taskAgentMap: [UUID: String] = [:]  // msgId → agentId
    /// msgId → the sessionId the task was started under. Used to (a) route
    /// gateway sessionKey on cancel and (b) decide which UI session "owns"
    /// the spinner / cancel affordance. Both populated together with
    /// `taskAgentMap` in `sendChatMessage`; both cleaned together on any
    /// terminal event (completed / cancelled / timed-out / error).
    var taskSessionMap: [UUID: UUID] = [:]

    /// Messages for sessions the user has navigated AWAY from while a
    /// foreground task was still streaming. Keyed by sessionId. The
    /// session's stream events keep updating this map even though the
    /// session isn't visible — so when the user navigates back, the
    /// result (or in-progress streaming) is already there.
    ///
    /// Cleared on switch-back into the session (entry is moved to
    /// `chatMessagesByAgent[agentId]`) and on session delete.
    /// Persisted via a parallel debounced save sink so on-disk state
    /// catches up with completions that landed while the session was
    /// inactive.
    @Published var chatMessagesByInactiveSession: [UUID: [ChatMessage]] = [:]

    /// Sessions whose messages are being lazy-loaded from disk in the
    /// background. The chat view watches this set so it can render a
    /// "loading…" placeholder during the cold-load window instead of
    /// flashing an empty thread. Entries are added by `switchSession` /
    /// `ensureMessagesLoaded` when they take the async path (cache miss)
    /// and removed when the load resolves.
    @Published var loadingSessionIds: Set<UUID> = []

    /// Whether the currently selected agent has any foreground task running
    /// — across all its sessions. Used by the agent picker to badge agents
    /// that are working in the background.
    var isCurrentAgentSending: Bool {
        foregroundTaskIds.contains(where: { taskAgentMap[$0] == selectedAgentId })
    }

    /// Check if a specific agent has a foreground task running (any session).
    func isAgentExecuting(_ agentId: String) -> Bool {
        foregroundTaskIds.contains(where: { taskAgentMap[$0] == agentId })
    }

    /// Check if a specific session has a foreground task running. Used by
    /// the input bar to decide whether to disable typing (background
    /// tasks INTENTIONALLY unlock the input — moving to bg is the user
    /// saying "don't block me on this").
    func hasForegroundTask(inSession sessionId: UUID) -> Bool {
        foregroundTaskIds.contains(where: { taskSessionMap[$0] == sessionId })
    }

    /// Check if a specific session has ANY in-flight task — foreground OR
    /// background. Used wherever we care about "is the gateway still
    /// running work on behalf of this session" regardless of whether the
    /// spinner is locking the UI:
    ///   - sidebar activity dot (orange) — shows even for bg tasks so the
    ///     user remembers they have something cooking over there
    ///   - `switchSession` / `createNewSession` stash decision — bg
    ///     tasks need the same in-memory preservation as fg ones, or
    ///     their stream events have nowhere to land after navigation
    ///   - `deleteSession` cancel sweep — both kinds become orphans on
    ///     the gateway if we don't cancel them
    func hasInflightTask(inSession sessionId: UUID) -> Bool {
        foregroundTaskIds.contains(where: { taskSessionMap[$0] == sessionId })
            || backgroundTaskIds.contains(where: { taskSessionMap[$0] == sessionId })
    }

    /// Recompute `isSendingMessage` based on whether the currently visible
    /// session has any foreground task in flight. Must be called whenever
    /// `foregroundTaskIds`, `selectedAgentId`, `selectedSessionIdByAgent[agentId]`,
    /// or `taskSessionMap` changes — otherwise the input lock won't track
    /// the visible session correctly.
    private func recomputeIsSendingMessage() {
        guard let sid = selectedSessionIdByAgent[selectedAgentId] else {
            isSendingMessage = false
            return
        }
        isSendingMessage = hasForegroundTask(inSession: sid)
    }

    /// Single-point removal of every piece of per-task tracking state.
    /// Every task-exit path must run through this — a partial cleanup
    /// leaves stale taskSessionMap/taskAgentMap entries that keep
    /// isSendingMessage and hasInflightTask(inSession:) wrong until the
    /// next app launch.
    private func clearTaskTracking(_ msgId: UUID) {
        activeChatRuns.removeValue(forKey: msgId)
        taskSessionKeyOverride.removeValue(forKey: msgId)
        foregroundTaskIds.remove(msgId)
        backgroundTaskIds.remove(msgId)
        taskAgentMap.removeValue(forKey: msgId)
        taskSessionMap.removeValue(forKey: msgId)
        recomputeIsSendingMessage()
    }

    /// Cancel every task (fg + bg) currently bound to `sessionId`. Only
    /// used by `deleteSession` — deleting a session while tasks are
    /// running on it makes no sense (the destination for the output is
    /// disappearing). For switchSession / createNewSession we instead
    /// stash the session's state into `chatMessagesByInactiveSession` so
    /// tasks can keep running and route output to the right place when
    /// the user comes back.
    ///
    /// Includes `.background` tasks: they're also bound to a sessionId
    /// via `taskSessionMap`, and if the session is deleted they'd become
    /// gateway-side orphans the same as foreground ones.
    private func cancelTasks(inSession sessionId: UUID) {
        let fg = foregroundTaskIds.filter { taskSessionMap[$0] == sessionId }
        let bg = backgroundTaskIds.filter { taskSessionMap[$0] == sessionId }
        for msgId in fg.union(bg) {
            cancelChat(msgId)
        }
    }

    /// Look up a message by id in whichever bucket currently holds it —
    /// the active per-agent map, or the inactive-sessions map for tasks
    /// whose owning session the user has navigated away from. Returns
    /// the message (read-only). Stream handlers use this for status
    /// checks ("don't overwrite a .cancelled message with a delta")
    /// without having to know where the message lives.
    private func findMessage(byId msgId: UUID) -> ChatMessage? {
        for messages in chatMessagesByAgent.values {
            if let msg = messages.first(where: { $0.id == msgId }) {
                return msg
            }
        }
        if let sessionId = taskSessionMap[msgId],
           let msg = chatMessagesByInactiveSession[sessionId]?.first(where: { $0.id == msgId }) {
            return msg
        }
        return nil
    }
    @Published var selectedAgentId: String = "main"
    @Published var availableAgents: [AgentOption] = [AgentOption(id: "main", name: "main", emoji: "", description: "", model: "", division: "")]

    // Agent Settings Panel state
    @Published var agentSettingsOpen: Bool = false
    @Published var selectedAgentDetail: SubAgentInfo?
    @Published var availableModelGroups: [ProviderModelGroup] = []
    @Published var availableModelsForSettings: [ModelOption] = []

    /// Internal agents managed by the app, hidden from user-facing lists.
    static let internalAgentIds: Set<String> = ["help-assistant"]

    /// Resolve an agent's on-disk workspace directory, faithfully replicating
    /// openclaw's `resolveAgentWorkspaceDir(cfg, agentId)`:
    ///   1. an explicit `agents.list[].workspace` always wins
    ///   2. otherwise the *default agent* — the first entry with `default: true`,
    ///      else the first entry in `agents.list`, else "main" — uses
    ///      `agents.defaults.workspace` (or the bare `~/.openclaw/workspace`)
    ///   3. every other agent uses `~/.openclaw/workspace-<id>`
    ///
    /// Why this exists: the old code hardcoded "main → ~/.openclaw/workspace",
    /// which is only correct when "main" happens to be the default agent. When
    /// another agent is listed first (e.g. `commander`), the runtime resolves
    /// main to `~/.openclaw/workspace-main`, but the UI kept pointing at the
    /// stale bare `workspace` dir — so the file browser, terminal, persona
    /// editor and IDENTITY.md parsing all looked at the wrong folder.
    static func resolveAgentWorkspace(_ agentId: String, config: [String: Any]) -> String {
        let baseDir = NSString("~/.openclaw").expandingTildeInPath
        let agentsSection = config["agents"] as? [String: Any]
        let list = agentsSection?["list"] as? [[String: Any]] ?? []

        // 1. explicit per-agent workspace
        if let entry = list.first(where: { ($0["id"] as? String) == agentId }),
           let ws = (entry["workspace"] as? String)?.trimmingCharacters(in: .whitespaces),
           !ws.isEmpty {
            return (ws as NSString).expandingTildeInPath
        }

        // 2. default agent id: first default:true, else first list entry, else "main"
        let defaultAgentId: String =
            (list.first(where: { ($0["default"] as? Bool) == true })?["id"] as? String)
            ?? (list.first?["id"] as? String)
            ?? "main"

        if agentId == defaultAgentId {
            if let defWs = ((agentsSection?["defaults"] as? [String: Any])?["workspace"] as? String)?
                .trimmingCharacters(in: .whitespaces), !defWs.isEmpty {
                return (defWs as NSString).expandingTildeInPath
            }
            return (baseDir as NSString).appendingPathComponent("workspace")
        }

        // 3. non-default agent
        return (baseDir as NSString).appendingPathComponent("workspace-\(agentId)")
    }

    /// Disk-reading convenience: parses `~/.openclaw/openclaw.json` then defers
    /// to `resolveAgentWorkspace(_:config:)`. Safe to call from view-layer
    /// computed properties (openclaw.json is tiny).
    static func resolveAgentWorkspace(_ agentId: String) -> String {
        let configPath = NSString("~/.openclaw/openclaw.json").expandingTildeInPath
        let config = FileManager.default.contents(atPath: configPath)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        return resolveAgentWorkspace(agentId, config: config)
    }

    func loadAvailableAgents() {
        let configPath = NSString("~/.openclaw/openclaw.json").expandingTildeInPath
        let baseDir = NSString("~/.openclaw").expandingTildeInPath
        var agents: [AgentOption] = []

        let previousSelectedAgentId = selectedAgentId

        // Ensure commander exists in openclaw.json before loading
        Self.ensureCommanderInConfig(configPath: configPath, baseDir: baseDir)

        // Seed a sane wall-clock timeout floor. openclaw's built-in default is
        // 600s (10 min), which silently aborts long autonomous runs (browser
        // checkout flows, multi-step research). We don't predict per-task
        // length (the client can't see whether a turn will use tools) — instead
        // we raise the single global cap to 1h as a *backstop* against
        // forgotten/stuck runs, and rely on the visible cancel button + elapsed
        // indicator + litellm cost limits for everything else. Only seeds when
        // the user hasn't set their own value.
        Self.ensureAgentDefaultsTimeout(configPath: configPath)

        if let data = FileManager.default.contents(atPath: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let agentsSection = json["agents"] as? [String: Any] {
            // Pick up gateway concurrency cap from agents.defaults.maxConcurrent.
            // Used by the chat header's concurrent-task badge so the user can
            // see how close they are to gateway queuing kicking in.
            if let defaults = agentsSection["defaults"] as? [String: Any],
               let max = defaults["maxConcurrent"] as? Int, max > 0 {
                maxConcurrentTasks = max
            } else {
                maxConcurrentTasks = 4
            }
        }

        if let data = FileManager.default.contents(atPath: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let agentsSection = json["agents"] as? [String: Any],
           let agentList = agentsSection["list"] as? [[String: Any]] {
            for entry in agentList {
                guard let agentId = entry["id"] as? String else { continue }

                // Skip internal agents (commander, help-assistant) from user-facing lists
                if Self.internalAgentIds.contains(agentId) { continue }

                // Determine workspace path for this agent (faithful to openclaw's
                // resolveAgentWorkspaceDir — NOT a hardcoded "main → workspace").
                let workspace = Self.resolveAgentWorkspace(agentId, config: json)

                // Read IDENTITY.md and parse name from file first, fall back to config.
                let identityPath = (workspace as NSString).appendingPathComponent("IDENTITY.md")
                let identityContent = (try? String(contentsOfFile: identityPath, encoding: .utf8)) ?? ""
                let parsed = PersonaViewModel.parseIdentity(identityContent)

                let identity = entry["identity"] as? [String: Any]

                let name: String = {
                    if !parsed.name.isEmpty { return parsed.name }
                    if let n = identity?["name"] as? String, !n.isEmpty { return n }
                    return entry["name"] as? String ?? agentId
                }()

                // Extract agent description from IDENTITY.md (text after ---) and SOUL.md
                let agentDescription = Self.extractAgentDescription(workspace: workspace, identityContent: identityContent)

                let model = entry["model"] as? String ?? ""

                // Resolve division: from IDENTITY.md first, then marketplace catalog, then "Custom"
                let division: String = {
                    if !parsed.division.isEmpty { return parsed.division }
                    if let marketplaceAgent = MarketplaceCatalog.shared.agents.first(where: { $0.id == agentId }) {
                        return marketplaceAgent.division
                    }
                    if agentId == "main" || agentId == "commander" { return "" }
                    return "Custom"
                }()

                agents.append(AgentOption(id: agentId, name: name, emoji: "", description: agentDescription, model: model, division: division))
            }
        }

        // Ensure "main" is always present
        if !agents.contains(where: { $0.id == "main" }) {
            // Even for main fallback, try reading from IDENTITY.md
            let mainWorkspace = Self.resolveAgentWorkspace("main")
            let mainIdentityPath = (mainWorkspace as NSString).appendingPathComponent("IDENTITY.md")
            let mainContent = (try? String(contentsOfFile: mainIdentityPath, encoding: .utf8)) ?? ""
            let mainParsed = PersonaViewModel.parseIdentity(mainContent)
            let mainName = mainParsed.name.isEmpty ? "main" : mainParsed.name
            let mainDesc = Self.extractAgentDescription(workspace: mainWorkspace, identityContent: mainContent)
            agents.insert(AgentOption(id: "main", name: mainName, emoji: "", description: mainDesc, model: "", division: ""), at: 0)
        }

        availableAgents = agents

        // Only reset selection if current agent no longer exists and it was not explicitly set by user
        if !agents.contains(where: { $0.id == previousSelectedAgentId }) {
            selectedAgentId = "main"
        } else {
            // Restore the previous selection to preserve chat history
            selectedAgentId = previousSelectedAgentId
        }
    }

    /// Default wall-clock cap (seconds) seeded into agents.defaults.timeoutSeconds
    /// when the user hasn't configured one. 1h backstop, NOT a per-task estimate.
    static let seededDefaultTimeoutSeconds = 3600

    /// Seed `agents.defaults.timeoutSeconds` in openclaw.json if absent.
    ///
    /// openclaw ships a 600s (10 min) default that hard-aborts long autonomous
    /// runs. We raise the floor to 1h so legitimate long tasks (browser
    /// automation, deep research) aren't cut off mid-run. This is a single
    /// global backstop — we deliberately do NOT vary it per agent (agent
    /// identity is a poor predictor of task length; a `main` turn can be a 2s
    /// Q&A or a 20-min checkout). Containment of stuck/forgotten runs is handled
    /// by: the always-visible cancel button, the elapsed-time indicator, and
    /// litellm-side cost limits (max_input_tokens / budgets). Idempotent and
    /// non-destructive: only writes when the key is missing, so a user who set
    /// their own value (including 0 = "no timeout") is never overridden.
    private static func ensureAgentDefaultsTimeout(configPath: String) {
        guard let data = FileManager.default.contents(atPath: configPath),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        var agentsSection = json["agents"] as? [String: Any] ?? [:]
        var defaults = agentsSection["defaults"] as? [String: Any] ?? [:]

        // Respect any existing value (including an explicit 0). Only seed when
        // the key is entirely absent.
        if defaults["timeoutSeconds"] != nil { return }

        defaults["timeoutSeconds"] = seededDefaultTimeoutSeconds
        agentsSection["defaults"] = defaults
        json["agents"] = agentsSection

        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: URL(fileURLWithPath: configPath))
        }
    }

    /// Ensure commander agent entry exists in openclaw.json.
    /// Called early in loadAvailableAgents() so commander is always visible in the UI.
    private static func ensureCommanderInConfig(configPath: String, baseDir: String) {
        guard let data = FileManager.default.contents(atPath: configPath),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        var agentsSection = json["agents"] as? [String: Any] ?? [:]
        var agentList = agentsSection["list"] as? [[String: Any]] ?? []

        // Already exists — nothing to do
        if agentList.contains(where: { ($0["id"] as? String) == "commander" }) { return }

        let agentDir = (baseDir as NSString).appendingPathComponent("agents/commander/agent")
        let workspaceDir = (baseDir as NSString).appendingPathComponent("workspace-commander")

        // Create directories
        try? FileManager.default.createDirectory(atPath: agentDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: workspaceDir, withIntermediateDirectories: true)

        // Write IDENTITY.md
        let identityContent = """
        # IDENTITY.md - Who Am I?

        - **Name:** Commander
        - **Creature:** AI Task Orchestrator
        - **Vibe:** Precise, structured, efficient
        """
        let identityPath = (workspaceDir as NSString).appendingPathComponent("IDENTITY.md")
        try? identityContent.write(toFile: identityPath, atomically: true, encoding: .utf8)

        // Add commander entry to config
        let commanderEntry: [String: Any] = [
            "id": "commander",
            "name": "commander",
            "default": false,
            "identity": [
                "name": "Commander",
                "emoji": "🎯"
            ],
            "agentDir": agentDir,
            "workspace": workspaceDir
        ]
        agentList.append(commanderEntry)
        agentsSection["list"] = agentList
        json["agents"] = agentsSection

        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: URL(fileURLWithPath: configPath))
        }
    }

    /// Extract a concise agent description from IDENTITY.md (free text after ---),
    /// SOUL.md ("## You Are" or "## 🧠 Your Identity & Memory" Role line),
    /// and AGENTS.md ("## When to Use" section).
    static func extractAgentDescription(workspace: String, identityContent: String) -> String {
        var parts: [String] = []

        // 1. IDENTITY.md: text after the first "---" separator
        if let separatorRange = identityContent.range(of: "\n---") {
            let afterSeparator = String(identityContent[separatorRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !afterSeparator.isEmpty && !afterSeparator.hasPrefix("This isn't just metadata") && !afterSeparator.hasPrefix("_Fill") {
                parts.append(afterSeparator)
            }
        }

        // 2. SOUL.md: extract "## You Are" section content
        let soulPath = (workspace as NSString).appendingPathComponent("SOUL.md")
        if let soulContent = try? String(contentsOfFile: soulPath, encoding: .utf8) {
            // Try "## You Are" first (user-created agents)
            if let youAreRange = soulContent.range(of: "## You Are") {
                let afterYouAre = String(soulContent[youAreRange.upperBound...])
                let sectionContent: String
                if let nextHeading = afterYouAre.range(of: "\n## ") {
                    sectionContent = String(afterYouAre[..<nextHeading.lowerBound])
                } else {
                    sectionContent = afterYouAre
                }
                let trimmed = sectionContent.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    parts.append(trimmed)
                }
            }
            // Fallback: "## 🧠 Your Identity & Memory" — extract Role line (marketplace agents)
            else if parts.isEmpty, let identityRange = soulContent.range(of: "Identity", options: .caseInsensitive) {
                let afterHeader = String(soulContent[identityRange.upperBound...])
                let sectionEnd = afterHeader.range(of: "\n## ")?.lowerBound ?? afterHeader.endIndex
                let section = String(afterHeader[..<sectionEnd])

                // Extract "- **Role**: ..." line
                for line in section.components(separatedBy: "\n") {
                    let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                    if trimmedLine.lowercased().contains("**role**") {
                        let roleText = trimmedLine
                            .replacingOccurrences(of: "- **Role**:", with: "")
                            .replacingOccurrences(of: "- **Role:**", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        if !roleText.isEmpty {
                            parts.append(roleText)
                        }
                        break
                    }
                }
            }
        }

        // 3. AGENTS.md: extract "## When to Use" section
        let agentsPath = (workspace as NSString).appendingPathComponent("AGENTS.md")
        if let agentsContent = try? String(contentsOfFile: agentsPath, encoding: .utf8) {
            if let whenRange = agentsContent.range(of: "## When to Use") {
                let afterWhen = String(agentsContent[whenRange.upperBound...])
                let sectionContent: String
                if let nextHeading = afterWhen.range(of: "\n## ") {
                    sectionContent = String(afterWhen[..<nextHeading.lowerBound])
                } else {
                    sectionContent = afterWhen
                }
                let trimmed = sectionContent.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    parts.append("When: \(trimmed)")
                }
            }
        }

        // Combine and truncate to keep prompt compact
        let combined = parts.joined(separator: " | ")
        if combined.count > 300 {
            return String(combined.prefix(300)) + "..."
        }
        return combined
    }

    // MARK: - Chat Helpers

    /// Compose the gateway sessionKey for a given (agent, sessionId) pair.
    ///
    /// Previously this was hardcoded `"agent:<id>:main"` for every session —
    /// so multiple UI "sessions" for the same agent all shared one server
    /// conversation context, leaking memory between them (you'd ask about
    /// X in session A, switch to session B, and the assistant would still
    /// "remember" X). Including the sessionId in the key isolates each UI
    /// session into its own gateway thread.
    private func sessionKeyForAgent(_ agentId: String, sessionId: UUID) -> String {
        if let projectId = activeProjectId(forAgent: agentId) {
            return "agent:\(agentId):project:\(projectId):\(sessionId.uuidString)"
        }
        return "agent:\(agentId):\(sessionId.uuidString)"
    }

    private func activeProjectId(forAgent agentId: String) -> String? {
        if let sessionId = selectedSessionIdByAgent[agentId],
           let meta = sessionMetadata(for: sessionId) {
            return meta.projectId
        }
        return activeProjectIdByAgent[agentId] ?? nil
    }

    private func activeProject(forAgent agentId: String) -> ProjectRecord? {
        guard let projectId = activeProjectId(forAgent: agentId) else { return nil }
        return projectsById[projectId]
    }

    private func sessionMetadata(for sessionId: UUID) -> ChatSessionMetadata? {
        if let pending = pendingSessionMetadataByAgent.values.first(where: { $0.id == sessionId }) {
            return pending
        }
        return chatSessionStore.index.first { $0.id == sessionId }
    }

    private struct LocalImageReviewChunkResult {
        let chunkIndex: Int
        let status: String
        let text: String
    }

    private func runLocalImageReviewBatch(
        userText: String,
        attachments: [URL],
        msgId: UUID,
        agentId: String,
        agentEmoji: String?
    ) async {
        let store = ImageReviewBatchStore()

        defer {
            clearTaskTracking(msgId)
        }

        do {
            let batch = try await Task.detached(priority: .utility) {
                try ImageReviewBatchStore().createBatch(from: attachments, messageText: userText)
            }.value

            guard let batch else {
                let error = "No supported image files were found in the uploaded attachments."
                updateMessage(msgId: msgId, content: error, status: .completed, agentId: agentId, agentEmoji: agentEmoji)
                return
            }

            try store.markBatch(batch, status: .running)
            let manifest = try store.loadManifest(for: batch)
            updateMessage(
                msgId: msgId,
                content: localImageReviewProgressMessage(batch: batch, completedChunks: 0),
                status: .loading,
                agentId: agentId,
                agentEmoji: agentEmoji
            )

            var chunkResults: [LocalImageReviewChunkResult] = []
            for chunkIndex in 0..<batch.chunkCount {
                if findMessage(byId: msgId)?.taskStatus == .cancelled {
                    try? store.markBatch(batch, status: .cancelled, completedAt: Date())
                    return
                }

                let entries = manifest.filter { $0.chunkIndex == chunkIndex }
                let prompt = ImageReviewBatchStore.buildChunkReviewPrompt(
                    batch: batch,
                    chunkIndex: chunkIndex,
                    entries: entries,
                    userMessage: userText
                )
                let sessionKey = ImageReviewBatchStore.chunkSessionKey(
                    agentId: agentId,
                    batchId: batch.id,
                    chunkIndex: chunkIndex
                )
                let composerModelOverride = activeComposerModel.trimmingCharacters(in: .whitespacesAndNewlines)
                let chunkResult = await runLocalImageReviewChunk(
                    sessionKey: sessionKey,
                    prompt: prompt,
                    msgId: msgId,
                    modelOverride: composerModelOverride
                )
                let result = LocalImageReviewChunkResult(
                    chunkIndex: chunkIndex,
                    status: chunkResult.status,
                    text: chunkResult.text
                )
                chunkResults.append(result)
                try store.appendChunkResult(
                    batch: batch,
                    chunkIndex: chunkIndex,
                    status: result.status,
                    responseText: result.text
                )

                updateMessage(
                    msgId: msgId,
                    content: localImageReviewProgressMessage(batch: batch, completedChunks: chunkIndex + 1),
                    status: .loading,
                    agentId: agentId,
                    agentEmoji: agentEmoji
                )

                if result.status != "completed" {
                    try store.markBatch(batch, status: .failed, completedAt: Date())
                    updateMessage(
                        msgId: msgId,
                        content: localImageReviewFinalMessage(batch: batch, chunkResults: chunkResults, failed: true),
                        status: .completed,
                        agentId: agentId,
                        agentEmoji: agentEmoji
                    )
                    return
                }
            }

            try writeLocalImageReviewReport(batch: batch, userText: userText, chunkResults: chunkResults)
            try store.markBatch(batch, status: .completed, completedAt: Date())
            _ = try? store.cleanupImageCache()
            updateMessage(
                msgId: msgId,
                content: localImageReviewFinalMessage(batch: batch, chunkResults: chunkResults, failed: false),
                status: .completed,
                agentId: agentId,
                agentEmoji: agentEmoji
            )
        } catch {
            let message = "Local image review batch failed: \(error.localizedDescription)"
            updateMessage(msgId: msgId, content: message, status: .completed, agentId: agentId, agentEmoji: agentEmoji)
        }
    }

    private func runLocalImageReviewChunk(
        sessionKey: String,
        prompt: String,
        msgId: UUID,
        modelOverride: String
    ) async -> (status: String, text: String) {
        let subscriberId = msgId.uuidString
        let eventStream = gatewayClient.subscribeToEvents(subscriberId: subscriberId)
        taskSessionKeyOverride[msgId] = sessionKey

        defer {
            gatewayClient.unsubscribe(subscriberId: subscriberId)
            activeChatRuns.removeValue(forKey: msgId)
            taskSessionKeyOverride.removeValue(forKey: msgId)
        }

        // Non-fatal: a rejected patch just means the chunk runs on the
        // session's current model instead of the composer override.
        if !modelOverride.isEmpty {
            let patched = await gatewayClient.patchSessionModel(sessionKey: sessionKey, model: modelOverride)
            if !patched {
                chatLog.warning("phase=session_model_patch_failed session=\(sessionKey, privacy: .public) model=\(modelOverride, privacy: .public) — running image review chunk with the session's current model")
            }
        }

        guard let runId = await gatewayClient.chatSend(sessionKey: sessionKey, message: prompt, attachments: nil) else {
            return ("failed", "Failed to send local image review chunk.")
        }
        activeChatRuns[msgId] = runId

        var accumulatedText = ""
        for await event in eventStream {
            switch event {
            case .delta(let eventRunId, let eventSessionKey, let text):
                guard eventRunId == runId, eventSessionKey == sessionKey, !text.isEmpty else { continue }
                accumulatedText = text
            case .final_(let eventRunId, let eventSessionKey, let text):
                guard eventRunId == runId, eventSessionKey == sessionKey else { continue }
                var finalText = text.isEmpty ? accumulatedText : text
                if finalText.isEmpty,
                   let historyText = await gatewayClient.fetchLastAssistantMessage(sessionKey: sessionKey) {
                    finalText = historyText
                }
                return ("completed", finalText.isEmpty ? "Chunk completed." : finalText)
            case .aborted(let eventRunId, let eventSessionKey):
                guard eventRunId == runId, eventSessionKey == sessionKey else { continue }
                return ("cancelled", accumulatedText)
            case .error(let eventRunId, let eventSessionKey, let message):
                guard eventRunId == runId, eventSessionKey == sessionKey else { continue }
                return ("failed", message)
            case .activity:
                continue
            }
        }
        return ("failed", accumulatedText.isEmpty ? "Connection interrupted before this chunk completed." : accumulatedText)
    }

    private func localImageReviewProgressMessage(batch: ImageReviewBatchStore.Batch, completedChunks: Int) -> String {
        """
        Local image review batch is running.

        Batch ID: \(batch.id)
        Images: \(batch.imageCount)
        Chunks: \(completedChunks)/\(batch.chunkCount)
        Manifest: \(batch.manifestURL.path)
        Results: \(batch.resultsURL.path)
        """
    }

    private func localImageReviewFinalMessage(
        batch: ImageReviewBatchStore.Batch,
        chunkResults: [LocalImageReviewChunkResult],
        failed: Bool
    ) -> String {
        let status = failed ? "Local image review batch stopped before all chunks completed." : "Local image review batch completed."
        let completed = chunkResults.filter { $0.status == "completed" }.count
        return """
        \(status)

        Batch ID: \(batch.id)
        Images: \(batch.imageCount)
        Completed chunks: \(completed)/\(batch.chunkCount)
        Manifest: \(batch.manifestURL.path)
        Chunk results: \(batch.resultsURL.path)
        Report: \(batch.reportURL.path)
        """
    }

    private func writeLocalImageReviewReport(
        batch: ImageReviewBatchStore.Batch,
        userText: String,
        chunkResults: [LocalImageReviewChunkResult]
    ) throws {
        let sections = chunkResults
            .sorted { $0.chunkIndex < $1.chunkIndex }
            .map { result in
                """
                ## Chunk \(result.chunkIndex + 1)

                Status: \(result.status)

                \(result.text)
                """
            }
            .joined(separator: "\n\n")
        let report = """
        # Local Image Review Batch

        Batch ID: \(batch.id)
        Images: \(batch.imageCount)
        Chunks: \(batch.chunkCount)
        Request: \(userText)

        \(sections)
        """
        try Data(report.utf8).write(to: batch.reportURL, options: .atomic)
    }

    private func updateMessage(
        msgId: UUID,
        content: String,
        status: ChatMessage.TaskStatus,
        agentId: String,
        agentEmoji: String?,
        activityEvents: [ChatActivityEvent]? = nil
    ) {
        let existing = findMessage(byId: msgId)
        let resolvedActivityEvents = activityEvents ?? (existing?.activityEvents ?? [])
        let resolvedCompletedAt = status.isTerminal ? (existing?.completedAt ?? Date()) : nil
        let newMsg = ChatMessage(
            role: .assistant, content: content,
            agentId: agentId, agentEmoji: agentEmoji,
            taskStatus: status, id: msgId,
            timestamp: existing?.timestamp,
            completedAt: resolvedCompletedAt,
            activityEvents: resolvedActivityEvents
        )
        // Route to wherever this msgId currently lives. The task may have
        // started in the (then-visible) active session and migrated to
        // chatMessagesByInactiveSession when the user navigated away —
        // stream events still need to find it.
        if let idx = chatMessagesByAgent[agentId]?.firstIndex(where: { $0.id == msgId }) {
            var messages = chatMessagesByAgent[agentId] ?? []
            messages[idx] = newMsg
            chatMessagesByAgent[agentId] = messages
            logChat("UPDATE_MSG (active): agent=\(agentId), contentLen=\(content.count), status=\(status), totalMsgs=\(messages.count)")
            return
        }
        if let sessionId = taskSessionMap[msgId],
           let idx = chatMessagesByInactiveSession[sessionId]?.firstIndex(where: { $0.id == msgId }) {
            var messages = chatMessagesByInactiveSession[sessionId] ?? []
            messages[idx] = newMsg
            chatMessagesByInactiveSession[sessionId] = messages
            logChat("UPDATE_MSG (inactive): session=\(sessionId.uuidString.prefix(8)), contentLen=\(content.count), status=\(status), totalMsgs=\(messages.count)")
            return
        }
        logChat("UPDATE_FAILED: agent=\(agentId), msgId=\(msgId.uuidString.prefix(8)) NOT FOUND in active or inactive!")
    }

    private func mergeActivityEvent(_ event: GatewayActivityEvent, into events: inout [ChatActivityEvent]) {
        let kind = ChatActivityEvent.Kind(gatewayKind: event.kind)
        if let idx = events.firstIndex(where: { $0.kind == kind }) {
            let existing = events[idx]
            events[idx] = ChatActivityEvent(
                kind: existing.kind,
                count: existing.count + 1,
                details: event.detail.map { existing.details + [$0] } ?? existing.details,
                ordinal: idx
            )
        } else {
            events.append(ChatActivityEvent(
                kind: kind,
                count: 1,
                details: event.detail.map { [$0] } ?? [],
                ordinal: events.count
            ))
        }
    }

    private func appendProgressActivityText(_ text: String, into events: inout [ChatActivityEvent]) {
        let normalized = Self.normalizedWorkingProgressText(text)
        guard !normalized.isEmpty else { return }
        if events.last?.kind == .progressUpdate, events.last?.detail == normalized {
            return
        }
        events.append(ChatActivityEvent(
            kind: .progressUpdate,
            count: 1,
            details: [normalized],
            ordinal: events.count
        ))
    }

    private func activityEventsForDisplay(
        committedEvents: [ChatActivityEvent],
        accumulatedText: String,
        committedWorkingText: String
    ) -> [ChatActivityEvent] {
        var displayEvents = committedEvents
        appendProgressActivityText(
            Self.uncommittedWorkingProgressText(
                accumulatedText: accumulatedText,
                committedWorkingText: committedWorkingText
            ),
            into: &displayEvents
        )
        return displayEvents
    }

    /// Treat text that appears before the next structured activity as working
    /// transcript. This preserves the model's own progress wording without
    /// parsing language or asking the model for a second summary.
    private static func uncommittedWorkingProgressText(
        accumulatedText: String,
        committedWorkingText: String
    ) -> String {
        guard !accumulatedText.isEmpty else { return "" }
        guard !committedWorkingText.isEmpty else {
            return normalizedWorkingProgressText(accumulatedText)
        }
        if accumulatedText.hasPrefix(committedWorkingText) {
            return normalizedWorkingProgressText(String(accumulatedText.dropFirst(committedWorkingText.count)))
        }
        let commonPrefix = accumulatedText.commonPrefix(with: committedWorkingText)
        guard !commonPrefix.isEmpty else {
            return normalizedWorkingProgressText(accumulatedText)
        }
        return normalizedWorkingProgressText(String(accumulatedText.dropFirst(commonPrefix.count)))
    }

    private static func visibleAssistantText(from text: String, committedWorkingText: String) -> String {
        guard !committedWorkingText.isEmpty, text.hasPrefix(committedWorkingText) else {
            return text
        }
        return String(text.dropFirst(committedWorkingText.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedWorkingProgressText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func appendBackgroundNotification(agentId: String, agentEmoji: String?, completed: Bool, msgId: UUID) {
        let agentName = availableAgents.first(where: { $0.id == agentId })?.name ?? agentId
        if completed {
            let notifyContent = String(format: String(localized: "✅ Background task from **%@** completed", bundle: LanguageManager.shared.localizedBundle), agentName)
            let notifyMsg = ChatMessage(role: .assistant, content: notifyContent, agentId: agentId, agentEmoji: agentEmoji, scrollTargetId: msgId)
            chatMessagesByAgent[agentId, default: []].append(notifyMsg)
        } else {
            let notifyContent = String(format: String(localized: "⚠️ Background task from **%@** timed out", bundle: LanguageManager.shared.localizedBundle), agentName)
            let notifyMsg = ChatMessage(role: .assistant, content: notifyContent, agentId: agentId, agentEmoji: agentEmoji)
            chatMessagesByAgent[agentId, default: []].append(notifyMsg)
        }
    }

    func sendChatMessage(_ text: String, attachments: [URL] = []) async {
        // Route to commander only when the user is on the commander tab
        if let collabVM = collabViewModel, collabVM.isRunning,
           selectedAgentId == "commander",
           !text.hasPrefix("/") {
            let currentAgent = selectedAgentId
            let userMessage = ChatMessage(role: .user, content: text)
            chatMessagesByAgent[currentAgent, default: []].append(userMessage)
            isSendingMessage = true
            let reply = await collabVM.handleUserMessage(text)
            let noReply = String(localized: "No response from AI.", bundle: LanguageManager.shared.localizedBundle)
            chatMessagesByAgent[currentAgent, default: []].append(ChatMessage(role: .assistant, content: reply ?? noReply, agentId: "commander"))
            isSendingMessage = false
            return
        }

        let userMessage = ChatMessage(role: .user, content: text, attachments: attachments)
        let currentAgentId = selectedAgentId
        chatMessagesByAgent[currentAgentId, default: []].append(userMessage)
        logChat("USER_MSG: agent=\(currentAgentId), totalMsgs=\(chatMessagesByAgent[currentAgentId]?.count ?? 0)")

        let currentAgentEmoji: String? = nil
        // Bind the run to the agent's currently-active session. `ensureActiveSessionId`
        // mints one lazily if the agent has never had a session before, so this is
        // always non-nil after the call.
        let currentSessionId = ensureActiveSessionId(forAgent: currentAgentId,
                                                     seedMessages: chatMessagesByAgent[currentAgentId] ?? [])
        let sessionKey = sessionKeyForAgent(currentAgentId, sessionId: currentSessionId)
        let currentProject = activeProject(forAgent: currentAgentId)

        // Insert a placeholder assistant message for streaming updates
        let msgId = UUID()
        let placeholderMsg = ChatMessage(role: .assistant, content: "", agentId: currentAgentId, agentEmoji: currentAgentEmoji, taskStatus: .loading, id: msgId)
        chatMessagesByAgent[currentAgentId, default: []].append(placeholderMsg)
        logChat("PLACEHOLDER: agent=\(currentAgentId), msgId=\(msgId.uuidString.prefix(8)), totalMsgs=\(chatMessagesByAgent[currentAgentId]?.count ?? 0)")

        // Track as foreground task — bound to BOTH agent and session so we can
        // (a) route the cancel/abort to the right gateway sessionKey and
        // (b) decide which UI session owns this spinner.
        foregroundTaskIds.insert(msgId)
        taskAgentMap[msgId] = currentAgentId
        taskSessionMap[msgId] = currentSessionId
        recomputeIsSendingMessage()

        // Check gateway connection. Prefer the gateway's own rejection reason
        // (e.g. NOT_PAIRED / DEVICE_IDENTITY_REQUIRED, token mismatch) so the user
        // can act on it; only fall back to the generic message when we never got
        // a server response (TCP failed / handshake never reached the auth step).
        guard gatewayClient.isConnected else {
            let generic = String(localized: "Gateway is not connected. Please check the service status.", bundle: LanguageManager.shared.localizedBundle)
            let errorMsg: String
            if let lastErr = gatewayClient.lastConnectError {
                let detail = lastErr.detailCode.map { " (\($0))" } ?? ""
                errorMsg = "\(generic)\n[\(lastErr.code)\(detail)] \(lastErr.message)"
            } else {
                errorMsg = generic
            }
            updateMessage(msgId: msgId, content: errorMsg, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
            clearTaskTracking(msgId)
            return
        }

        if ImageReviewBatchStore.isImageReviewBatchCandidate(
            urls: attachments,
            messageText: text,
            selectedAgentId: currentAgentId
        ) {
            await runLocalImageReviewBatch(
                userText: text,
                attachments: attachments,
                msgId: msgId,
                agentId: currentAgentId,
                agentEmoji: currentAgentEmoji
            )
            return
        }

        let processed = attachmentProcessor.process(attachments)
        let baseMessage = text
            + ProjectSessionContextBuilder.message(for: currentProject)
            + processed.manifestText
        let composerModelOverride = activeComposerModel.trimmingCharacters(in: .whitespacesAndNewlines)

        // Subscribe to events BEFORE sending to avoid race condition
        let subscriberId = msgId.uuidString
        let eventStream = gatewayClient.subscribeToEvents(subscriberId: subscriberId)

        // Apply the composer model as a session-level override. Non-fatal by
        // design: a gateway that rejects `sessions.patch` (older builds, or a
        // connection it classifies as webchat) still runs the turn on the
        // session's current model, so warn instead of blocking the message.
        if !composerModelOverride.isEmpty, appliedSessionModels[sessionKey] != composerModelOverride {
            let patched = await gatewayClient.patchSessionModel(sessionKey: sessionKey, model: composerModelOverride)
            if patched {
                appliedSessionModels[sessionKey] = composerModelOverride
            } else {
                appliedSessionModels.removeValue(forKey: sessionKey)
                chatLog.warning("phase=session_model_patch_failed session=\(sessionKey, privacy: .public) model=\(composerModelOverride, privacy: .public) — sending with the session's current model")
                showErrorMessage(String(localized: "Could not switch to the selected model; sending with the current model.", bundle: LanguageManager.shared.localizedBundle))
            }
        }

        // Send the message
        let chatSendStart = ContinuousClock.now
        chatLog.info("phase=chat_send_start agent=\(currentAgentId, privacy: .public) session=\(currentSessionId.uuidString, privacy: .public) sessionKey=\(sessionKey, privacy: .public) model_override=\(composerModelOverride.isEmpty ? "default" : composerModelOverride, privacy: .public) message_len=\(baseMessage.count, privacy: .public) attachment_count=\(attachments.count, privacy: .public) inline_attachment_count=\(processed.inlineAttachments.count, privacy: .public)")
        let runId = await gatewayClient.chatSend(
            sessionKey: sessionKey,
            message: baseMessage,
            attachments: processed.inlineAttachments.isEmpty ? nil : processed.inlineAttachments
        )

        guard let runId = runId else {
            chatLog.warning("phase=chat_send_failed agent=\(currentAgentId, privacy: .public) session=\(currentSessionId.uuidString, privacy: .public) elapsed_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public)")
            let errorMsg = String(localized: "Failed to send message. Please try again.", bundle: LanguageManager.shared.localizedBundle)
            updateMessage(msgId: msgId, content: errorMsg, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
            gatewayClient.unsubscribe(subscriberId: subscriberId)
            clearTaskTracking(msgId)
            return
        }

        let chatSendAckAt = ContinuousClock.now
        chatLog.info("phase=chat_send_ack runId=\(runId, privacy: .public) agent=\(currentAgentId, privacy: .public) session=\(currentSessionId.uuidString, privacy: .public) elapsed_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public)")

        if !attachments.isEmpty {
            showSuccessMessage("Attachments sent as a selective manifest. Large files and folders will not be read wholesale.")
        }

        activeChatRuns[msgId] = runId
        chatLog.info("chat.send ok: runId=\(runId), subscriberId=\(subscriberId), bgTasks=\(self.backgroundTaskIds.count)")

        // Persist the run so we can recover via chat.history if the
        // app dies before the stream completes (force-quit, crash, OOM).
        // Removed in the defer block below on normal stream exit, so
        // typical runs never leave a stale entry.
        registerInFlightRun(
            runId: runId,
            sessionKey: sessionKey,
            msgId: msgId,
            sessionId: currentSessionId,
            agentId: currentAgentId,
            agentEmoji: currentAgentEmoji
        )

        // Abandonment safety net: only triggers when NO inbound traffic at all for the
        // entire `inactivityLimit` window. Modeled after Claude's API/SSE behavior — we
        // never want to declare a task failed purely because deltas came infrequently
        // (deep-thinking + long tools can be naturally silent for many minutes). The
        // 30s client heartbeat already proves WS liveness independently; this timer is
        // pure defense-in-depth for genuinely abandoned runs.
        //
        // Claude-style "prefer resume over fail": before marking `.timedOut`, attempt
        // a `chat.history` fetch first. If the gateway has more content than our
        // placeholder, the run actually completed gateway-side and we just missed the
        // final event (possible after long lid-closed sleep, dropped reconnect race,
        // etc.). Recover cleanly to `.completed` instead of falsely marking failed.
        let inactivityLimit: TimeInterval = inactivityTimeoutSeconds  // user-tunable, default 60 min
        let timeoutTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // check every 10s
                guard let self = self, !Task.isCancelled else { return }
                // Use the gateway-level timestamp: any inbound message resets it; nothing for
                // `inactivityLimit` means we're not getting anything (including ack/delta) from gateway.
                let elapsed = Date().timeIntervalSince(self.gatewayClient.lastMessageReceivedAt)
                if elapsed >= inactivityLimit {
                    if self.activeChatRuns[msgId] != nil {
                        // Step 1: try history recovery before declaring failure.
                        // 10s budget (matches GatewayClient.fetchLastAssistantMessage's own timeout).
                        let recovered = await self.gatewayClient.fetchLastAssistantMessage(sessionKey: sessionKey)
                        self.gatewayClient.unsubscribe(subscriberId: subscriberId)

                        await MainActor.run {
                            // Snapshot current placeholder length so we only adopt history
                            // if it strictly extends what we already have. Otherwise (history
                            // empty / shorter / unchanged) fall to the timedOut path.
                            let currentLen = self.findMessage(byId: msgId)?.content.count ?? 0
                            if let text = recovered, text.count > currentLen, !text.isEmpty {
                                chatLog.info("inactivity recovery succeeded: \(text.count) chars from history (placeholder had \(currentLen))")
                                self.updateMessage(msgId: msgId, content: text, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
                            } else {
                                chatLog.warning("inactivity timeout: no usable history, marking timedOut (elapsed=\(Int(elapsed))s)")
                                let timeoutMsg = String(localized: "The task timed out and has been terminated. You can try again or switch to another agent.", bundle: LanguageManager.shared.localizedBundle)
                                if let msg = self.findMessage(byId: msgId) {
                                    let content = msg.content.isEmpty
                                        ? timeoutMsg
                                        : msg.content + "\n\n---\n> ⚠️ " + timeoutMsg
                                    self.updateMessage(msgId: msgId, content: content, status: .timedOut, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
                                }
                            }
                            self.clearTaskTracking(msgId)
                        }
                    }
                    return
                }
            }
        }

        // Guarantee cleanup: no matter how the stream loop exits, reset state
        defer {
            timeoutTask.cancel()
            gatewayClient.unsubscribe(subscriberId: subscriberId)
            // Cleanup must happen on MainActor since these are @Published properties
            Task { @MainActor in
                self.clearTaskTracking(msgId)
                self.unregisterInFlightRun(msgId: msgId)
            }
        }

        // Stream events
        var accumulatedText = ""
        var committedWorkingText = ""
        var accumulatedActivityEvents: [ChatActivityEvent] = []
        var seenActivityEventKeys = Set<String>()
        var receivedTerminalEvent = false
        var emptyFinalCount = 0
        // Throttle message updates to prevent CPU 100% during fast streaming
        var lastUpdateTime = Date()
        let updateThrottleInterval: TimeInterval = 0.1  // Update at most every 100ms
        var didLogFirstEvent = false
        var didLogFirstDelta = false
        var didLogFirstActivity = false

        func logFirstGatewayEventIfNeeded(kind: String, eventRunId: String, eventSessionKey: String?) {
            guard !didLogFirstEvent else { return }
            didLogFirstEvent = true
            chatLog.info("phase=chat_first_event kind=\(kind, privacy: .public) runId=\(eventRunId, privacy: .public) sessionKey=\(eventSessionKey ?? "nil", privacy: .public) elapsed_from_send_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public) elapsed_after_ack_ms=\(Self.elapsedMillisecondsText(since: chatSendAckAt), privacy: .public)")
        }

        streamLoop: for await event in eventStream {

            switch event {
            case .activity(let eventRunId, _, let event):
                guard eventRunId == runId else { continue }
                logFirstGatewayEventIfNeeded(kind: "activity", eventRunId: eventRunId, eventSessionKey: nil)
                if !didLogFirstActivity {
                    didLogFirstActivity = true
                    chatLog.info("phase=chat_first_activity runId=\(eventRunId, privacy: .public) kind=\(event.kind.rawValue, privacy: .public) elapsed_from_send_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public) elapsed_after_ack_ms=\(Self.elapsedMillisecondsText(since: chatSendAckAt), privacy: .public)")
                }
                guard seenActivityEventKeys.insert(event.dedupeKey).inserted else { continue }
                let progressText = Self.uncommittedWorkingProgressText(
                    accumulatedText: accumulatedText,
                    committedWorkingText: committedWorkingText
                )
                if !progressText.isEmpty {
                    appendProgressActivityText(progressText, into: &accumulatedActivityEvents)
                    committedWorkingText = accumulatedText
                }
                mergeActivityEvent(event, into: &accumulatedActivityEvents)
                if let current = findMessage(byId: msgId),
                   current.taskStatus != .cancelled {
                    updateMessage(msgId: msgId, content: "", status: current.taskStatus, agentId: currentAgentId, agentEmoji: currentAgentEmoji, activityEvents: accumulatedActivityEvents)
                }

            case .delta(let eventRunId, let eventSessionKey, let text):
                guard eventRunId == runId else { continue }
                logFirstGatewayEventIfNeeded(kind: "delta", eventRunId: eventRunId, eventSessionKey: eventSessionKey)
                // Skip empty deltas (e.g. tool_use blocks with no text content)
                guard !text.isEmpty else {
                    chatLog.debug("chat delta: EMPTY text skipped, runId=\(eventRunId)")
                    continue
                }
                if !didLogFirstDelta {
                    didLogFirstDelta = true
                    chatLog.info("phase=chat_first_delta runId=\(eventRunId, privacy: .public) sessionKey=\(eventSessionKey, privacy: .public) text_len=\(text.count, privacy: .public) elapsed_from_send_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public) elapsed_after_ack_ms=\(Self.elapsedMillisecondsText(since: chatSendAckAt), privacy: .public)")
                }
                chatLog.debug("chat delta: runId=\(eventRunId), textLen=\(text.count)")
                // Gateway sends full accumulated text in each delta, so use replacement
                accumulatedText = text
                // A real delta arrived — reset the premature-final counter
                emptyFinalCount = 0

                // Only update UI if enough time has passed (throttle to prevent CPU 100%)
                let now = Date()
                if now.timeIntervalSince(lastUpdateTime) >= updateThrottleInterval {
                    lastUpdateTime = now
                    // Only update if not already in a terminal state. The
                    // placeholder may live in chatMessagesByAgent[agentId]
                    // (session still visible) or in chatMessagesByInactiveSession
                    // (user navigated to a different session mid-stream) —
                    // findMessage handles both.
                    if let current = findMessage(byId: msgId),
                       current.taskStatus != .cancelled {
                        let displayEvents = activityEventsForDisplay(
                            committedEvents: accumulatedActivityEvents,
                            accumulatedText: accumulatedText,
                            committedWorkingText: committedWorkingText
                        )
                        updateMessage(msgId: msgId, content: "", status: current.taskStatus, agentId: currentAgentId, agentEmoji: currentAgentEmoji, activityEvents: displayEvents)
                    }
                }

            case .final_(let eventRunId, let eventSessionKey, let text):
                guard eventRunId == runId else { continue }
                logFirstGatewayEventIfNeeded(kind: "final", eventRunId: eventRunId, eventSessionKey: eventSessionKey)
                chatLog.info("phase=chat_final runId=\(eventRunId, privacy: .public) sessionKey=\(eventSessionKey, privacy: .public) text_len=\(text.count, privacy: .public) accumulated_len=\(accumulatedText.count, privacy: .public) saw_delta=\(didLogFirstDelta, privacy: .public) elapsed_from_send_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public) elapsed_after_ack_ms=\(Self.elapsedMillisecondsText(since: chatSendAckAt), privacy: .public)")
                chatLog.info("chat final: runId=\(eventRunId), textLen=\(text.count), accumulatedLen=\(accumulatedText.count)")
                var finalText = Self.visibleAssistantText(
                    from: text.isEmpty ? accumulatedText : text,
                    committedWorkingText: committedWorkingText
                )
                // Fallback: when gateway final has no content (e.g. tool-heavy responses where
                // stripInlineDirectiveTagsForDisplay filtered all text), fetch from chat history
                if finalText.isEmpty {
                    chatLog.info("chat final empty — fetching chat.history as fallback")
                    if let historyText = await gatewayClient.fetchLastAssistantMessage(sessionKey: eventSessionKey) {
                        chatLog.info("chat.history fallback: got \(historyText.count) chars")
                        finalText = Self.visibleAssistantText(
                            from: historyText,
                            committedWorkingText: committedWorkingText
                        )
                    }
                }
                // If still no content, the gateway may have sent a premature final
                // while the task is still running (e.g. intermediate sub-run ended).
                // Skip the first empty final, but accept on the second — to avoid
                // background tasks getting stuck in "running" state forever.
                if finalText.isEmpty {
                    emptyFinalCount += 1
                    if emptyFinalCount < 2 {
                        chatLog.warning("chat final has no content — ignoring premature final #\(emptyFinalCount), continuing to wait")
                        continue
                    }
                    chatLog.warning("chat final has no content — accepting after \(emptyFinalCount) empty finals")
                    let doneMsg = String(localized: "Task completed.", bundle: LanguageManager.shared.localizedBundle)
                    finalText = doneMsg
                }
                receivedTerminalEvent = true
                let wasBackground = backgroundTaskIds.contains(msgId)
                updateMessage(msgId: msgId, content: finalText, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji, activityEvents: accumulatedActivityEvents)
                if wasBackground {
                    // Only emit the "background task completed" inline card when the
                    // user is still looking at the SAME session the task ran in.
                    // Otherwise we'd append it into whatever session is currently
                    // active for this agent — and `persistChangedSessions` would
                    // later save that orphan line into the wrong session's JSON
                    // (the v1.1.49 / v1.1.50 cross-session "answer in another
                    // conversation" bug). The real reply was already routed to
                    // the right place via `updateMessage` above, so navigating
                    // back to the original session shows the completed turn
                    // naturally — no notification needed there either.
                    if selectedSessionIdByAgent[currentAgentId] == taskSessionMap[msgId] {
                        appendBackgroundNotification(agentId: currentAgentId, agentEmoji: currentAgentEmoji, completed: true, msgId: msgId)
                    }
                }
                break streamLoop

            case .aborted(let eventRunId, _):
                guard eventRunId == runId else { continue }
                logFirstGatewayEventIfNeeded(kind: "aborted", eventRunId: eventRunId, eventSessionKey: nil)
                chatLog.info("phase=chat_aborted runId=\(eventRunId, privacy: .public) elapsed_from_send_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public) elapsed_after_ack_ms=\(Self.elapsedMillisecondsText(since: chatSendAckAt), privacy: .public)")
                receivedTerminalEvent = true
                if let current = findMessage(byId: msgId),
                   current.taskStatus != .cancelled {
                    updateMessage(msgId: msgId, content: "", status: .cancelled, agentId: currentAgentId, agentEmoji: currentAgentEmoji, activityEvents: accumulatedActivityEvents)
                }
                break streamLoop

            case .error(let eventRunId, _, let message):
                guard eventRunId == runId else { continue }
                logFirstGatewayEventIfNeeded(kind: "error", eventRunId: eventRunId, eventSessionKey: nil)
                chatLog.warning("phase=chat_error runId=\(eventRunId, privacy: .public) message_len=\(message.count, privacy: .public) elapsed_from_send_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public) elapsed_after_ack_ms=\(Self.elapsedMillisecondsText(since: chatSendAckAt), privacy: .public)")
                receivedTerminalEvent = true
                let errorContent = "⚠️ " + message
                // Ensure UI update happens on MainActor
                await MainActor.run {
                    self.updateMessage(msgId: msgId, content: errorContent, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji, activityEvents: accumulatedActivityEvents)
                }
                chatLog.warning("chat error: runId=\(runId), message=\(message)")
                break streamLoop
            }
        }

        // Stream ended without a terminal event — typically WebSocket dropped
        // (sleep / network blip / gateway restart) and `scheduleReconnect()`
        // finished our event continuations. Don't immediately declare the
        // task dead: in many cases the run actually COMPLETED on the gateway
        // during the disconnect window (LLM provider doesn't know about our
        // client disconnect), and we can recover the final reply via
        // `chat.history`.
        //
        // Strategy:
        //   1. Give WS up to 15s to reconnect (usual reconnect window is
        //      1-3s, longer on system wake from sleep)
        //   2. Once back online, ask gateway for the last assistant
        //      message in this session via `chat.history`
        //   3. If history has more content than we streamed → use it,
        //      mark `.completed` cleanly with no "interrupted" notice
        //   4. If history has nothing or is shorter → fall through to
        //      the legacy "Connection was interrupted" path
        if !receivedTerminalEvent {
            chatLog.warning("chat stream ended WITHOUT terminal event: runId=\(runId), accumulatedLen=\(accumulatedText.count) — attempting chat.history recovery")

            // Wait briefly for the WS to come back. Poll every 0.5s
            // rather than blocking on a single 30s sleep so we recover
            // as soon as the gateway is reachable.
            //
            // 30s window: must strictly exceed our reconnect backoff
            // ceiling (1+2+4+8 = 15s for the 4th attempt) plus the
            // connect.challenge round-trip + auth (~1-3s). 15s exactly
            // matched the backoff tail and lost the race on the 4th
            // retry; 30s gives the handshake comfortable headroom and
            // matches Anthropic SSE's typical reconnect tolerance.
            var recovered: String? = nil
            let recoveryDeadline = Date().addingTimeInterval(30)
            while Date() < recoveryDeadline {
                if gatewayClient.isConnected {
                    recovered = await gatewayClient.fetchLastAssistantMessage(sessionKey: sessionKey)
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            if let current = findMessage(byId: msgId),
               current.taskStatus != .completed && current.taskStatus != .cancelled && current.taskStatus != .timedOut {
                // Prefer history if it returned strictly more content than
                // what we managed to capture via streaming. The history
                // endpoint returns the FULL final assistant turn if the
                // run completed gateway-side, so this transparently
                // covers the "system slept while LLM finished" case.
                if let recoveredText = recovered, recoveredText.count > accumulatedText.count {
                    chatLog.info("chat.history recovered \(recoveredText.count) chars (streamed only \(accumulatedText.count))")
                    let recoveredVisibleText = Self.visibleAssistantText(
                        from: recoveredText,
                        committedWorkingText: committedWorkingText
                    )
                    updateMessage(msgId: msgId, content: recoveredVisibleText, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji, activityEvents: accumulatedActivityEvents)
                } else {
                    chatLog.warning("chat.history recovery failed or shorter than stream — marking interrupted")
                    let disconnectNote = String(localized: "Connection was interrupted. The response may be incomplete.", bundle: LanguageManager.shared.localizedBundle)
                    updateMessage(msgId: msgId, content: disconnectNote, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji, activityEvents: accumulatedActivityEvents)
                }
            }
        }
    }

    /// Move a foreground task to background, unlocking the input
    func moveTaskToBackground(_ msgId: UUID) {
        guard foregroundTaskIds.contains(msgId) else { return }
        foregroundTaskIds.remove(msgId)
        backgroundTaskIds.insert(msgId)
        recomputeIsSendingMessage()

        let bgLabel = String(localized: "⏳ Task running in background...", bundle: LanguageManager.shared.localizedBundle)

        // First look in the active per-agent map (the common case — auto-bg
        // fires from ThinkingIndicator which only renders for visible
        // placeholders).
        for agentId in chatMessagesByAgent.keys {
            if let idx = chatMessagesByAgent[agentId]?.firstIndex(where: { $0.id == msgId }) {
                let msg = chatMessagesByAgent[agentId]![idx]
                let content = msg.content.isEmpty ? bgLabel : msg.content
                var messages = chatMessagesByAgent[agentId]!
                messages[idx] = ChatMessage(
                    role: .assistant, content: content,
                    agentId: msg.agentId, agentEmoji: msg.agentEmoji,
                    taskStatus: .background, id: msgId
                )
                chatMessagesByAgent[agentId] = messages
                return
            }
        }

        // Fall back to the inactive stash. Reachable when the auto-bg
        // timer fires within the ~1s window between the user switching
        // sessions and `.onDisappear` cancelling the timer — without
        // this branch the placeholder keeps showing "Thinking…" forever
        // when the user navigates back, even though the task is
        // already tracked as background internally.
        if let sessionId = taskSessionMap[msgId],
           let idx = chatMessagesByInactiveSession[sessionId]?.firstIndex(where: { $0.id == msgId }) {
            let msg = chatMessagesByInactiveSession[sessionId]![idx]
            let content = msg.content.isEmpty ? bgLabel : msg.content
            var messages = chatMessagesByInactiveSession[sessionId]!
            messages[idx] = ChatMessage(
                role: .assistant, content: content,
                agentId: msg.agentId, agentEmoji: msg.agentEmoji,
                taskStatus: .background, id: msgId
            )
            chatMessagesByInactiveSession[sessionId] = messages
        }
    }

    /// Cancel an in-progress chat task.
    /// Sends chat.abort via WebSocket and terminates the event stream.
    func cancelChat(_ msgId: UUID) {
        // 1. Look up runId and send abort via gateway WebSocket.
        //    Build sessionKey from the TASK's bound (agent, session), not
        //    the currently-active one — callers like cancelTasks(inSession:)
        //    pass msgIds from sessions that may no longer be selected.
        let runId = activeChatRuns[msgId]
        let taskAgent = taskAgentMap[msgId] ?? selectedAgentId
        let taskSid = taskSessionMap[msgId] ?? selectedSessionIdByAgent[taskAgent]
        if let sessionKey = taskSessionKeyOverride[msgId] ?? taskSid.map({ sessionKeyForAgent(taskAgent, sessionId: $0) }) {
            Task {
                _ = await gatewayClient.abortChat(sessionKey: sessionKey, runId: runId)
            }
        } else {
            chatLog.warning("cancelChat: no session bound to msgId \(msgId.uuidString.prefix(8)) — abort skipped")
        }

        // 2. Terminate the event stream for this message
        gatewayClient.unsubscribe(subscriberId: msgId.uuidString)
        activeChatRuns.removeValue(forKey: msgId)

        // 3. Update message status to cancelled — message may live in
        // chatMessagesByAgent (visible session) or chatMessagesByInactiveSession
        // (background-streaming session). updateMessage handles both.
        if let msg = findMessage(byId: msgId) {
            updateMessage(msgId: msgId, content: msg.content,
                          status: .cancelled,
                          agentId: msg.agentId ?? taskAgentMap[msgId] ?? selectedAgentId,
                          agentEmoji: msg.agentEmoji)
        }

        // 4. Cleanup tracking
        clearTaskTracking(msgId)
    }

    /// Filter out system prompt lines from openclaw agent output
    nonisolated static func filterAgentOutput(_ output: String?) -> String? {
        guard let output = output else { return nil }
        // Strip ANSI escape codes first
        let ansiPattern = "\u{1B}\\[[0-9;]*[a-zA-Z]"
        let cleaned = output.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)
        let filtered = cleaned
            .components(separatedBy: "\n")
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return true }
                if trimmed.hasPrefix("[agent-scope]") { return false }
                if trimmed.hasPrefix("[plugins]") { return false }
                if trimmed.hasPrefix("[agent/embedded]") { return false }
                if trimmed.hasPrefix("Gateway agent failed") { return false }
                if trimmed.hasPrefix("Gateway target:") { return false }
                if trimmed.hasPrefix("Source: local") { return false }
                if trimmed.hasPrefix("Bind: loopback") { return false }
                if trimmed.hasPrefix("Config:") && trimmed.contains("openclaw.json") { return false }
                if trimmed.hasPrefix("Config warnings:") { return false }
                if trimmed.hasPrefix("Config overwrite:") { return false }
                if trimmed.hasPrefix("- plugins.") { return false }
                if trimmed.hasPrefix("- ") && trimmed.contains("plugin") && trimmed.contains("detected") { return false }
                if trimmed.contains("plugins.allow is empty") { return false }
                if trimmed.contains("Multiple agents marked default") { return false }
                return true
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return filtered.isEmpty ? nil : filtered
    }

    func clearChat() {
        chatMessages.removeAll()
        // Reset the backend session for the current (agent, session) so the
        // next message starts with a clean gateway context. Falls back to
        // doing nothing if we somehow don't have an active session — better
        // than wiping the wrong session.
        guard let sid = selectedSessionIdByAgent[selectedAgentId] else { return }
        resetAgentSession(agentId: selectedAgentId, sessionId: sid)
    }

    /// Reset the backend session files for a specific (agent, session) so
    /// the next message starts fresh — without nuking other UI sessions
    /// the user has for the same agent.
    private func resetAgentSession(agentId: String, sessionId: UUID) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let sessionsDir = "\(homeDir)/.openclaw/agents/\(agentId)/sessions"
        let sessionsJsonPath = "\(sessionsDir)/sessions.json"
        let fm = FileManager.default

        // Look up the gateway session-id mapped to *this* UI session's
        // sessionKey, not the legacy "agent:X:main" catch-all. Match the key
        // CASE-INSENSITIVELY: the client builds sessionKey with Swift's
        // UPPERCASE `UUID.uuidString`, but the gateway stores it LOWERCASE — an
        // exact match silently missed, so this reset was a no-op on the gateway
        // side (it only cleared the local mirror, never the gateway context).
        let sessionKey = sessionKeyForAgent(agentId, sessionId: sessionId).lowercased()
        guard let data = fm.contents(atPath: sessionsJsonPath),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actualKey = root.keys.first(where: { $0.lowercased() == sessionKey }),
              let entry = root[actualKey] as? [String: Any],
              let gwSessionId = entry["sessionId"] as? String else {
            NSLog("[Chat] resetAgentSession: no active session found for %@", agentId)
            return
        }

        // Rename the .jsonl file to .jsonl.reset.<timestamp>
        let jsonlPath = "\(sessionsDir)/\(gwSessionId).jsonl"
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupPath = "\(jsonlPath).reset.\(timestamp)"
        if fm.fileExists(atPath: jsonlPath) {
            try? fm.moveItem(atPath: jsonlPath, toPath: backupPath)
            NSLog("[Chat] resetAgentSession: renamed %@ -> %@", jsonlPath, backupPath)
        }

        // Remove the session entry from sessions.json so backend creates a new one
        root.removeValue(forKey: actualKey)
        if let updatedData = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? updatedData.write(to: URL(fileURLWithPath: sessionsJsonPath))
            NSLog("[Chat] resetAgentSession: removed session key %@ from sessions.json", actualKey)
        }
    }

}
