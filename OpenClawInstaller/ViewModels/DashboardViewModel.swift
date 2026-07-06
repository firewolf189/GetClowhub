import Foundation
import Combine
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import os.log

// internal (not file-private): also used by the InFlightRuns extension (P1.6b).
let chatLog = Logger(subsystem: "com.openclaw.installer", category: "Chat")
private let sessionSwitchPerfLog = Logger(subsystem: "com.openclaw.installer", category: "SessionSwitchPerformance")

@MainActor
class DashboardViewModel: ObservableObject {
    let chatState = ChatRuntimeState()
    let taskState = TaskActivityState()
    let sessionState = SessionNavigationState()
    @Published var openclawService: OpenClawService
    @Published var settings: AppSettingsManager
    @Published var systemEnvironment: SystemEnvironment

    // Debug logging
    private let chatDebugLog = OSLog(subsystem: "com.openclaw.chat", category: "debug")
    func logChat(_ message: String) {
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
    let providerModelFetchService = ProviderModelFetchService()  // internal: ConfigProviderLogs extension (P1.6c)
    let attachmentProcessor = AttachmentProcessor()

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
    var logRefreshTimer: Timer?  // internal: ConfigProviderLogs extension (P1.6c)
    var budgetMonitorTimer: Timer?  // internal: used by BudgetManagement extension (P1.4)

    private let _commandExecutor: CommandExecutor
    let projectWorkspaceService = ProjectWorkspaceService()
    private var cancellables = Set<AnyCancellable>()

    #if REQUIRE_LOGIN
    // MembershipManager reference for GetClawHub save logic
    weak var membershipManager: MembershipManager?
    #endif
    // Gateway WebSocket client for chat
    @Published var gatewayClient: GatewayClient

    // Maps msgId → runId for active WebSocket chat runs
    var activeChatRuns: [UUID: String] = [:]
    var taskSessionKeyOverride: [UUID: String] = [:]

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
        chatState.$chatMessagesByAgent
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
        Publishers.CombineLatest(sessionState.$selectedAgentId, taskState.$foregroundTaskIds)
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
        chatState.$chatMessagesByInactiveSession
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
        Publishers.CombineLatest(taskState.$foregroundTaskIds, taskState.$backgroundTaskIds)
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
    var appliedSessionModels: [String: String] = [:]

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
            showSuccessMessage(I18n.t("dashboard.service.toast.started"))
        } catch {
            showErrorMessage(I18n.format("dashboard.service.toast.startFailed", error.localizedDescription))
        }

