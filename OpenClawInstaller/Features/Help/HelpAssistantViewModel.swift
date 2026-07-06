import Foundation
import Combine

// MARK: - Help Message Model

struct HelpMessage: Identifiable {
    let id = UUID()
    let role: HelpRole
    let content: String

    enum HelpRole {
        case user
        case assistant
    }
}

// MARK: - Help Assistant ViewModel

@MainActor
class HelpAssistantViewModel: ObservableObject {
    @Published var messages: [HelpMessage] = []
    @Published var isLoading = false
    @Published var inputText = ""

    private weak var dashboardViewModel: DashboardViewModel?
    private let faqMatcher = HelpFAQMatcher.shared
    private var userGuideContent: String = ""

    var isServiceRunning: Bool {
        dashboardViewModel?.openclawService.status == .running
    }

    var currentTab: DashboardViewModel.DashboardTab? {
        dashboardViewModel?.selectedTab
    }

    init(dashboardViewModel: DashboardViewModel) {
        self.dashboardViewModel = dashboardViewModel
        loadUserGuide()
    }

    // MARK: - User Guide Loading

    private func loadUserGuide() {
        if let url = Bundle.main.url(forResource: "用户指南", withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            userGuideContent = content
        }
    }

    // MARK: - Ensure Help Agent

    /// Create a dedicated help-assistant agent in openclaw.json if it doesn't exist.
    /// Also ensures IDENTITY.md and SOUL.md are written to the workspace directory
    /// (openclaw reads persona from workspace, not agentDir).
    private func ensureHelpAgent() {
        let configPath = NSString("~/.openclaw/openclaw.json").expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: configPath),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        var agentsSection = json["agents"] as? [String: Any] ?? [:]
        var agentList = agentsSection["list"] as? [[String: Any]] ?? []

        let agentDir = NSString("~/.openclaw/agents/help-assistant/agent").expandingTildeInPath
        let workspaceDir = NSString("~/.openclaw/workspace-help-assistant").expandingTildeInPath

        // Always ensure SOUL.md and IDENTITY.md are up-to-date in the workspace
        try? FileManager.default.createDirectory(atPath: workspaceDir, withIntermediateDirectories: true)

        let soulContent = buildSoulContent()
        let soulPath = (workspaceDir as NSString).appendingPathComponent("SOUL.md")
        try? soulContent.write(toFile: soulPath, atomically: true, encoding: .utf8)

        let identityContent = """
        # IDENTITY.md - Who Am I?

        - **Name:** Help Assistant
        - **Creature:** GetClawHub Customer Support Bot
        - **Vibe:** Concise, practical, helpful
        """
        let identityPath = (workspaceDir as NSString).appendingPathComponent("IDENTITY.md")
        try? identityContent.write(toFile: identityPath, atomically: true, encoding: .utf8)

        // Check if agent already exists in config
        if agentList.contains(where: { ($0["id"] as? String) == "help-assistant" }) {
            return
        }

        // Create agent directory
        try? FileManager.default.createDirectory(atPath: agentDir, withIntermediateDirectories: true)

