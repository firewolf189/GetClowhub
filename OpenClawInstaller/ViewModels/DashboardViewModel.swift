import Foundation
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var openclawService: OpenClawService
    @Published var settings: AppSettingsManager
    @Published var systemEnvironment: SystemEnvironment

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
    var pendingProviderKey: String = ""

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
    }

    // Gateway logs
    @Published var gatewayLogs: [String] = []
    @Published var isLoadingLogs = false

    // Diagnostics
    @Published var diagnosticReport: String = ""
    @Published var showDiagnostics = false
    private var logRefreshTimer: Timer?

    private let commandExecutor: CommandExecutor
    private var cancellables = Set<AnyCancellable>()

    init(
        openclawService: OpenClawService,
        settings: AppSettingsManager,
        systemEnvironment: SystemEnvironment,
        commandExecutor: CommandExecutor
    ) {
        self.openclawService = openclawService
        self.settings = settings
        self.systemEnvironment = systemEnvironment
        self.commandExecutor = commandExecutor

        // Initialize edited values from real config
        self.editedPort = String(settings.settings.gatewayPort)
        self.editedAuthToken = settings.settings.gatewayAuthToken
        self.editedModelBaseUrl = settings.settings.modelBaseUrl
        self.editedModelApiKey = settings.settings.modelApiKey
        self.editedSelectedProviderKey = settings.settings.selectedProviderKey
        self.editedProviderApi = settings.settings.providerApi
        self.editedConfiguredModels = settings.settings.configuredModels

        // Load available providers from preset
        self.availableProviders = presetManager.loadPresets()

        // If no config file exists, populate from preset defaults
        if editedModelBaseUrl.isEmpty,
           let preset = availableProviders.first(where: { $0.key == editedSelectedProviderKey }) {
            editedModelBaseUrl = preset.baseUrl
            editedProviderApi = preset.api
            editedConfiguredModels = preset.models
        }

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
    }

    deinit {
        Task { @MainActor in
            openclawService.stopMonitoring()
            logRefreshTimer?.invalidate()
            logRefreshTimer = nil
        }
    }

    // Plugins
    @Published var plugins: [PluginInfo] = []
    @Published var isLoadingPlugins = false

    // Channels
    @Published var channels: [ChannelInfo] = []
    @Published var isLoadingChannels = false

    // Models
    @Published var models: [ModelInfo] = []
    @Published var modelOverview: ModelOverview = ModelOverview()
    @Published var fallbackModels: [String] = []
    @Published var imageFallbackModels: [String] = []
    @Published var isLoadingModels = false

    // Cron Jobs
    @Published var cronJobs: [CronJobInfo] = []
    @Published var isLoadingCronJobs = false

    // MARK: - Tab Management

    enum DashboardTab: String, CaseIterable, Hashable {
        case chat = "Chat"
        case status = "Status"
        case persona = "Persona"
        case subAgents = "Multi-Agent"
        case config = "Configuration"
        case skills = "Skills"
        case models = "Models"
        case channels = "Channels"
        case plugins = "Plugins"
        case cron = "Cron"
        case logs = "Logs"

        var icon: String {
            switch self {
            case .chat: return "message.fill"
            case .status: return "chart.bar.fill"
            case .persona: return "person.text.rectangle"
            case .subAgents: return "person.3.fill"
            case .config: return "gearshape"
            case .skills: return "bolt.fill"
            case .models: return "cube.fill"
            case .channels: return "bubble.left.and.bubble.right.fill"
            case .plugins: return "puzzlepiece.fill"
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
        availableProviders = presetManager.loadPresets()

        // If no config file exists yet, populate from preset defaults
        if editedModelBaseUrl.isEmpty,
           let preset = availableProviders.first(where: { $0.key == editedSelectedProviderKey }) {
            editedModelBaseUrl = preset.baseUrl
            editedProviderApi = preset.api
            editedConfiguredModels = preset.models
        }
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

        // Write to ~/.openclaw/openclaw.json
        if settings.saveToFile() {
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
        if let preset = presetManager.findProvider(byKey: key) {
            editedModelBaseUrl = preset.baseUrl
            editedProviderApi = preset.api
            editedConfiguredModels = preset.models
            editedModelApiKey = ""
        }
        pendingProviderKey = ""
        showProviderSwitchConfirm = false
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

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true

        // Auto-hide after 5 seconds
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            showError = false
        }
    }

    private func showSuccessMessage(_ message: String) {
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

    /// Load skills list by running `openclaw skills list`
    func loadSkills() async {
        isLoadingSkills = true
        let output = await openclawService.runCommand(
            "openclaw skills list 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        let (parsed, summary) = Self.parseSkillsList(output: output)
        skills = parsed.sorted { a, b in
            if a.status != b.status {
                return a.status == .ready
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        skillsSummary = summary
        isLoadingSkills = false
    }

    /// Parse `openclaw skills list` table output.
    /// Table format: │ Status │ Skill │ Description │ Source │
    static func parseSkillsList(output: String?) -> ([SkillInfo], SkillsSummary) {
        guard let output = output else { return ([], SkillsSummary()) }

        var results: [SkillInfo] = []
        var summary = SkillsSummary()

        // Parse header "Skills (35/81 ready)"
        for line in output.components(separatedBy: .newlines) {
            if line.contains("Skills (") && line.contains("ready)") {
                if let range = line.range(of: "\\((\\d+)/(\\d+)\\s+ready\\)", options: .regularExpression) {
                    let match = String(line[range])
                    let nums = match.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
                    if nums.count >= 2 {
                        summary.ready = Int(nums[0]) ?? 0
                        summary.total = Int(nums[1]) ?? 0
                    }
                }
                break
            }
        }

        // Current row accumulator (for multiline cells)
        var currentStatus: String?
        var currentName: String?
        var currentDesc: String?
        var currentSource: String?

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip border lines and non-table lines
            guard trimmed.hasPrefix("│") else { continue }

            // Skip header row
            if trimmed.contains("Status") && trimmed.contains("Skill") && trimmed.contains("Description") && trimmed.contains("Source") {
                continue
            }

            // Split by │ and trim
            let cells = trimmed.components(separatedBy: "│")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            // cells[0]="" cells[1]=Status cells[2]=Skill cells[3]=Description cells[4]=Source
            guard cells.count >= 5 else { continue }

            let status = cells[1]
            // Strip leading emoji from skill name (e.g. "📦 feishu-doc" -> "feishu-doc")
            let skill = cells[2].drop(while: { !$0.isASCII })
                .trimmingCharacters(in: .whitespaces)
            let desc = cells[3]
            let source = cells[4]

            // Check if this is a new row (status column is non-empty)
            if !status.isEmpty {
                // Flush previous row
                if let prevName = currentName, !prevName.isEmpty {
                    results.append(SkillInfo(
                        name: prevName,
                        status: currentStatus?.contains("ready") == true ? .ready : .missing,
                        description: currentDesc ?? "",
                        source: currentSource ?? ""
                    ))
                }
                currentStatus = status
                currentName = skill
                currentDesc = desc
                currentSource = source
            } else {
                // Continuation line — append description
                if !skill.isEmpty {
                    currentName = (currentName ?? "") + skill
                }
                if !desc.isEmpty {
                    currentDesc = ((currentDesc ?? "") + " " + desc).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        // Flush last row
        if let prevName = currentName, !prevName.isEmpty {
            results.append(SkillInfo(
                name: prevName,
                status: currentStatus?.contains("ready") == true ? .ready : .missing,
                description: currentDesc ?? "",
                source: currentSource ?? ""
            ))
        }

        return (results, summary)
    }

    /// Load detail info for a specific skill
    func loadSkillDetail(_ skillName: String) async {
        isLoadingSkillDetail = true
        let output = await openclawService.runCommand(
            "openclaw skills info '\(skillName)' 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        selectedSkillDetail = Self.parseSkillInfo(output: output, skillName: skillName)
        isLoadingSkillDetail = false
    }

    /// Parse `openclaw skills info <name>` output
    static func parseSkillInfo(output: String?, skillName: String) -> SkillDetailInfo? {
        guard let output = output else { return nil }

        var status = ""
        var description = ""
        var source = ""
        var path = ""
        var requirements: [String] = []
        var isReady = false

        var inRequirements = false
        var inDescription = true

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip noise lines
            if trimmed.hasPrefix("[agent-scope]") || trimmed.hasPrefix("Config warnings:")
                || trimmed.hasPrefix("- plugins.") || trimmed.isEmpty { continue }
            if trimmed.hasPrefix("│") || trimmed.hasPrefix("◇") || trimmed.hasPrefix("├") { continue }

            // Status line: "📦 brainstorming ✓ Ready" or "🎮 discord ✗ Missing requirements"
            if trimmed.contains("Ready") || trimmed.contains("Missing") {
                if trimmed.contains("Ready") {
                    status = "Ready"
                    isReady = true
                } else {
                    status = "Missing requirements"
                    isReady = false
                }
                inDescription = true
                continue
            }

            if trimmed.hasPrefix("Details:") {
                inDescription = false
                inRequirements = false
                continue
            }

            if trimmed.hasPrefix("Requirements:") {
                inDescription = false
                inRequirements = true
                continue
            }

            if trimmed.hasPrefix("Tip:") {
                break
            }

            if trimmed.hasPrefix("Source:") {
                source = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                continue
            }

            if trimmed.hasPrefix("Path:") {
                path = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                continue
            }

            if inRequirements {
                if trimmed.hasPrefix("Config:") || trimmed.hasPrefix("Bins:") {
                    requirements.append(trimmed)
                }
                continue
            }

            if inDescription && !trimmed.hasPrefix("Details:") && !trimmed.hasPrefix("Source:")
                && !trimmed.hasPrefix("Path:") {
                if !description.isEmpty { description += " " }
                description += trimmed
            }
        }

        return SkillDetailInfo(
            name: skillName,
            status: status,
            isReady: isReady,
            description: description,
            source: source,
            path: path,
            requirements: requirements
        )
    }

    // MARK: - Chat

    @Published var chatMessages: [ChatMessage] = []
    @Published var isSendingMessage = false  // true when any foreground task is active
    @Published var foregroundTaskIds: Set<UUID> = []  // message IDs of foreground (blocking) tasks
    @Published var backgroundTaskIds: Set<UUID> = []  // message IDs of background tasks
    @Published var selectedAgentId: String = "main"
    @Published var availableAgents: [AgentOption] = [AgentOption(id: "main", name: "main", emoji: "🤖")]

    func loadAvailableAgents() {
        let configPath = NSString("~/.openclaw/openclaw.json").expandingTildeInPath
        let baseDir = NSString("~/.openclaw").expandingTildeInPath
        var agents: [AgentOption] = []

        if let data = FileManager.default.contents(atPath: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let agentsSection = json["agents"] as? [String: Any],
           let agentList = agentsSection["list"] as? [[String: Any]] {
            for entry in agentList {
                guard let agentId = entry["id"] as? String else { continue }

                // Determine workspace path for this agent
                let workspace: String
                if let ws = entry["workspace"] as? String {
                    workspace = (ws as NSString).expandingTildeInPath
                } else if agentId == "main" {
                    workspace = (baseDir as NSString).appendingPathComponent("workspace")
                } else {
                    workspace = (baseDir as NSString).appendingPathComponent("workspace-\(agentId)")
                }

                // Read IDENTITY.md and parse emoji/name from file first, fall back to config
                let identityPath = (workspace as NSString).appendingPathComponent("IDENTITY.md")
                let identityContent = (try? String(contentsOfFile: identityPath, encoding: .utf8)) ?? ""
                let parsed = PersonaViewModel.parseIdentity(identityContent)

                let identity = entry["identity"] as? [String: Any]

                let name: String = {
                    if !parsed.name.isEmpty { return parsed.name }
                    if let n = identity?["name"] as? String, !n.isEmpty { return n }
                    return entry["name"] as? String ?? agentId
                }()

                let emoji: String = {
                    if !parsed.emoji.isEmpty { return parsed.emoji }
                    return identity?["emoji"] as? String ?? "🤖"
                }()

                agents.append(AgentOption(id: agentId, name: name, emoji: emoji))
            }
        }

        // Ensure "main" is always present
        if !agents.contains(where: { $0.id == "main" }) {
            // Even for main fallback, try reading from IDENTITY.md
            let mainWorkspace = (baseDir as NSString).appendingPathComponent("workspace")
            let mainIdentityPath = (mainWorkspace as NSString).appendingPathComponent("IDENTITY.md")
            let mainContent = (try? String(contentsOfFile: mainIdentityPath, encoding: .utf8)) ?? ""
            let mainParsed = PersonaViewModel.parseIdentity(mainContent)
            let mainName = mainParsed.name.isEmpty ? "main" : mainParsed.name
            let mainEmoji = mainParsed.emoji.isEmpty ? "🤖" : mainParsed.emoji
            agents.insert(AgentOption(id: "main", name: mainName, emoji: mainEmoji), at: 0)
        }

        availableAgents = agents

        // Reset selection if current agent no longer exists
        if !agents.contains(where: { $0.id == selectedAgentId }) {
            selectedAgentId = "main"
        }
    }

    func sendChatMessage(_ text: String, attachments: [URL] = []) async {
        let userMessage = ChatMessage(role: .user, content: text, attachments: attachments)
        chatMessages.append(userMessage)

        let currentAgentId = selectedAgentId
        let currentAgentEmoji = availableAgents.first(where: { $0.id == currentAgentId })?.emoji

        // Build the full message: text + file paths
        var messageParts = [text]
        for url in attachments {
            messageParts.append(url.path)
        }
        let fullMessage = messageParts.joined(separator: "\n")
        let escaped = fullMessage.replacingOccurrences(of: "'", with: "'\\''")

        // Insert a placeholder assistant message for streaming updates
        let msgId = UUID()
        let placeholderMsg = ChatMessage(role: .assistant, content: "", agentId: currentAgentId, agentEmoji: currentAgentEmoji, taskStatus: .loading, id: msgId)
        chatMessages.append(placeholderMsg)

        // Track as foreground task
        foregroundTaskIds.insert(msgId)
        isSendingMessage = true

        // Helper to update message in place
        func updateMessage(content: String, status: ChatMessage.TaskStatus) {
            if let idx = self.chatMessages.firstIndex(where: { $0.id == msgId }) {
                self.chatMessages[idx] = ChatMessage(
                    role: .assistant, content: content,
                    agentId: currentAgentId, agentEmoji: currentAgentEmoji,
                    taskStatus: status, id: msgId
                )
            }
        }

        // Run streaming command in a detached Task so we can await or let it continue in background
        let resultStream: AsyncStream<(Bool, String?)> = AsyncStream { continuation in
            Task { [weak self] in
                guard let self = self else {
                    continuation.yield((true, nil))
                    continuation.finish()
                    return
                }
                let result = await self.openclawService.runCommandStreaming(
                    "openclaw agent --agent \(currentAgentId) -m '\(escaped)' 2>&1",
                    timeout: 1800
                ) { [weak self] rawOutput in
                    guard let self = self else { return }
                    let filtered = Self.filterAgentOutput(rawOutput) ?? ""
                    if !filtered.isEmpty {
                        Task { @MainActor in
                            if let idx = self.chatMessages.firstIndex(where: { $0.id == msgId }) {
                                let currentStatus = self.chatMessages[idx].taskStatus
                                // Don't overwrite if the final result has already been written
                                guard currentStatus != .completed else { return }
                                self.chatMessages[idx] = ChatMessage(
                                    role: .assistant, content: filtered,
                                    agentId: currentAgentId, agentEmoji: currentAgentEmoji,
                                    taskStatus: currentStatus, id: msgId
                                )
                            }
                        }
                    }
                }
                switch result {
                case .completed(let output):
                    continuation.yield((true, output))
                case .timedOut(let partialOutput):
                    continuation.yield((false, partialOutput))
                }
                continuation.finish()
            }
        }

        // Wait for the result — this runs on MainActor so we can update UI
        for await (completed, output) in resultStream {
            let wasBackground = backgroundTaskIds.contains(msgId)

            if completed {
                let noReply = String(localized: "No response from AI.", bundle: LanguageManager.shared.localizedBundle)
                let reply = Self.filterAgentOutput(output) ?? noReply
                updateMessage(content: reply, status: .completed)
            } else {
                let partial = Self.filterAgentOutput(output) ?? ""
                let timeoutMsg = String(localized: "The task timed out and has been terminated. You can try again or switch to another agent.", bundle: LanguageManager.shared.localizedBundle)
                let reply = partial.isEmpty
                    ? timeoutMsg
                    : partial + "\n\n---\n> ⚠️ " + timeoutMsg
                updateMessage(content: reply, status: .timedOut)
            }

            // If task was in background, append a notification message at the bottom
            if wasBackground {
                let agentName = availableAgents.first(where: { $0.id == currentAgentId })?.name ?? currentAgentId
                if completed {
                    let notifyContent = String(format: String(localized: "✅ Background task from **%@** completed", bundle: LanguageManager.shared.localizedBundle), agentName)
                    let notifyMsg = ChatMessage(role: .assistant, content: notifyContent, agentId: currentAgentId, agentEmoji: currentAgentEmoji, scrollTargetId: msgId)
                    chatMessages.append(notifyMsg)
                } else {
                    let notifyContent = String(format: String(localized: "⚠️ Background task from **%@** timed out", bundle: LanguageManager.shared.localizedBundle), agentName)
                    let notifyMsg = ChatMessage(role: .assistant, content: notifyContent, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
                    chatMessages.append(notifyMsg)
                }
            }

            // Cleanup tracking
            foregroundTaskIds.remove(msgId)
            backgroundTaskIds.remove(msgId)
            isSendingMessage = !foregroundTaskIds.isEmpty
        }
    }

    /// Move a foreground task to background, unlocking the input
    func moveTaskToBackground(_ msgId: UUID) {
        guard foregroundTaskIds.contains(msgId) else { return }
        foregroundTaskIds.remove(msgId)
        backgroundTaskIds.insert(msgId)
        isSendingMessage = !foregroundTaskIds.isEmpty

        // Update message status to background
        if let idx = chatMessages.firstIndex(where: { $0.id == msgId }) {
            let msg = chatMessages[idx]
            let bgLabel = String(localized: "⏳ Task running in background...", bundle: LanguageManager.shared.localizedBundle)
            let content = msg.content.isEmpty ? bgLabel : msg.content
            chatMessages[idx] = ChatMessage(
                role: .assistant, content: content,
                agentId: msg.agentId, agentEmoji: msg.agentEmoji,
                taskStatus: .background, id: msgId
            )
        }
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
    }

    // MARK: - Status Summary

    func getStatusSummary() -> String {
        let status = openclawService.status.rawValue
        let version = openclawService.version.isEmpty ? "Unknown" : openclawService.version

        if openclawService.status == .running {
            let uptime = formatUptime(openclawService.uptime)
            return "\(status) • v\(version) • Uptime: \(uptime)"
        } else {
            return "\(status) • v\(version)"
        }
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }

    // MARK: - Plugin Management

    /// Refresh the installed plugins list by running `openclaw plugins list`
    func loadPlugins() async {
        isLoadingPlugins = true
        // Strip ANSI color codes for clean parsing
        let output = await openclawService.runCommand(
            "openclaw plugins list 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        plugins = Self.parsePluginList(output: output)
            .sorted { a, b in
                if a.enabled != b.enabled { return a.enabled }
                return a.channel.localizedCaseInsensitiveCompare(b.channel) == .orderedAscending
            }
        isLoadingPlugins = false
    }

    /// Parse `openclaw plugins list` table output.
    /// Table format: │ Name │ ID │ Status │ Source │ Version │
    /// Status values: "loaded", "disabled"
    /// A new row starts when the Status cell is non-empty.
    /// Continuation lines (Status empty) may carry overflow text for Name or ID.
    static func parsePluginList(output: String?) -> [PluginInfo] {
        guard let output = output else { return [] }

        var results: [PluginInfo] = []
        var currentName: String?
        var currentId: String?
        var currentStatus: String?
        var currentSource: String?

        func flushRow() {
            guard var name = currentName, let status = currentStatus else { return }
            var id = currentId ?? ""

            // If ID is empty, try to extract from Source ("stock:plugin-id/..." or "global:plugin-id/...")
            if id.isEmpty, let source = currentSource, !source.isEmpty,
               let colonIdx = source.firstIndex(of: ":"),
               let slashIdx = source[source.index(after: colonIdx)...].firstIndex(of: "/") {
                id = String(source[source.index(after: colonIdx)..<slashIdx])
            }

            // Last resort: derive ID from name
            if id.isEmpty {
                id = name.replacingOccurrences(of: "@openclaw/", with: "")
            }

            if name.isEmpty { name = id }

            let enabled = status == "loaded"
            results.append(PluginInfo(
                channel: name,
                pluginId: id,
                installed: true,
                enabled: enabled
            ))
        }

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("│") else { continue }
            if trimmed.contains("Name") && trimmed.contains("Status") && trimmed.contains("Source") {
                continue
            }

            let cells = trimmed.components(separatedBy: "│")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 4 else { continue }

            let name = cells[1]
            let pluginId = cells[2]
            let status = cells[3]
            let source = cells.count >= 5 ? cells[4] : ""

            if !status.isEmpty {
                // New row — flush previous
                flushRow()
                currentName = name
                currentId = pluginId
                currentStatus = status
                currentSource = source
            } else {
                // Continuation line — append Name overflow
                if !name.isEmpty, let existing = currentName {
                    if existing.hasSuffix("/") || existing.hasSuffix("-") {
                        currentName = existing + name
                    } else {
                        currentName = existing + " " + name
                    }
                }
                // Append ID overflow (IDs never contain spaces, always direct concat)
                if !pluginId.isEmpty {
                    if let existing = currentId, !existing.isEmpty {
                        currentId = existing + pluginId
                    } else {
                        currentId = pluginId
                    }
                }
            }
        }
        flushRow()

        return results
    }

    /// Enable a plugin
    func enablePlugin(_ plugin: PluginInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand("openclaw plugins enable \(plugin.pluginId) 2>&1")
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to enable \(plugin.channel): \(output)")
        } else {
            showSuccessMessage("\(plugin.channel) enabled")
        }
        await loadPlugins()
        isPerformingAction = false
    }

    /// Disable a plugin
    func disablePlugin(_ plugin: PluginInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand("openclaw plugins disable \(plugin.pluginId) 2>&1")
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to disable \(plugin.channel): \(output)")
        } else {
            showSuccessMessage("\(plugin.channel) disabled")
        }
        await loadPlugins()
        isPerformingAction = false
    }

    // MARK: - Channel Management

    /// Available channel types for adding
    static let availableChannelTypes = [
        "telegram", "whatsapp", "discord", "irc", "googlechat", "slack",
        "signal", "imessage", "feishu", "nostr", "msteams", "mattermost",
        "nextcloud-talk", "matrix", "dingtalk", "bluebubbles", "line",
        "zalo", "synology-chat", "tlon"
    ]

    /// Load channels by running `openclaw channels status`
    func loadChannels() async {
        isLoadingChannels = true
        let output = await openclawService.runCommand(
            "openclaw channels status 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        channels = Self.parseChannelStatus(output: output)
            .sorted { a, b in
                let aPriority = a.configured && a.linked ? 0 : a.configured ? 1 : 2
                let bPriority = b.configured && b.linked ? 0 : b.configured ? 1 : 2
                if aPriority != bPriority { return aPriority < bPriority }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        isLoadingChannels = false
    }

    /// Parse `openclaw channels status` output.
    /// Lines like: `- WhatsApp default: enabled, configured, not linked, stopped, disconnected, dm:pairing, error:not linked`
    /// or: `- DingTalk default: enabled, configured`
    /// Stops at "Warnings:" or "Tip:" sections to avoid parsing non-channel lines.
    static func parseChannelStatus(output: String?) -> [ChannelInfo] {
        guard let output = output else { return [] }

        var results: [ChannelInfo] = []

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Stop parsing at non-channel sections
            let lower = trimmed.lowercased()
            if lower.hasPrefix("warnings:") || lower.hasPrefix("tip:") || lower.hasPrefix("docs:") || lower.hasPrefix("usage:") {
                break
            }

            // Match lines starting with "- ChannelName accountId: status1, status2, ..."
            guard trimmed.hasPrefix("- ") else { continue }
            let content = String(trimmed.dropFirst(2))

            // Split at first ":"
            guard let colonIdx = content.firstIndex(of: ":") else { continue }
            let nameAndAccount = content[content.startIndex..<colonIdx]
                .trimmingCharacters(in: .whitespaces)
            let statusPart = content[content.index(after: colonIdx)...]
                .trimmingCharacters(in: .whitespaces)

            // The status part must contain "enabled" or "disabled" to be a channel line
            let statusLower = statusPart.lowercased()
            guard statusLower.contains("enabled") || statusLower.contains("disabled") else { continue }

            // Split name and account: "WhatsApp default" -> name="WhatsApp", account="default"
            let nameParts = nameAndAccount.components(separatedBy: " ")
            let channelName: String
            let account: String
            if nameParts.count >= 2 {
                channelName = nameParts.dropLast().joined(separator: " ")
                account = nameParts.last!
            } else {
                channelName = nameAndAccount
                account = "default"
            }

            // Parse status tags
            let tags = statusPart.components(separatedBy: ",").map {
                $0.trimmingCharacters(in: .whitespaces).lowercased()
            }

            let enabled = tags.contains("enabled")
            let configured = tags.contains("configured")
            let notConfigured = tags.contains("not configured")
            let linked = tags.contains("linked")
            let notLinked = tags.contains("not linked")

            // Extract error message if present
            var errorMsg: String?
            for tag in tags {
                if tag.hasPrefix("error:") {
                    errorMsg = String(tag.dropFirst(6))
                }
            }

            results.append(ChannelInfo(
                name: channelName,
                account: account,
                enabled: enabled,
                configured: configured && !notConfigured,
                linked: notLinked ? false : (linked || configured),
                error: errorMsg,
                statusTags: tags
            ))
        }

        return results
    }

    /// Add a channel with token
    func addChannel(channelType: String, token: String) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw channels add --channel \(channelType) --token '\(token)' 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to add \(channelType): \(output)")
        } else {
            showSuccessMessage("\(channelType) channel added")
        }
        await loadChannels()
        isPerformingAction = false
    }

    func addChannel(channelType: String, appKey: String, appSecret: String) async {
        isPerformingAction = true
        let escapedKey = appKey.replacingOccurrences(of: "'", with: "'\\''")
        let escapedSecret = appSecret.replacingOccurrences(of: "'", with: "'\\''")
        let output = await openclawService.runCommand(
            "openclaw channels add --channel \(channelType) --app-key '\(escapedKey)' --app-secret '\(escapedSecret)' 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to add \(channelType): \(output)")
        } else {
            showSuccessMessage("\(channelType) channel added")
        }
        await loadChannels()
        isPerformingAction = false
    }

    /// Remove a channel
    func removeChannel(_ channel: ChannelInfo) async {
        isPerformingAction = true
        let channelType = channel.name.lowercased()
        let output = await openclawService.runCommand(
            "openclaw channels remove --channel \(channelType) --account \(channel.account) --delete 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to remove \(channel.name): \(output)")
        } else {
            showSuccessMessage("\(channel.name) channel removed")
        }
        await loadChannels()
        isPerformingAction = false
    }

    // MARK: - Cron Job Management

    /// Load cron jobs by running `openclaw cron list --json`
    func loadCronJobs() async {
        isLoadingCronJobs = true
        let output = await openclawService.runCommand(
            "openclaw cron list --all --json 2>&1",
            timeout: 60
        )
        cronJobs = Self.parseCronJobList(output: output)
        isLoadingCronJobs = false
    }

    /// Parse `openclaw cron list --json` output
    static func parseCronJobList(output: String?) -> [CronJobInfo] {
        guard let output = output else { return [] }

        // Strip ANSI escape codes
        let ansiPattern = "\\u{1B}\\[[0-9;]*[a-zA-Z]"
        let cleaned = output.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)

        // Try to extract JSON from the output (skip any non-JSON lines)
        let lines = cleaned.components(separatedBy: .newlines)
        var jsonString = ""
        var inJson = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inJson {
                if trimmed == "[" || trimmed.hasPrefix("[{") || trimmed.hasPrefix("[\"") {
                    inJson = true
                } else if trimmed.hasPrefix("{") {
                    inJson = true
                }
            }
            if inJson {
                jsonString += line + "\n"
            }
        }

        guard !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8) else { return [] }

        // Try parsing as {"jobs": [...]} or as [...]
        if let wrapper = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let jobsArray = wrapper["jobs"] as? [[String: Any]] {
            return jobsArray.compactMap { Self.parseCronJobDict($0) }
        } else if let jobsArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return jobsArray.compactMap { Self.parseCronJobDict($0) }
        }

        return []
    }

    /// Parse a single cron job dictionary
    private static func parseCronJobDict(_ dict: [String: Any]) -> CronJobInfo? {
        guard let id = dict["id"] as? String else { return nil }

        let name = dict["name"] as? String ?? id

        // schedule is a nested object: { kind, expr, tz }
        let scheduleObj = dict["schedule"] as? [String: Any]
        let schedule = scheduleObj?["expr"] as? String ?? dict["schedule"] as? String ?? ""
        let timezone = scheduleObj?["tz"] as? String ?? dict["timezone"] as? String ?? ""

        let agentId = dict["agentId"] as? String ?? dict["agent_id"] as? String ?? ""
        let sessionTarget = dict["sessionTarget"] as? String ?? dict["session_target"] as? String ?? ""

        // message is nested in payload: { kind, message, timeoutSeconds }
        let payloadObj = dict["payload"] as? [String: Any]
        let message = payloadObj?["message"] as? String ?? dict["message"] as? String ?? ""

        let enabled = dict["enabled"] as? Bool ?? true

        // nextRun / lastRun are timestamps in state: { nextRunAtMs, lastRunAtMs }
        let stateObj = dict["state"] as? [String: Any]
        let nextRun = Self.formatTimestamp(stateObj?["nextRunAtMs"])
        let lastRun = Self.formatTimestamp(stateObj?["lastRunAtMs"])

        let status = dict["status"] as? String ?? (enabled ? "idle" : "disabled")
        let model = dict["model"] as? String ?? ""

        return CronJobInfo(
            cronId: id,
            name: name,
            schedule: schedule,
            timezone: timezone,
            agentId: agentId,
            sessionTarget: sessionTarget,
            message: message,
            enabled: enabled,
            nextRun: nextRun,
            lastRun: lastRun,
            status: status,
            model: model
        )
    }

    /// Format a millisecond timestamp to a readable date string
    private static func formatTimestamp(_ value: Any?) -> String {
        guard let ms = value as? Double ?? (value as? Int).map({ Double($0) }) else { return "" }
        let date = Date(timeIntervalSince1970: ms / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    /// Add a new cron job
    func addCronJob(name: String, schedule: String, timezone: String, agentId: String, message: String, sessionTarget: String) async {
        isPerformingAction = true
        var cmd = "openclaw cron add --name '\(name)' --cron '\(schedule)'"
        if !timezone.isEmpty {
            cmd += " --tz '\(timezone)'"
        }
        if !agentId.isEmpty {
            cmd += " --agent '\(agentId)'"
        }
        if !sessionTarget.isEmpty {
            cmd += " --session-target '\(sessionTarget)'"
        }
        if !message.isEmpty {
            let escapedMessage = message.replacingOccurrences(of: "'", with: "'\\''")
            cmd += " --message '\(escapedMessage)'"
        }
        cmd += " --json 2>&1"

        let output = await openclawService.runCommand(cmd)
        if let output = output, output.lowercased().contains("error") && !output.contains("{") {
            showErrorMessage("Failed to add cron job: \(output)")
        } else {
            showSuccessMessage("Cron job '\(name)' created")
        }
        await loadCronJobs()
        isPerformingAction = false
    }

    /// Enable a cron job
    func enableCronJob(_ job: CronJobInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw cron enable \(job.cronId) 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to enable cron job: \(output)")
        } else {
            showSuccessMessage("Cron job '\(job.name)' enabled")
        }
        await loadCronJobs()
        isPerformingAction = false
    }

    /// Disable a cron job
    func disableCronJob(_ job: CronJobInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw cron disable \(job.cronId) 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to disable cron job: \(output)")
        } else {
            showSuccessMessage("Cron job '\(job.name)' disabled")
        }
        await loadCronJobs()
        isPerformingAction = false
    }

    /// Remove a cron job
    func removeCronJob(_ job: CronJobInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw cron rm \(job.cronId) 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to remove cron job: \(output)")
        } else {
            showSuccessMessage("Cron job '\(job.name)' removed")
        }
        await loadCronJobs()
        isPerformingAction = false
    }

    /// Manually run a cron job
    func runCronJob(_ job: CronJobInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw cron run \(job.cronId) 2>&1",
            timeout: 120
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to run cron job: \(output)")
        } else {
            showSuccessMessage("Cron job '\(job.name)' triggered")
        }
        await loadCronJobs()
        isPerformingAction = false
    }

    // MARK: - Model Management

    /// Load models overview, model list, and fallback lists
    func loadModels() async {
        isLoadingModels = true
        async let statusOutput = openclawService.runCommand(
            "openclaw models status 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        async let listOutput = openclawService.runCommand(
            "openclaw models list 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        async let fbOutput = openclawService.runCommand(
            "openclaw models fallbacks list 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        async let imgFbOutput = openclawService.runCommand(
            "openclaw models image-fallbacks list 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        modelOverview = Self.parseModelStatus(output: await statusOutput)
        models = Self.parseModelList(output: await listOutput)
            .sorted { a, b in
                // Image-capable models first
                if a.supportsImage != b.supportsImage { return a.supportsImage }
                // Then by context length descending
                let aCtx = Self.parseContextLength(a.contextLength)
                let bCtx = Self.parseContextLength(b.contextLength)
                if aCtx != bCtx { return aCtx > bCtx }
                return a.modelId.localizedCaseInsensitiveCompare(b.modelId) == .orderedAscending
            }
        fallbackModels = Self.parseFallbackList(output: await fbOutput)
        imageFallbackModels = Self.parseFallbackList(output: await imgFbOutput)
        isLoadingModels = false
    }

    /// Parse `models status` output for overview info
    static func parseModelStatus(output: String?) -> ModelOverview {
        guard let output = output else { return ModelOverview() }

        var overview = ModelOverview()
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()

            if lower.hasPrefix("default") {
                if let value = Self.extractStatusValue(trimmed) {
                    overview.defaultModel = value
                }
            } else if lower.hasPrefix("image model") {
                if let value = Self.extractStatusValue(trimmed) {
                    overview.imageModel = value == "-" ? nil : value
                }
            } else if lower.hasPrefix("fallbacks") {
                if let value = Self.extractStatusValue(trimmed) {
                    overview.fallbacks = value == "-" ? "" : value
                }
            } else if lower.hasPrefix("image fallbacks") {
                if let value = Self.extractStatusValue(trimmed) {
                    overview.imageFallbacks = value == "-" ? "" : value
                }
            } else if lower.hasPrefix("aliases") {
                if let value = Self.extractStatusValue(trimmed) {
                    overview.aliases = value == "-" ? "" : value
                }
            }
        }
        return overview
    }

    /// Extract value after ": " in a status line
    private static func extractStatusValue(_ line: String) -> String? {
        guard let colonIdx = line.firstIndex(of: ":") else { return nil }
        let value = line[line.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Parse `fallbacks list` or `image-fallbacks list` output.
    /// Format: "Fallbacks (N):" followed by "- model1" lines, or "- none"
    static func parseFallbackList(output: String?) -> [String] {
        guard let output = output else { return [] }
        var results: [String] = []
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else { continue }
            let value = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if value.lowercased() == "none" || value.isEmpty { continue }
            results.append(value)
        }
        return results
    }

    /// Parse context length string like "128k", "200k", "1M" into a comparable integer.
    static func parseContextLength(_ str: String) -> Int {
        let s = str.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasSuffix("m") {
            return (Int(s.dropLast()) ?? 0) * 1_000_000
        } else if s.hasSuffix("k") {
            return (Int(s.dropLast()) ?? 0) * 1_000
        }
        return Int(s) ?? 0
    }

    /// Parse `models list` output using fixed column positions from header.
    static func parseModelList(output: String?) -> [ModelInfo] {
        guard let output = output else { return [] }

        var results: [ModelInfo] = []
        // Column positions parsed from header
        var colInput = 0
        var colCtx = 0
        var colLocal = 0
        var colAuth = 0
        var colTags = 0
        var headerFound = false

        for line in output.components(separatedBy: .newlines) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            // Detect header and extract column positions
            if !headerFound {
                if let rModel = line.range(of: "Model"),
                   let rInput = line.range(of: "Input"),
                   let rCtx = line.range(of: "Ctx"),
                   let rAuth = line.range(of: "Auth"),
                   let rTags = line.range(of: "Tags") {
                    colInput = line.distance(from: line.startIndex, to: rInput.lowerBound)
                    colCtx = line.distance(from: line.startIndex, to: rCtx.lowerBound)
                    // Local column is optional
                    if let rLocal = line.range(of: "Local") {
                        colLocal = line.distance(from: line.startIndex, to: rLocal.lowerBound)
                    } else {
                        colLocal = colAuth
                    }
                    colAuth = line.distance(from: line.startIndex, to: rAuth.lowerBound)
                    colTags = line.distance(from: line.startIndex, to: rTags.lowerBound)
                    headerFound = true
                }
                continue
            }

            // Extract columns by position
            let len = line.count
            guard len > colInput else { continue }

            func substr(from: Int, to: Int) -> String {
                guard from < len else { return "" }
                let end = min(to, len)
                let start = line.index(line.startIndex, offsetBy: from)
                let finish = line.index(line.startIndex, offsetBy: end)
                return String(line[start..<finish]).trimmingCharacters(in: .whitespaces)
            }

            let modelId = substr(from: 0, to: colInput)
            let input = substr(from: colInput, to: colCtx)
            let ctx = substr(from: colCtx, to: colLocal)
            let local = substr(from: colLocal, to: colAuth)
            let auth = substr(from: colAuth, to: colTags)
            let tags = len > colTags ? String(line[line.index(line.startIndex, offsetBy: colTags)...]).trimmingCharacters(in: .whitespaces) : ""

            guard !modelId.isEmpty else { continue }

            let isDefault = tags.lowercased().contains("default")
            let supportsImage = input.lowercased().contains("image")

            results.append(ModelInfo(
                modelId: modelId,
                input: input,
                contextLength: ctx,
                local: local.lowercased() == "yes",
                authenticated: auth.lowercased() == "yes",
                isDefault: isDefault,
                supportsImage: supportsImage,
                tags: tags
            ))
        }

        return results
    }

    /// Set default model
    func setDefaultModel(_ model: ModelInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw models set '\(model.modelId)' 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to set default model: \(output)")
        } else {
            showSuccessMessage("Default model set to \(model.modelId)")
        }
        await loadModels()
        isPerformingAction = false
    }

    /// Set image model
    func setImageModel(_ model: ModelInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw models set-image '\(model.modelId)' 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to set image model: \(output)")
        } else {
            showSuccessMessage("Image model set to \(model.modelId)")
        }
        await loadModels()
        isPerformingAction = false
    }

    /// Add a model to fallback list
    func addFallback(_ model: ModelInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw models fallbacks add '\(model.modelId)' 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to add fallback: \(output)")
        } else {
            showSuccessMessage("\(model.modelId) added to fallbacks")
        }
        await loadModels()
        isPerformingAction = false
    }

    /// Remove a model from fallback list
    func removeFallback(_ modelId: String) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw models fallbacks remove '\(modelId)' 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to remove fallback: \(output)")
        } else {
            showSuccessMessage("\(modelId) removed from fallbacks")
        }
        await loadModels()
        isPerformingAction = false
    }

    /// Add a model to image fallback list
    func addImageFallback(_ model: ModelInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw models image-fallbacks add '\(model.modelId)' 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to add image fallback: \(output)")
        } else {
            showSuccessMessage("\(model.modelId) added to image fallbacks")
        }
        await loadModels()
        isPerformingAction = false
    }

    /// Remove a model from image fallback list
    func removeImageFallback(_ modelId: String) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw models image-fallbacks remove '\(modelId)' 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to remove image fallback: \(output)")
        } else {
            showSuccessMessage("\(modelId) removed from image fallbacks")
        }
        await loadModels()
        isPerformingAction = false
    }
}