        isPerformingAction = false
    }

    func stopService() async {
        isPerformingAction = true

        do {
            try await openclawService.stop()
            showSuccessMessage(I18n.t("dashboard.service.toast.stopped"))
        } catch {
            showErrorMessage(I18n.format("dashboard.service.toast.stopFailed", error.localizedDescription))
        }

        isPerformingAction = false
    }

    func restartService() async {
        isPerformingAction = true

        do {
            try await openclawService.restart()
            showSuccessMessage(I18n.t("dashboard.service.toast.restarted"))
        } catch {
            showErrorMessage(I18n.format("dashboard.service.toast.restartFailed", error.localizedDescription))
        }

        isPerformingAction = false
    }

    func refreshStatus() async {
        await openclawService.checkStatus()
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

    var chatMessagesByAgent: [String: [ChatMessage]] {
        get { chatState.chatMessagesByAgent }
        set { chatState.chatMessagesByAgent = newValue }
    }
    /// Computed view into the currently selected agent's messages.
    var chatMessages: [ChatMessage] {
        get { chatState.chatMessages(for: selectedAgentId) }
        set { chatState.setChatMessages(newValue, for: selectedAgentId) }
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
    var sessionsByAgent: [String: [ChatSessionMetadata]] {
        get { sessionState.sessionsByAgent }
        set { sessionState.sessionsByAgent = newValue }
    }
    /// Global derived list for pinned sessions. The sessions still retain their
    /// original agent/project ownership; this is only a sidebar presentation.
    var pinnedSessions: [ChatSessionMetadata] {
        get { sessionState.pinnedSessions }
        set { sessionState.pinnedSessions = newValue }
    }
    var projectBindingsByAgent: [String: [AgentProjectBinding]] {
        get { sessionState.projectBindingsByAgent }
        set { sessionState.projectBindingsByAgent = newValue }
    }
    var projectSessionsByAgent: [String: [ProjectSessionGroup]] {
        get { sessionState.projectSessionsByAgent }
        set { sessionState.projectSessionsByAgent = newValue }
    }
    var generalSessionsByAgent: [String: [ChatSessionMetadata]] {
        get { sessionState.generalSessionsByAgent }
        set { sessionState.generalSessionsByAgent = newValue }
    }
    var projectsById: [String: ProjectRecord] {
        get { sessionState.projectsById }
        set { sessionState.projectsById = newValue }
    }
    /// The currently visible session for each agent. Switching this swaps
    /// chatMessagesByAgent[agentId] to the loaded session's messages.
    var selectedSessionIdByAgent: [String: UUID] {
        get { sessionState.selectedSessionIdByAgent }
        set { sessionState.selectedSessionIdByAgent = newValue }
    }
    var activeProjectIdByAgent: [String: String?] = [:]
    /// Empty sessions created by the sidebar plus button before the user sends
    /// a first message. They should be visible/clickable in the sidebar, but
    /// should not be persisted unless the user actually types into them.
    var pendingSessionMetadataByAgent: [String: ChatSessionMetadata] = [:]
    var shouldSuppressNextSessionSwitchBottomScroll = false


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
        guard wasActive else {
            rebuildSessionsMirror()
            recomputeIsSendingMessage()
            return
        }
        shouldSuppressNextSessionSwitchBottomScroll = true
        promoteNextSession(forAgent: agentId)
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
    func ensureActiveSessionId(forAgent agentId: String, seedMessages: [ChatMessage] = []) -> UUID {
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
    var isSendingMessage: Bool {
        get { taskState.isSendingMessage }
        set { taskState.isSendingMessage = newValue }
    }
    var foregroundTaskIds: Set<UUID> {
        get { taskState.foregroundTaskIds }
        set { taskState.foregroundTaskIds = newValue }
    }
    var backgroundTaskIds: Set<UUID> {
        get { taskState.backgroundTaskIds }
        set { taskState.backgroundTaskIds = newValue }
    }
    var taskAgentMap: [UUID: String] {
        get { taskState.taskAgentMap }
        set { taskState.taskAgentMap = newValue }
    }
    /// msgId → the sessionId the task was started under. Used to (a) route
    /// gateway sessionKey on cancel and (b) decide which UI session "owns"
    /// the spinner / cancel affordance. Both populated together with
    /// `taskAgentMap` in `sendChatMessage`; both cleaned together on any
    /// terminal event (completed / cancelled / timed-out / error).
    var taskSessionMap: [UUID: UUID] {
        get { taskState.taskSessionMap }
        set { taskState.taskSessionMap = newValue }
    }

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
    var chatMessagesByInactiveSession: [UUID: [ChatMessage]] {
        get { chatState.chatMessagesByInactiveSession }
        set { chatState.chatMessagesByInactiveSession = newValue }
    }

    /// Sessions whose messages are being lazy-loaded from disk in the
    /// background. The chat view watches this set so it can render a
    /// "loading…" placeholder during the cold-load window instead of
    /// flashing an empty thread. Entries are added by `switchSession` /
    /// `ensureMessagesLoaded` when they take the async path (cache miss)
    /// and removed when the load resolves.
    var loadingSessionIds: Set<UUID> {
        get { chatState.loadingSessionIds }
        set { chatState.loadingSessionIds = newValue }
    }

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

    var inflightSessionIds: Set<UUID> {
        Set((foregroundTaskIds.union(backgroundTaskIds)).compactMap { taskSessionMap[$0] })
    }

    func consumeSuppressNextSessionSwitchBottomScroll() -> Bool {
        let shouldSuppress = shouldSuppressNextSessionSwitchBottomScroll
        shouldSuppressNextSessionSwitchBottomScroll = false
        return shouldSuppress
    }

    /// Recompute `isSendingMessage` based on whether the currently visible
    /// session has any foreground task in flight. Must be called whenever
    /// `foregroundTaskIds`, `selectedAgentId`, `selectedSessionIdByAgent[agentId]`,
    /// or `taskSessionMap` changes — otherwise the input lock won't track
    /// the visible session correctly.
    func recomputeIsSendingMessage() {
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
    func clearTaskTracking(_ msgId: UUID) {
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
    func cancelTasks(inSession sessionId: UUID) {
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
    func findMessage(byId msgId: UUID) -> ChatMessage? {
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
    var selectedAgentId: String {
        get { sessionState.selectedAgentId }
        set { sessionState.selectedAgentId = newValue }
    }
    var availableAgents: [AgentOption] {
        get { sessionState.availableAgents }
        set { sessionState.availableAgents = newValue }
    }

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

}