        let entry: [String: Any] = [
            "id": "help-assistant",
            "name": "help-assistant",
            "default": false,
            "identity": [
                "name": "Help Assistant",
                "emoji": "❓"
            ],
            "agentDir": agentDir,
            "workspace": workspaceDir
        ]
        agentList.append(entry)
        agentsSection["list"] = agentList
        json["agents"] = agentsSection

        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: URL(fileURLWithPath: configPath))
        }
    }

    // MARK: - Build SOUL.md Content

    /// Build the SOUL.md persona content for the Help Assistant agent.
    /// This is written to the workspace so openclaw loads it as the agent's system prompt.
    private func buildSoulContent() -> String {
        var parts: [String] = []

        parts.append("""
        # SOUL.md - GetClawHub Help Assistant

        ## You Are

        You are the GetClawHub Help Assistant, a customer support bot exclusively for the GetClawHub macOS application.

        ## Rules

        1. ONLY answer questions related to GetClawHub usage, features, configuration, and troubleshooting.
        2. If the user asks anything unrelated to GetClawHub (coding help, general knowledge, casual chat, etc.), politely decline and say: "This question is beyond my scope. Please use the Chat page to ask your AI assistant." (Use the user's language for this response.)
        3. ALWAYS reply in the same language the user uses. If the user writes in Chinese, reply in Chinese. If in English, reply in English. Match the user's language exactly.
        4. Keep answers concise, practical, and step-by-step.
        5. When referencing app pages, use their exact names: Chat, Status, Persona, Multi-Agent, Configuration, Skills, Models, Channels, Plugins, Cron, Logs, Doctor.
        """)

        if !userGuideContent.isEmpty {
            parts.append("""
            ## User Guide

            Below is the complete GetClawHub User Guide. Base all your answers on this document:

            ---
            \(userGuideContent)
            ---
            """)
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Send Question

    func sendQuestion(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(HelpMessage(role: .user, content: trimmed))
        inputText = ""

        if isServiceRunning {
            sendToAI(trimmed)
        } else {
            answerFromFAQ(trimmed)
        }
    }

    // MARK: - AI Mode

    private func sendToAI(_ question: String) {
        guard let vm = dashboardViewModel else { return }

        isLoading = true

        // Ensure the dedicated help-assistant agent exists with up-to-date SOUL.md
        ensureHelpAgent()

        // Only inject dynamic context (app state) — static persona is in SOUL.md
        let contextInfo = buildContextInfo()
        let fullMessage: String
        if contextInfo.isEmpty {
            fullMessage = question
        } else {
            fullMessage = """
            [Current App Context]
            \(contextInfo)

            [User Question]
            \(question)
            """
        }

        // Write to temp file to avoid shell escaping issues with large content (12KB+ user guide)
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("getclawhub_help_\(UUID().uuidString).txt")

        Task {
            defer { try? FileManager.default.removeItem(at: tempFile) }

            do {
                try fullMessage.write(to: tempFile, atomically: true, encoding: .utf8)
            } catch {
                messages.append(HelpMessage(role: .assistant, content: "Sorry, I could not get a response. Please try again."))
                isLoading = false
                return
            }

            let escapedPath = tempFile.path.replacingOccurrences(of: "'", with: "'\\''")
            // Use dedicated help-assistant agent to avoid polluting the main chat session.
            let command = "openclaw agent --agent help-assistant -m \"$(cat '\(escapedPath)')\" 2>&1"
            let output = await vm.openclawService.runCommand(command, timeout: 120)
            let reply = Self.filterOutput(output)

            messages.append(HelpMessage(role: .assistant, content: reply ?? "Sorry, I could not get a response. Please try again."))
            isLoading = false
        }
    }

    // MARK: - FAQ Mode

    private func answerFromFAQ(_ question: String) {
        if let item = faqMatcher.match(question) {
            let answer = faqMatcher.answer(for: item, input: question)
            messages.append(HelpMessage(role: .assistant, content: answer))
        } else {
            let fallback = faqMatcher.fallbackAnswer(for: question)
            messages.append(HelpMessage(role: .assistant, content: fallback))
        }
    }

    // MARK: - Context Info Builder

    /// Build dynamic context about current app state to inject into messages.
    /// Static persona and user guide are in SOUL.md (loaded by openclaw automatically).
    private func buildContextInfo() -> String {
        guard let vm = dashboardViewModel else { return "" }

        let tabName = vm.selectedTab.rawValue
        let serviceStatus = vm.openclawService.status.rawValue
        let version = vm.openclawService.version.isEmpty ? "Unknown" : vm.openclawService.version
        let port = vm.openclawService.port
        let provider = vm.editedSelectedProviderKey.isEmpty ? "Not configured" : vm.editedSelectedProviderKey

        return """
        - Active page: \(tabName)
        - Service status: \(serviceStatus)
        - OpenClaw version: \(version)
        - Configured provider: \(provider)
        - Port: \(port)
        """
    }

    // MARK: - Output Filtering

    /// Filter raw CLI output, removing ANSI codes and noise lines.
    /// Aligned with DashboardViewModel.filterAgentOutput.
    private static func filterOutput(_ output: String?) -> String? {
        guard let raw = output, !raw.isEmpty else { return nil }

        let ansiPattern = "\u{1B}\\[[0-9;]*[a-zA-Z]"
        let cleaned = raw.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)

        let lines = cleaned.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return true }
            if trimmed.hasPrefix("[agent-scope]") { return false }
            if trimmed.hasPrefix("[plugins]") { return false }
            if trimmed.hasPrefix("[cli]") { return false }
            if trimmed.hasPrefix("Config warnings:") { return false }
            if trimmed.hasPrefix("Config overwrite:") { return false }
            if trimmed.hasPrefix("- plugins.") { return false }
            if trimmed.hasPrefix("- ") && trimmed.contains("plugin") && trimmed.contains("detected") { return false }
            if trimmed.contains("plugins.allow is empty") { return false }
            if trimmed.contains("Multiple agents marked default") { return false }
            if ["◻", "◼", "━"].contains(where: { trimmed.hasPrefix($0) }) { return false }
            return true
        }

        let result = filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    // MARK: - Quick Questions

    func quickQuestionKeys(for tab: DashboardViewModel.DashboardTab) -> [String] {
        switch tab {
        case .status:
            return ["help.quick.status.start", "help.quick.status.restart", "help.quick.status.systemInfo"]
        case .config:
            return ["help.quick.config.models", "help.quick.config.port", "help.quick.config.provider"]
        case .chat:
            return ["help.quick.chat.slash", "help.quick.chat.switchAssistant", "help.quick.chat.history"]
        case .cron:
            return ["help.quick.cron.create", "help.quick.cron.expression", "help.quick.cron.pause"]
        case .persona:
            return ["help.quick.persona.edit", "help.quick.persona.files", "help.quick.persona.preview"]
        case .subAgents:
            return ["help.quick.subAgents.create", "help.quick.subAgents.switch", "help.quick.subAgents.delete"]
        case .skills:
            return ["help.quick.skills.install", "help.quick.skills.status", "help.quick.skills.findMore"]
        case .models:
            return ["help.quick.models.default", "help.quick.models.fallback", "help.quick.models.image"]
        case .channels:
            return ["help.quick.channels.telegram", "help.quick.channels.status", "help.quick.channels.remove"]
        case .plugins:
            return ["help.quick.plugins.enable", "help.quick.plugins.available", "help.quick.plugins.status"]
        case .logs:
            return ["help.quick.logs.search", "help.quick.logs.colors", "help.quick.logs.export"]
        case .budget:
            return ["help.quick.budget.set", "help.quick.budget.alerts", "help.quick.budget.costs"]
        case .billing:
            return ["help.quick.billing.view", "help.quick.billing.limit", "help.quick.billing.reset"]
        case .market:
            return ["help.quick.market.install", "help.quick.market.contents", "help.quick.market.uninstall"]
        case .tasksLogs:
            return ["help.quick.tasks.create", "help.quick.tasks.pause", "help.quick.tasks.edit"]
        case .outputs:
            return ["help.quick.outputs.what", "help.quick.outputs.hidden", "help.quick.outputs.open"]
        }
    }

    func clearMessages() {
        messages.removeAll()
    }
}