// MARK: - Plugin Info Model

struct PluginInfo: Identifiable {
    let id = UUID()
    let channel: String
    let pluginId: String
    var installed: Bool
    var enabled: Bool
}

// MARK: - Channel Info Model

struct ChannelInfo: Identifiable {
    let id = UUID()
    let name: String
    let account: String
    let enabled: Bool
    let configured: Bool
    let linked: Bool
    let error: String?
    let statusTags: [String]
}

// MARK: - Model Info

struct ModelOverview {
    var defaultModel: String = "-"
    var imageModel: String?
    var fallbacks: String = ""
    var imageFallbacks: String = ""
    var aliases: String = ""
}

struct ModelInfo: Identifiable {
    let id = UUID()
    let modelId: String
    let input: String
    let contextLength: String
    let local: Bool
    let authenticated: Bool
    var isDefault: Bool
    let supportsImage: Bool
    let tags: String
}

// MARK: - Chat Message

struct ChatMessage: Identifiable {
    let id: UUID
    let role: ChatRole
    let content: String
    let agentId: String?
    let agentEmoji: String?
    let attachments: [URL]
    let taskStatus: TaskStatus
    let scrollTargetId: UUID?  // For notification messages: ID of the message to scroll to

    init(role: ChatRole, content: String, agentId: String? = nil, agentEmoji: String? = nil, attachments: [URL] = [], taskStatus: TaskStatus = .completed, id: UUID = UUID(), scrollTargetId: UUID? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.agentId = agentId
        self.agentEmoji = agentEmoji
        self.attachments = attachments
        self.taskStatus = taskStatus
        self.scrollTargetId = scrollTargetId
    }

    enum ChatRole {
        case user
        case assistant
    }

    enum TaskStatus {
        case loading      // Foreground: waiting for result
        case background   // Moved to background, still running
        case completed    // Done
        case timedOut     // Timed out, process terminated
    }
}

// MARK: - Skill Info

enum SkillStatus: String {
    case ready = "ready"
    case missing = "missing"
}

struct SkillsSummary {
    var ready: Int = 0
    var total: Int = 0
}

struct SkillInfo: Identifiable {
    let id = UUID()
    let name: String
    let status: SkillStatus
    let description: String
    let source: String
}

struct SkillDetailInfo: Identifiable {
    let id = UUID()
    let name: String
    let status: String
    let isReady: Bool
    let description: String
    let source: String
    let path: String
    let requirements: [String]
}

// MARK: - Agent Option

struct AgentOption: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
}

// MARK: - Cron Job Info

struct CronJobInfo: Identifiable {
    let id = UUID()
    let cronId: String
    let name: String
    let schedule: String
    let timezone: String
    let agentId: String
    let sessionTarget: String
    let message: String
    let enabled: Bool
    let nextRun: String
    let lastRun: String
    let status: String
    let model: String
}
