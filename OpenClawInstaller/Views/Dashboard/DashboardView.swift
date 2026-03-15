import SwiftUI
import UniformTypeIdentifiers
import AVKit

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    #if REQUIRE_LOGIN
    @EnvironmentObject var authManager: AuthManager
    #endif
    @AppStorage("appAppearance") private var appAppearance: String = "system"

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedTab: $viewModel.selectedTab, viewModel: viewModel)
        } detail: {
            DetailContentView(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(colorSchemeForAppearance)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .overlay(alignment: .top) {
            if viewModel.showSuccess {
                SuccessToast(message: viewModel.successMessage)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: viewModel.showSuccess)
        .onAppear {
            viewModel.openclawService.startMonitoring()
            Task {
                await viewModel.openclawService.fetchVersion()
            }
        }
        .onDisappear {
            viewModel.openclawService.stopMonitoring()
        }
        .sheet(isPresented: $viewModel.showDiagnostics) {
            DiagnosticsSheet(report: viewModel.diagnosticReport, isPresented: $viewModel.showDiagnostics)
        }
    }

    private var colorSchemeForAppearance: ColorScheme? {
        switch appAppearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selectedTab: DashboardViewModel.DashboardTab
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject var sparkleUpdater: SparkleUpdater
    @EnvironmentObject var languageManager: LanguageManager
    #if REQUIRE_LOGIN
    @EnvironmentObject var authManager: AuthManager
    #endif
    @AppStorage("appAppearance") private var appAppearance: String = "system"
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        if appAppearance == "dark" { return true }
        if appAppearance == "light" { return false }
        return colorScheme == .dark
    }

    var body: some View {
        List(selection: $selectedTab) {
            ServiceStatusBadge(viewModel: viewModel)
                .listRowSeparator(.hidden)
                .padding(.bottom, 8)

            Section("Chat") {
                Label("Chat", systemImage: "message.fill")
                    .tag(DashboardViewModel.DashboardTab.chat)
            }

            Section("Overview") {
                Label("Status", systemImage: "chart.bar.fill")
                    .tag(DashboardViewModel.DashboardTab.status)
            }

            Section("Agent") {
                Label("Persona", systemImage: "person.text.rectangle")
                    .tag(DashboardViewModel.DashboardTab.persona)
                Label("Multi-Agent", systemImage: "person.3.fill")
                    .tag(DashboardViewModel.DashboardTab.subAgents)
            }

            Section("Settings") {
                Label("Configuration", systemImage: "gearshape")
                    .tag(DashboardViewModel.DashboardTab.config)
                Label("Skills", systemImage: "bolt.fill")
                    .tag(DashboardViewModel.DashboardTab.skills)
                Label("Models", systemImage: "cube.fill")
                    .tag(DashboardViewModel.DashboardTab.models)
                Label("Channels", systemImage: "bubble.left.and.bubble.right.fill")
                    .tag(DashboardViewModel.DashboardTab.channels)
                Label("Plugins", systemImage: "puzzlepiece.fill")
                    .tag(DashboardViewModel.DashboardTab.plugins)
            }

            Section("Tools") {
                Label("Cron", systemImage: "clock.badge")
                    .tag(DashboardViewModel.DashboardTab.cron)
                Label("Logs", systemImage: "doc.text.magnifyingglass")
                    .tag(DashboardViewModel.DashboardTab.logs)

                Button(action: {
                    Task { await viewModel.runDiagnostics() }
                }) {
                    Label("Doctor", systemImage: "stethoscope")
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                // User status
                #if REQUIRE_LOGIN
                HStack(spacing: 6) {
                    if case .loggedIn(let nickname) = authManager.state {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                        Text(nickname)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Button("Log Out") {
                            authManager.logout()
                        }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        Text("Not Logged In")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Log In") {
                            authManager.login()
                        }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)

                Divider()
                #endif

                // Language selector
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                Menu {
                    ForEach(languageManager.supportedLanguages) { lang in
                        Button(action: { languageManager.selectedLanguage = lang.id }) {
                            HStack {
                                Text(lang.name)
                                if languageManager.selectedLanguage == lang.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(languageManager.displayName)
                            .font(.caption)
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GetClawHub")
                        .font(.caption)
                        .fontWeight(.medium)

                    HStack(spacing: 4) {
                        Text("v\(sparkleUpdater.currentVersion)")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        // Version check button / status
                        if sparkleUpdater.isCheckingVersion {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.7)
                        } else if sparkleUpdater.updateAvailable {
                            Button(action: { sparkleUpdater.checkForUpdates() }) {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 10))
                                    Text("v\(sparkleUpdater.latestVersion)")
                                        .font(.caption2)
                                }
                                .foregroundColor(.green)
                            }
                            .buttonStyle(.plain)
                            .help("Update to v\(sparkleUpdater.latestVersion)")
                        } else if sparkleUpdater.checkSucceeded {
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                Text("Latest")
                                    .font(.caption2)
                            }
                            .foregroundColor(.green)
                        } else {
                            Button(action: {
                                Task { await sparkleUpdater.checkLatestVersion() }
                            }) {
                                HStack(spacing: 2) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 10))
                                    Text("Update")
                                        .font(.caption2)
                                }
                                .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Check for Updates")
                        }
                    }
                }

                Spacer()

                Button(action: {
                    HelpAssistantWindowController.shared.showWindow(dashboardViewModel: viewModel)
                }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Help Assistant")

                Button(action: {
                    appAppearance = isDark ? "light" : "dark"
                }) {
                    Image(systemName: isDark ? "sun.max.fill" : "moon.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(isDark ? "Switch to Light Mode" : "Switch to Dark Mode")
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 280)
    }
}

// MARK: - Service Status Badge

struct ServiceStatusBadge: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.openclawService.status.rawValue)
                    .font(.headline)

                if !viewModel.openclawService.version.isEmpty {
                    Text("v\(viewModel.openclawService.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch viewModel.openclawService.status {
        case .running: return .green
        case .stopped: return .gray
        case .starting, .stopping: return .orange
        case .error: return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - Detail Content

struct DetailContentView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        Group {
            switch viewModel.selectedTab {
            case .chat:
                ChatView(viewModel: viewModel)
            case .status:
                StatusTabView(viewModel: viewModel)
            case .persona:
                PersonaTabView()
            case .subAgents:
                SubAgentsTabView(openclawService: viewModel.openclawService)
            case .config:
                ConfigTabView(viewModel: viewModel)
            case .skills:
                SkillsTabView(viewModel: viewModel)
            case .models:
                ModelsTabView(viewModel: viewModel)
            case .channels:
                ChannelsTabView(viewModel: viewModel)
            case .plugins:
                PluginsTabView(viewModel: viewModel)
            case .cron:
                CronTabView(viewModel: viewModel)
            case .logs:
                LogsTabView(viewModel: viewModel)
            }
        }
        .onChange(of: viewModel.selectedTab) { newTab in
            if newTab == .chat {
                viewModel.loadAvailableAgents()
            }
        }
    }
}

// MARK: - Slash Command Model

struct SlashCommand: Identifiable {
    let id: String  // e.g. "/help"
    let name: String
    let description: String
    let hasParam: Bool
}

private let slashCommands: [SlashCommand] = [
    // Core
    SlashCommand(id: "/help",       name: "/help",       description: "Show help",               hasParam: false),
    SlashCommand(id: "/status",     name: "/status",     description: "View session status",      hasParam: false),
    SlashCommand(id: "/agent",      name: "/agent",      description: "Switch agent",             hasParam: true),
    SlashCommand(id: "/agents",     name: "/agents",     description: "List agents",              hasParam: false),
    SlashCommand(id: "/session",    name: "/session",    description: "Switch session",           hasParam: true),
    SlashCommand(id: "/sessions",   name: "/sessions",   description: "List sessions",            hasParam: false),
    SlashCommand(id: "/model",      name: "/model",      description: "Switch model",             hasParam: true),
    SlashCommand(id: "/models",     name: "/models",     description: "List models",              hasParam: false),
    // Session control
    SlashCommand(id: "/think",      name: "/think",      description: "Set thinking level",       hasParam: true),
    SlashCommand(id: "/verbose",    name: "/verbose",    description: "Verbose output mode",      hasParam: true),
    SlashCommand(id: "/reasoning",  name: "/reasoning",  description: "Reasoning mode toggle",    hasParam: true),
    SlashCommand(id: "/usage",      name: "/usage",      description: "Usage display mode",       hasParam: true),
    SlashCommand(id: "/elevated",   name: "/elevated",   description: "Elevated permission mode", hasParam: true),
    SlashCommand(id: "/activation", name: "/activation", description: "Activation mode",          hasParam: true),
    SlashCommand(id: "/deliver",    name: "/deliver",    description: "Message delivery toggle",  hasParam: true),
    // Session lifecycle
    SlashCommand(id: "/new",        name: "/new",        description: "Reset session",            hasParam: false),
    SlashCommand(id: "/reset",      name: "/reset",      description: "Reset session",            hasParam: false),
    SlashCommand(id: "/abort",      name: "/abort",      description: "Abort current run",        hasParam: false),
    SlashCommand(id: "/settings",   name: "/settings",   description: "Open settings",            hasParam: false),
    SlashCommand(id: "/exit",       name: "/exit",       description: "Exit app",                 hasParam: false),
    // Skills
    SlashCommand(id: "/skills",     name: "/skills",     description: "Use a skill",              hasParam: true),
]

// MARK: - Chat View

struct ChatView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var inputText = ""
    @State private var eventMonitor: Any?
    @State private var queryHistory: [String] = UserDefaults.standard.stringArray(forKey: "chatQueryHistory") ?? []
    @State private var historyIndex: Int = -1
    // Slash command autocomplete
    @State private var slashSelectedIndex: Int = 0
    @State private var isInputFocused: Bool = false
    @State private var focusMonitor: Any?
    // Skills panel
    @State private var skillsSelectedIndex: Int = 0
    @State private var skillJustSelected: Bool = false
    // @ Agent mention panel
    @State private var agentSelectedIndex: Int = 0
    @State private var agentJustSelected: Bool = false
    // File attachments
    @State private var attachedFiles: [URL] = []

    // MARK: - Chat Message List (extracted for compiler performance)

    @ViewBuilder
    private func chatScrollContent(proxy: ScrollViewProxy) -> some View {
        let scrollView = ScrollView {
            if viewModel.chatMessages.isEmpty {
                ChatWelcomeView()
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.chatMessages) { message in
                        if !(message.role == .assistant && message.content.isEmpty && message.attachments.isEmpty) {
                            if message.scrollTargetId != nil {
                                BackgroundTaskNotification(message: message, scrollProxy: proxy)
                                    .id(message.id)
                            } else {
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                        }
                    }

                    ForEach(viewModel.chatMessages.filter { $0.taskStatus == .loading && $0.content.isEmpty }) { loadingMsg in
                        ThinkingIndicator(
                            message: loadingMsg,
                            viewModel: viewModel
                        )
                        .id("loading-\(loadingMsg.id)")
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("chatBottom")
                }
                .padding(20)
            }
        }

        if #available(macOS 14.0, *) {
            scrollView
                .defaultScrollAnchor(.bottom)
                .onChange(of: viewModel.chatMessages.count) { _ in
                    withAnimation { proxy.scrollTo("chatBottom", anchor: .bottom) }
                }
                .onChange(of: viewModel.chatMessages.last?.content) { _ in
                    withAnimation { proxy.scrollTo("chatBottom", anchor: .bottom) }
                }
        } else {
            scrollView
                .onChange(of: viewModel.chatMessages.count) { _ in
                    withAnimation { proxy.scrollTo("chatBottom", anchor: .bottom) }
                }
                .onChange(of: viewModel.chatMessages.last?.content) { _ in
                    withAnimation { proxy.scrollTo("chatBottom", anchor: .bottom) }
                }
                .onAppear {
                    if !viewModel.chatMessages.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo("chatBottom", anchor: .bottom)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            proxy.scrollTo("chatBottom", anchor: .bottom)
                        }
                    }
                }
        }
    }

    /// Filtered slash commands based on current input
    private var filteredSlashCommands: [SlashCommand] {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return [] }
        // Only match when the input is purely a command prefix (no spaces = no param yet)
        guard !trimmed.dropFirst().contains(" ") else { return [] }
        if trimmed == "/" { return slashCommands }
        return slashCommands.filter { $0.name.hasPrefix(trimmed.lowercased()) }
    }

    private var showSlashPanel: Bool {
        !filteredSlashCommands.isEmpty && !showSkillsPanel && !showAgentPanel
    }

    /// Filtered skills based on input after "/skills "
    private var filteredSkills: [SkillInfo] {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces).lowercased()
        // Exact "/skills" or "/skills " prefix
        guard trimmed == "/skills" || trimmed.hasPrefix("/skills ") else { return [] }
        let keyword = trimmed.hasPrefix("/skills ") ? String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces) : ""
        let allSkills = viewModel.skills
        if keyword.isEmpty { return allSkills }
        return allSkills.filter { $0.name.lowercased().contains(keyword) }
    }

    private var showSkillsPanel: Bool {
        if skillJustSelected { return false }
        let trimmed = inputText.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed == "/skills" || trimmed.hasPrefix("/skills ") else { return false }
        guard !viewModel.skills.isEmpty else { return false }
        let keyword = trimmed.hasPrefix("/skills ") ? String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces) : ""
        if keyword.contains(" ") { return false }
        return true
    }

    /// Filtered agents based on input after "@"
    private var filteredAgents: [AgentOption] {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("@") else { return [] }
        let keyword = String(trimmed.dropFirst()).lowercased()
        // Only match when typing the agent name (no space yet)
        guard !keyword.contains(" ") else { return [] }
        let allAgents = viewModel.availableAgents
        if keyword.isEmpty { return allAgents }
        return allAgents.filter { $0.name.lowercased().contains(keyword) || $0.id.lowercased().contains(keyword) }
    }

    private var showAgentPanel: Bool {
        if agentJustSelected { return false }
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("@") else { return false }
        guard !viewModel.availableAgents.isEmpty else { return false }
        let keyword = String(trimmed.dropFirst())
        // Only show panel while typing agent name (before space)
        if keyword.contains(" ") { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                chatScrollContent(proxy: proxy)
            }

            // Floating card input bar with slash command overlay
            ZStack(alignment: .bottom) {
                // Slash command autocomplete panel
                if showSlashPanel {
                    VStack(spacing: 0) {
                        ScrollViewReader { slashProxy in
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(Array(filteredSlashCommands.enumerated()), id: \.element.id) { index, cmd in
                                        HStack(spacing: 8) {
                                            Text(cmd.name)
                                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                                .foregroundColor(index == slashSelectedIndex ? .white : .primary)
                                            Spacer()
                                            Text(cmd.description)
                                                .font(.system(size: 12))
                                                .foregroundColor(index == slashSelectedIndex ? .white.opacity(0.8) : .secondary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(index == slashSelectedIndex ? Color.accentColor : Color.clear)
                                        .cornerRadius(6)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectSlashCommand(filteredSlashCommands[index])
                                        }
                                        .id(cmd.id)
                                    }
                                }
                                .padding(6)
                            }
                            .onChange(of: slashSelectedIndex) { newIndex in
                                if newIndex >= 0 && newIndex < filteredSlashCommands.count {
                                    withAnimation {
                                        slashProxy.scrollTo(filteredSlashCommands[newIndex].id, anchor: .center)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 280)
                    }
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 12, y: -4)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 110) // offset above the input card
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Skills autocomplete panel
                if showSkillsPanel {
                    VStack(spacing: 0) {
                        if filteredSkills.isEmpty {
                            HStack {
                                Text("No matching skills")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        } else {
                            ScrollViewReader { skillProxy in
                                ScrollView {
                                    VStack(spacing: 0) {
                                        ForEach(Array(filteredSkills.enumerated()), id: \.element.id) { index, skill in
                                            HStack(spacing: 8) {
                                                Circle()
                                                    .fill(skill.status == .ready ? Color.green : Color.orange)
                                                    .frame(width: 8, height: 8)
                                                Text(skill.name)
                                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                                    .foregroundColor(index == skillsSelectedIndex ? .white : .primary)
                                                Spacer()
                                                if !skill.description.isEmpty {
                                                    Text(skill.description)
                                                        .font(.system(size: 11))
                                                        .foregroundColor(index == skillsSelectedIndex ? .white.opacity(0.8) : .secondary)
                                                        .lineLimit(1)
                                                }
                                                if !skill.source.isEmpty {
                                                    Text(skill.source)
                                                        .font(.system(size: 10))
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 2)
                                                        .background(
                                                            (index == skillsSelectedIndex ? Color.white.opacity(0.2) : Color.secondary.opacity(0.12))
                                                        )
                                                        .cornerRadius(4)
                                                        .foregroundColor(index == skillsSelectedIndex ? .white.opacity(0.9) : .secondary)
                                                }
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(index == skillsSelectedIndex ? Color.accentColor : Color.clear)
                                            .cornerRadius(6)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                selectSkill(filteredSkills[index])
                                            }
                                            .id("skill-\(skill.name)")
                                        }
                                    }
                                    .padding(6)
                                }
                                .onChange(of: skillsSelectedIndex) { newIndex in
                                    if newIndex >= 0 && newIndex < filteredSkills.count {
                                        withAnimation {
                                            skillProxy.scrollTo("skill-\(filteredSkills[newIndex].name)", anchor: .center)
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 280)
                        }
                    }
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 12, y: -4)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 110)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // @ Agent mention panel
                if showAgentPanel {
                    VStack(spacing: 0) {
                        if filteredAgents.isEmpty {
                            HStack {
                                Text("No matching agents")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        } else {
                            ScrollViewReader { agentProxy in
                                ScrollView {
                                    VStack(spacing: 0) {
                                        ForEach(Array(filteredAgents.enumerated()), id: \.element.id) { index, agent in
                                            HStack(spacing: 8) {
                                                Text(agent.emoji)
                                                    .font(.system(size: 16))
                                                    .frame(width: 24)
                                                Text(agent.name)
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(index == agentSelectedIndex ? .white : .primary)
                                                if agent.id != agent.name {
                                                    Text(agent.id)
                                                        .font(.system(size: 11))
                                                        .foregroundColor(index == agentSelectedIndex ? .white.opacity(0.7) : .secondary)
                                                }
                                                Spacer()
                                                if agent.id == viewModel.selectedAgentId {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 11, weight: .semibold))
                                                        .foregroundColor(index == agentSelectedIndex ? .white : .accentColor)
                                                }
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(index == agentSelectedIndex ? Color.accentColor : Color.clear)
                                            .cornerRadius(6)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                selectAgent(filteredAgents[index])
                                            }
                                            .id("agent-\(agent.id)")
                                        }
                                    }
                                    .padding(6)
                                }
                                .onChange(of: agentSelectedIndex) { newIndex in
                                    if newIndex >= 0 && newIndex < filteredAgents.count {
                                        withAnimation {
                                            agentProxy.scrollTo("agent-\(filteredAgents[newIndex].id)", anchor: .center)
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 280)
                        }
                    }
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 12, y: -4)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 110)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Input card
                VStack(spacing: 0) {
                    // Toolbar row: new chat + agent picker + attach
                    HStack(spacing: 8) {
                        Button(action: { viewModel.clearChat() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14))
                                Text("New")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("New Conversation")

                        Picker("", selection: $viewModel.selectedAgentId) {
                            ForEach(viewModel.availableAgents) { agent in
                                Text("\(agent.emoji) \(agent.name)")
                                    .tag(agent.id)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .controlSize(.small)
                        .help("Select Agent")

                        Spacer()

                        Button(action: { openFilePicker() }) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Attach File", bundle: LanguageManager.shared.localizedBundle))
                        .disabled(isInputLocked)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                    // Attachment preview bar
                    if !attachedFiles.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(attachedFiles, id: \.absoluteString) { url in
                                    AttachmentPreview(url: url) {
                                        attachedFiles.removeAll { $0 == url }
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                    }

                    // Input row: text editor + send button
                    HStack(alignment: .bottom, spacing: 8) {
                        ZStack(alignment: .topLeading) {
                            // Placeholder — hidden when focused
                            if inputText.isEmpty && !isInputFocused {
                                Text("Ask anything...")
                                    .font(.subheadline)
                                    .foregroundColor(Color(NSColor.placeholderTextColor).opacity(0.6))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .allowsHitTesting(false)
                                    .transition(.opacity)
                            }

                            // Hidden text for height calculation
                            Text(inputText.isEmpty ? " " : inputText)
                                .font(.body)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .opacity(0)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            TextEditor(text: $inputText)
                                .font(.body)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .scrollContentBackground(.hidden)
                                .disabled(isInputLocked)
                        }
                        .frame(minHeight: 36, maxHeight: 120)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)

                        Button(action: { sendMessage() }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(canSend ? .accentColor : Color(NSColor.separatorColor))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                        .animation(.easeInOut(duration: 0.15), value: canSend)
                        .padding(.bottom, 4)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: -2)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    for provider in providers {
                        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                            guard let urlData = data as? Data,
                                  let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                            DispatchQueue.main.async {
                                if !attachedFiles.contains(url) {
                                    attachedFiles.append(url)
                                }
                            }
                        }
                    }
                    return true
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showSlashPanel)
            .animation(.easeInOut(duration: 0.15), value: showSkillsPanel)
        }
        .onAppear {
            viewModel.loadAvailableAgents()
            if viewModel.skills.isEmpty {
                Task { await viewModel.loadSkills() }
            }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard let responder = event.window?.firstResponder, responder is NSTextView else {
                    return event
                }

                // Escape (keyCode 53) — close slash/skills/agent panel
                if event.keyCode == 53 && (showSlashPanel || showSkillsPanel || showAgentPanel) {
                    DispatchQueue.main.async {
                        inputText = ""
                        slashSelectedIndex = 0
                        skillsSelectedIndex = 0
                        agentSelectedIndex = 0
                    }
                    return nil
                }

                // Cmd+V (keyCode 9) — paste image from clipboard
                if event.keyCode == 9 && event.modifierFlags.contains(.command) {
                    let pb = NSPasteboard.general
                    let hasImage = pb.canReadItem(withDataConformingToTypes: [
                        NSPasteboard.PasteboardType.png.rawValue,
                        NSPasteboard.PasteboardType.tiff.rawValue
                    ])
                    // Only intercept if clipboard has image data but no text
                    let hasText = pb.string(forType: .string) != nil
                    if hasImage && !hasText {
                        DispatchQueue.main.async { pasteImageFromClipboard() }
                        return nil
                    }
                }

                // Tab (keyCode 48) — confirm slash/skills/agent selection
                if event.keyCode == 48 {
                    if showAgentPanel {
                        let agents = filteredAgents
                        if agentSelectedIndex >= 0 && agentSelectedIndex < agents.count {
                            DispatchQueue.main.async { selectAgent(agents[agentSelectedIndex]) }
                        }
                        return nil
                    }
                    if showSkillsPanel {
                        let skills = filteredSkills
                        if skillsSelectedIndex >= 0 && skillsSelectedIndex < skills.count {
                            DispatchQueue.main.async { selectSkill(skills[skillsSelectedIndex]) }
                        }
                        return nil
                    }
                    if showSlashPanel {
                        let cmds = filteredSlashCommands
                        if slashSelectedIndex >= 0 && slashSelectedIndex < cmds.count {
                            DispatchQueue.main.async { selectSlashCommand(cmds[slashSelectedIndex]) }
                        }
                        return nil
                    }
                }

                // Return without Shift
                if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
                    // If agent panel is open, confirm selection instead of sending
                    if showAgentPanel {
                        let agents = filteredAgents
                        if !agents.isEmpty && agentSelectedIndex >= 0 && agentSelectedIndex < agents.count {
                            DispatchQueue.main.async { selectAgent(agents[agentSelectedIndex]) }
                        }
                        return nil
                    }
                    // If skills panel is open, confirm selection instead of sending
                    if showSkillsPanel {
                        let skills = filteredSkills
                        if !skills.isEmpty && skillsSelectedIndex >= 0 && skillsSelectedIndex < skills.count {
                            DispatchQueue.main.async { selectSkill(skills[skillsSelectedIndex]) }
                        }
                        return nil
                    }
                    // If slash panel is open, confirm selection instead of sending
                    if showSlashPanel {
                        let cmds = filteredSlashCommands
                        if slashSelectedIndex >= 0 && slashSelectedIndex < cmds.count {
                            DispatchQueue.main.async { selectSlashCommand(cmds[slashSelectedIndex]) }
                        }
                        return nil
                    }
                    DispatchQueue.main.async { sendMessage() }
                    return nil
                }

                // ↑ (keyCode 126)
                if event.keyCode == 126 {
                    // Agent panel navigation takes priority
                    if showAgentPanel {
                        DispatchQueue.main.async {
                            if agentSelectedIndex > 0 {
                                agentSelectedIndex -= 1
                            }
                        }
                        return nil
                    }
                    // Skills panel navigation takes priority
                    if showSkillsPanel {
                        DispatchQueue.main.async {
                            if skillsSelectedIndex > 0 {
                                skillsSelectedIndex -= 1
                            }
                        }
                        return nil
                    }
                    // Slash panel navigation takes priority
                    if showSlashPanel {
                        DispatchQueue.main.async {
                            if slashSelectedIndex > 0 {
                                slashSelectedIndex -= 1
                            }
                        }
                        return nil
                    }
                    // History browsing
                    if (inputText.isEmpty || historyIndex >= 0) && !queryHistory.isEmpty {
                        if historyIndex == -1 {
                            historyIndex = queryHistory.count - 1
                        } else if historyIndex > 0 {
                            historyIndex -= 1
                        }
                        inputText = queryHistory[historyIndex]
                        return nil
                    }
                }

                // ↓ (keyCode 125)
                if event.keyCode == 125 {
                    // Agent panel navigation takes priority
                    if showAgentPanel {
                        DispatchQueue.main.async {
                            let agents = filteredAgents
                            if agentSelectedIndex < agents.count - 1 {
                                agentSelectedIndex += 1
                            }
                        }
                        return nil
                    }
                    // Skills panel navigation takes priority
                    if showSkillsPanel {
                        DispatchQueue.main.async {
                            let skills = filteredSkills
                            if skillsSelectedIndex < skills.count - 1 {
                                skillsSelectedIndex += 1
                            }
                        }
                        return nil
                    }
                    // Slash panel navigation takes priority
                    if showSlashPanel {
                        DispatchQueue.main.async {
                            let cmds = filteredSlashCommands
                            if slashSelectedIndex < cmds.count - 1 {
                                slashSelectedIndex += 1
                            }
                        }
                        return nil
                    }
                    // History browsing
                    if historyIndex >= 0 {
                        if historyIndex < queryHistory.count - 1 {
                            historyIndex += 1
                            inputText = queryHistory[historyIndex]
                        } else {
                            historyIndex = -1
                            inputText = ""
                        }
                        return nil
                    }
                }

                return event
            }

            // Focus monitor: track whether the TextEditor has focus
            focusMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { event in
                DispatchQueue.main.async {
                    if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
                        if !isInputFocused { withAnimation(.easeOut(duration: 0.15)) { isInputFocused = true } }
                    } else {
                        if isInputFocused { withAnimation(.easeIn(duration: 0.15)) { isInputFocused = false } }
                    }
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
            if let monitor = focusMonitor {
                NSEvent.removeMonitor(monitor)
                focusMonitor = nil
            }
        }
        .onChange(of: inputText) { _ in
            // Reset slash/skills/agent selection index when input changes
            slashSelectedIndex = 0
            skillsSelectedIndex = 0
            agentSelectedIndex = 0
            // Reset skill selection flag if input no longer has skill prefix
            if skillJustSelected {
                let trimmed = inputText.trimmingCharacters(in: .whitespaces).lowercased()
                if !trimmed.hasPrefix("/skills ") {
                    skillJustSelected = false
                }
            }
            // Reset agent selection flag if input no longer has @ prefix
            if agentJustSelected {
                let trimmed = inputText.trimmingCharacters(in: .whitespaces)
                if !trimmed.hasPrefix("@") {
                    agentJustSelected = false
                }
            }
        }
    }

    private var canSend: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespaces).isEmpty
        let hasFiles = !attachedFiles.isEmpty
        return (hasText || hasFiles) && !viewModel.isSendingMessage
    }

    /// Whether the input area (text + attachment) should be locked
    private var isInputLocked: Bool {
        viewModel.isSendingMessage
    }

    private func sendMessage() {
        var text = inputText.trimmingCharacters(in: .whitespaces)
        let files = attachedFiles
        guard !text.isEmpty || !files.isEmpty else { return }
        inputText = ""
        attachedFiles = []

        // Handle @agent_name prefix: strip it and use the actual message
        if text.hasPrefix("@") {
            let afterAt = String(text.dropFirst())
            if let spaceIdx = afterAt.firstIndex(of: " ") {
                let agentName = String(afterAt[afterAt.startIndex..<spaceIdx])
                let messageContent = String(afterAt[afterAt.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespaces)
                // Verify the agent exists
                if viewModel.availableAgents.contains(where: { $0.name == agentName || $0.id == agentName }) {
                    text = messageContent.isEmpty ? "hi, \(agentName)" : messageContent
                }
            } else {
                // Just "@agentName" with no message
                let agentName = afterAt.trimmingCharacters(in: .whitespaces)
                if viewModel.availableAgents.contains(where: { $0.name == agentName || $0.id == agentName }) {
                    text = "hi, \(agentName)"
                }
            }
        }

        // Update history: deduplicate, append, cap at 20, persist
        if !text.isEmpty {
            if let idx = queryHistory.firstIndex(of: text) {
                queryHistory.remove(at: idx)
            }
            queryHistory.append(text)
            if queryHistory.count > 20 {
                queryHistory.removeFirst()
            }
            UserDefaults.standard.set(queryHistory, forKey: "chatQueryHistory")
        }
        historyIndex = -1

        // Handle local commands
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        if lower == "/exit" {
            NSApp.terminate(nil)
            return
        }

        let isResetCommand = (lower == "/new" || lower == "/reset")

        Task {
            await viewModel.sendChatMessage(text, attachments: files)
            if isResetCommand {
                await MainActor.run { viewModel.clearChat() }
            }
        }
    }

    private func selectSlashCommand(_ cmd: SlashCommand) {
        slashSelectedIndex = 0
        if cmd.hasParam {
            // Fill command with trailing space, let user type the parameter
            inputText = cmd.name + " "
        } else {
            // No param — send immediately
            inputText = cmd.name
            sendMessage()
        }
    }

    private func selectSkill(_ skill: SkillInfo) {
        skillsSelectedIndex = 0
        skillJustSelected = true
        inputText = "/skills \(skill.name) "
    }

    private func selectAgent(_ agent: AgentOption) {
        agentSelectedIndex = 0
        agentJustSelected = true
        viewModel.selectedAgentId = agent.id
        inputText = "@\(agent.name) "
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .image, .pdf, .plainText,
            .audio, .movie,
            UTType(filenameExtension: "doc")!,
            UTType(filenameExtension: "docx")!,
            UTType(filenameExtension: "xls")!,
            UTType(filenameExtension: "xlsx")!,
            UTType(filenameExtension: "ppt")!,
            UTType(filenameExtension: "pptx")!,
            UTType(filenameExtension: "csv")!,
            UTType(filenameExtension: "json")!,
            UTType(filenameExtension: "md")!,
        ]
        if panel.runModal() == .OK {
            for url in panel.urls {
                if !attachedFiles.contains(url) {
                    attachedFiles.append(url)
                }
            }
        }
    }

    private func pasteImageFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let imageData = pasteboard.data(forType: .png)
                ?? pasteboard.data(forType: .tiff) else { return }

        let uploadsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw/uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: uploadsDir, withIntermediateDirectories: true)

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let fileName = "paste_\(timestamp).png"
        let fileURL = uploadsDir.appendingPathComponent(fileName)

        // Convert to PNG if needed
        if let image = NSImage(data: imageData),
           let tiffData = image.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: fileURL)
        } else {
            try? imageData.write(to: fileURL)
        }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            if !attachedFiles.contains(fileURL) {
                attachedFiles.append(fileURL)
            }
        }
    }
}

// MARK: - Chat Welcome View

struct ChatWelcomeView: View {
    private let cards: [(title: LocalizedStringKey, desc: LocalizedStringKey)] = [
        ("Daily Weather Alerts", "Auto push weather updates with outfit & travel tips"),
        ("Remote File Control", "Edit and manage local files from your phone anytime"),
        ("Mobile Remote Work", "Browse and handle tasks on-the-go without a laptop"),
        ("Social Media Auto Growth", "Auto engage and post to grow followers effortlessly"),
        ("GitHub Auto Development", "You bring ideas, I build repos and ship to stars"),
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Logo
            Image("Logo1")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 40))

            BrandTextView()

            // Subtitle
            Text("Your 24/7 all-in-one AI assistant, always at your service")
                .font(.body)
                .foregroundColor(.secondary)

            Spacer()

            // Suggestion cards
            HStack(spacing: 12) {
                ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        Text(card.desc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Background Task Notification

struct BackgroundTaskNotification: View {
    let message: ChatMessage
    let scrollProxy: ScrollViewProxy

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Agent avatar
            if let agentId = message.agentId, agentId != "main",
               let emoji = message.agentEmoji {
                Text(emoji)
                    .font(.system(size: 22))
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 24))
                    .foregroundColor(.orange)
                    .frame(width: 32, height: 32)
            }

            HStack(spacing: 6) {
                Text(message.content)
                    .font(.callout)

                Button(action: {
                    if let targetId = message.scrollTargetId {
                        withAnimation {
                            scrollProxy.scrollTo(targetId, anchor: .top)
                        }
                    }
                }) {
                    Text("View result ↑")
                        .font(.callout)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.08))
            .cornerRadius(12)

            Spacer(minLength: 60)
        }
    }
}

// MARK: - Thinking Indicator with Background Timer

struct ThinkingIndicator: View {
    let message: ChatMessage
    @ObservedObject var viewModel: DashboardViewModel
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer?

    private var showBackgroundButton: Bool {
        elapsedSeconds >= 60
    }

    var body: some View {
        HStack(spacing: 8) {
            // Agent avatar
            if let agentId = message.agentId, agentId != "main",
               let emoji = viewModel.availableAgents.first(where: { $0.id == agentId })?.emoji {
                Text(emoji)
                    .font(.system(size: 22))
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 24))
                    .foregroundColor(.orange)
                    .frame(width: 32, height: 32)
            }

            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Thinking...")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Show elapsed time
                Text(formatTime(elapsedSeconds))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)

            // "转后台" button — only visible after 60 seconds
            if showBackgroundButton {
                Button(action: {
                    viewModel.moveTaskToBackground(message.id)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 11))
                        Text("Move to Background")
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            Spacer()
        }
        .animation(.easeInOut(duration: 0.3), value: showBackgroundButton)
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }

    private func startTimer() {
        elapsedSeconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                elapsedSeconds += 1
                // Auto-move to background at 120 seconds
                if elapsedSeconds >= 120 && viewModel.foregroundTaskIds.contains(message.id) {
                    viewModel.moveTaskToBackground(message.id)
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return m > 0 ? String(format: "%d:%02d", m, s) : "\(s)s"
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage
    @State private var isHovering = false

    /// Media file URLs detected in assistant response text
    private var detectedMediaURLs: [URL] {
        guard message.role == .assistant else { return [] }
        let mediaExtensions: Set<String> = [
            "mp4", "mov", "avi", "mkv", "webm", "m4v",
            "mp3", "wav", "m4a", "aac", "flac", "ogg", "wma", "aiff",
            "jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "tiff",
        ]
        let text = message.content
        var urls: [URL] = []

        // Direct file paths with media extensions
        let extPattern = mediaExtensions.joined(separator: "|")
        let filePattern = "(/[^\\s\"'`<>()\\[\\]]+\\.(?:\(extPattern)))(?=[\\s\"'`.,;:!?)\\]\\n]|$)"
        if let regex = try? NSRegularExpression(pattern: filePattern, options: [.caseInsensitive, .anchorsMatchLines]) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                if let range = Range(captureRange, in: text) {
                    let path = String(text[range])
                    let url = URL(fileURLWithPath: path)
                    if FileManager.default.fileExists(atPath: url.path), !urls.contains(url) {
                        urls.append(url)
                    }
                }
            }
        }

        return urls
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant {
                // AI avatar: sub-agent shows emoji, main keeps system icon
                if let agentId = message.agentId, agentId != "main",
                   let emoji = message.agentEmoji {
                    Text(emoji)
                        .font(.system(size: 22))
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 24))
                        .foregroundColor(.orange)
                        .frame(width: 32, height: 32)
                }
            }

            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Attachment thumbnails (user-attached files)
                if !message.attachments.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.attachments, id: \.absoluteString) { url in
                            AttachmentThumbnail(url: url)
                        }
                    }
                }

                if !message.content.isEmpty {
                    ZStack(alignment: .topTrailing) {
                        if message.role == .assistant {
                            SelectableMarkdownView(content: message.content)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(10)
                                .background(backgroundColor)
                                .cornerRadius(12)
                        } else {
                            Text(message.content)
                                .padding(10)
                                .background(backgroundColor)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .textSelection(.enabled)
                        }

                        // Hover copy button
                        if isHovering && !message.content.isEmpty {
                            Button(action: { copyToClipboard(message.content) }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .padding(5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(NSColor.windowBackgroundColor))
                                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .padding(6)
                            .transition(.opacity)
                        }
                    }
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isHovering = hovering
                        }
                    }
                    .contextMenu {
                        Button(action: { copyToClipboard(message.content) }) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                }

                // Detected media files from assistant response
                if !detectedMediaURLs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(detectedMediaURLs, id: \.absoluteString) { url in
                            AttachmentThumbnail(url: url)
                        }
                    }
                }

                // Background task indicator
                if message.taskStatus == .background {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Running in background...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                }
            }

            if message.role == .assistant { Spacer(minLength: 60) }

            if message.role == .user {
                // User avatar
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
                    .frame(width: 32, height: 32)
            }
        }
    }

    private var backgroundColor: Color {
        message.role == .user ? .accentColor : Color(NSColor.controlBackgroundColor)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Attachment Thumbnail (in chat bubble)

struct AttachmentThumbnail: View {
    let url: URL

    private var fileType: AttachmentFileType {
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "tiff", "svg"].contains(ext) {
            return .image
        } else if ["mp4", "mov", "avi", "mkv", "webm", "m4v"].contains(ext) {
            return .video
        } else if ["mp3", "wav", "m4a", "aac", "flac", "ogg", "wma", "aiff"].contains(ext) {
            return .audio
        }
        return .other
    }

    enum AttachmentFileType {
        case image, video, audio, other
    }

    var body: some View {
        switch fileType {
        case .image:
            if let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 300, maxHeight: 300)
                    .cornerRadius(8)
            } else {
                fileIcon
            }
        case .video:
            InlineVideoPlayer(url: url)
        case .audio:
            InlineAudioPlayer(url: url)
        case .other:
            fileIcon
        }
    }

    private var fileIcon: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
            Text(url.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var iconName: String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "ppt", "pptx": return "rectangle.fill.on.rectangle.fill"
        case "zip", "rar", "7z", "tar", "gz": return "archivebox.fill"
        case "json", "xml", "yaml", "yml": return "curlybraces"
        case "md", "txt": return "doc.plaintext"
        default: return "doc.fill"
        }
    }
}

// MARK: - Inline Video Player

struct InlineVideoPlayer: View {
    let url: URL
    @State private var showPlayer = false
    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack {
            if showPlayer {
                NativeVideoPlayerView(url: url)
                    .frame(width: 280, height: 180)
                    .cornerRadius(8)
            } else {
                // Thumbnail placeholder with play button
                ZStack {
                    if let thumb = thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 280, height: 180)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color(NSColor.controlBackgroundColor))
                            .frame(width: 280, height: 180)
                        Image(systemName: "film")
                            .font(.system(size: 30))
                            .foregroundColor(.secondary)
                    }

                    // Play button overlay
                    Button(action: { showPlayer = true }) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)

                    // File name
                    VStack {
                        Spacer()
                        HStack {
                            Text(url.lastPathComponent)
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(4)
                            Spacer()
                        }
                        .padding(6)
                    }
                }
                .frame(width: 280, height: 180)
                .cornerRadius(8)
            }
        }
        .onAppear { generateThumbnail() }
    }

    private func generateThumbnail() {
        Task.detached {
            let asset = AVAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 560, height: 360)
            if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                await MainActor.run {
                    thumbnail = nsImage
                }
            }
        }
    }
}

// MARK: - Native Video Player (NSViewRepresentable)

struct NativeVideoPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .inline
        let player = AVPlayer(url: url)
        playerView.player = player
        player.play()
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
    }
}

// MARK: - Inline Audio Player

struct InlineAudioPlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var timeObserver: Any?

    var body: some View {
        HStack(spacing: 10) {
            // Play/Pause button
            Button(action: { togglePlayback() }) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                // File name
                Text(url.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(NSColor.separatorColor))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor)
                            .frame(width: duration > 0 ? geo.size.width * (currentTime / duration) : 0, height: 4)
                    }
                }
                .frame(height: 4)

                // Time labels
                HStack {
                    Text(formatTime(currentTime))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatTime(duration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .frame(width: 260)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .onDisappear { cleanup() }
    }

    private func ensurePlayer() {
        guard player == nil else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let avPlayer = AVPlayer(url: url)
        self.player = avPlayer

        // Get duration
        Task {
            if let asset = avPlayer.currentItem?.asset {
                let dur = try? await asset.load(.duration)
                if let dur = dur {
                    await MainActor.run {
                        duration = CMTimeGetSeconds(dur)
                    }
                }
            }
        }

        // Periodic time observer
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = CMTimeGetSeconds(time)
        }

        // Reset when playback ends
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { _ in
            isPlaying = false
            avPlayer.seek(to: .zero)
            currentTime = 0
        }
    }

    private func togglePlayback() {
        ensurePlayer()
        guard let player = player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func cleanup() {
        player?.pause()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Attachment Preview (in input bar)

struct AttachmentPreview: View {
    let url: URL
    let onRemove: () -> Void

    private var isImage: Bool {
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "tiff", "svg"].contains(ext)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isImage, let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipped()
                    .cornerRadius(8)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: fileIconName)
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                    Text(url.lastPathComponent)
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: 56)
                }
                .frame(width: 60, height: 60)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
    }

    private var fileIconName: String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "ppt", "pptx": return "rectangle.fill.on.rectangle.fill"
        case "mp3", "wav", "m4a", "aac", "flac": return "music.note"
        case "mp4", "mov", "avi", "mkv", "webm": return "film.fill"
        default: return "doc.fill"
        }
    }
}

// MARK: - Success Toast

struct SuccessToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 20))

            Text(message)
                .font(.body)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        )
    }
}

// MARK: - Diagnostics Sheet

struct DiagnosticsSheet: View {
    let report: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Diagnostics Report")
                    .font(.headline)

                Spacer()

                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            // Report content
            ScrollView {
                Text(report)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - Brand Text

struct BrandTextView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            Text("GetClaw")
                .foregroundColor(colorScheme == .dark ? .white : .black)
            Text("Hub")
                .foregroundColor(.red)
        }
        .font(.title2)
        .fontWeight(.bold)
    }
}

// MARK: - Selectable Markdown View (WKWebView-based)

import WebKit

/// Renders markdown as selectable rich text via WKWebView.
/// Supports free multi-line text selection and proper markdown rendering.
struct SelectableMarkdownView: NSViewRepresentable {
    let content: String
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        context.coordinator.lastContent = ""
        loadHTML(in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.webView = webView
        loadHTML(in: webView, coordinator: context.coordinator)
    }

    private func loadHTML(in webView: WKWebView, coordinator: Coordinator) {
        let html = Self.buildHTML(content, isDark: colorScheme == .dark)
        guard html != coordinator.lastContent else { return }
        coordinator.lastContent = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - Coordinator for height tracking

    class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var lastContent: String = ""
        private var heightConstraint: NSLayoutConstraint?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateHeight(webView)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        private func updateHeight(_ webView: WKWebView) {
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
                guard let height = result as? CGFloat, height > 0 else { return }
                DispatchQueue.main.async {
                    if let constraint = self?.heightConstraint {
                        constraint.constant = height
                    } else {
                        webView.translatesAutoresizingMaskIntoConstraints = false
                        let c = webView.heightAnchor.constraint(equalToConstant: height)
                        c.priority = .defaultHigh
                        c.isActive = true
                        self?.heightConstraint = c
                    }
                    webView.invalidateIntrinsicContentSize()
                }
            }
        }
    }

    // MARK: - Build HTML

    static func buildHTML(_ markdown: String, isDark: Bool) -> String {
        let textColor = isDark ? "#e0e0e0" : "#1d1d1f"
        let codeBg = isDark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.05)"
        let borderColor = isDark ? "rgba(255,255,255,0.15)" : "rgba(0,0,0,0.15)"
        let tableBg = isDark ? "rgba(255,255,255,0.04)" : "rgba(0,0,0,0.02)"
        let blockquoteBorder = isDark ? "#555" : "#ccc"
        let blockquoteColor = isDark ? "#aaa" : "#666"
        let linkColor = isDark ? "#6cb6ff" : "#0366d6"

        let body = convertMarkdown(markdown)

        return """
        <html><head><meta charset='utf-8'>
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            font-size: 13px; color: \(textColor); line-height: 1.6;
            -webkit-user-select: text; cursor: text;
            word-wrap: break-word; overflow-wrap: break-word;
        }
        h1 { font-size: 20px; font-weight: 700; margin: 12px 0 6px; }
        h2 { font-size: 17px; font-weight: 700; margin: 10px 0 5px; }
        h3 { font-size: 15px; font-weight: 600; margin: 8px 0 4px; }
        h4, h5, h6 { font-size: 14px; font-weight: 600; margin: 6px 0 3px; }
        p { margin: 6px 0; }
        code {
            font-family: Menlo, Monaco, monospace; font-size: 12px;
            background: \(codeBg); padding: 1px 4px; border-radius: 3px;
        }
        pre {
            background: \(codeBg); padding: 10px; border-radius: 6px;
            overflow-x: auto; margin: 8px 0;
        }
        pre code { background: none; padding: 0; }
        table { border-collapse: collapse; margin: 8px 0; }
        th, td { border: 1px solid \(borderColor); padding: 5px 10px; text-align: left; }
        th { font-weight: 600; }
        tr:nth-child(even) { background: \(tableBg); }
        blockquote {
            border-left: 3px solid \(blockquoteBorder);
            margin: 6px 0; padding: 2px 10px; color: \(blockquoteColor);
        }
        a { color: \(linkColor); text-decoration: none; }
        ul, ol { padding-left: 20px; margin: 4px 0; }
        li { margin: 2px 0; }
        hr { border: none; border-top: 1px solid \(borderColor); margin: 10px 0; }
        img { max-width: 100%; }
        </style></head><body>\(body)</body></html>
        """
    }

    // MARK: - Markdown → HTML conversion

    private static func convertMarkdown(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var html = ""
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Code block
            if trimmed.hasPrefix("```") {
                var codeContent = ""
                i += 1
                while i < lines.count {
                    let codeLine = lines[i]
                    if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    if !codeContent.isEmpty { codeContent += "\n" }
                    codeContent += codeLine
                    i += 1
                }
                html += "<pre><code>\(escapeHTML(codeContent))</code></pre>"
                continue
            }

            // Empty line
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Table: starts with | and next line is separator
            if trimmed.hasPrefix("|") && trimmed.contains("|") {
                var tableLines: [String] = []
                while i < lines.count {
                    let tl = lines[i].trimmingCharacters(in: .whitespaces)
                    if tl.hasPrefix("|") && tl.contains("|") {
                        tableLines.append(tl)
                        i += 1
                    } else {
                        break
                    }
                }
                html += renderTable(tableLines)
                continue
            }

            // Heading: # to ######
            if trimmed.hasPrefix("#") {
                if let spaceIdx = trimmed.firstIndex(of: " ") {
                    let hashPart = trimmed[trimmed.startIndex..<spaceIdx]
                    if hashPart.allSatisfy({ $0 == "#" }) && hashPart.count <= 6 {
                        let level = hashPart.count
                        let headingText = String(trimmed[trimmed.index(after: spaceIdx)...])
                        html += "<h\(level)>\(processInline(headingText))</h\(level)>"
                        i += 1
                        continue
                    }
                }
            }

            // Horizontal rule
            if isHorizontalRule(trimmed) {
                html += "<hr>"
                i += 1
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let ql = lines[i].trimmingCharacters(in: .whitespaces)
                    if ql.hasPrefix("> ") {
                        quoteLines.append(String(ql.dropFirst(2)))
                        i += 1
                    } else if ql == ">" {
                        quoteLines.append("")
                        i += 1
                    } else {
                        break
                    }
                }
                html += "<blockquote>\(quoteLines.map { processInline($0) }.joined(separator: "<br>"))</blockquote>"
                continue
            }

            // Unordered list
            if isUnorderedListItem(trimmed) {
                html += "<ul>"
                while i < lines.count {
                    let li = lines[i].trimmingCharacters(in: .whitespaces)
                    if isUnorderedListItem(li) {
                        html += "<li>\(processInline(String(li.dropFirst(2))))</li>"
                        i += 1
                    } else {
                        break
                    }
                }
                html += "</ul>"
                continue
            }

            // Ordered list
            if isOrderedListItem(trimmed) {
                html += "<ol>"
                while i < lines.count {
                    let li = lines[i].trimmingCharacters(in: .whitespaces)
                    if let content = orderedListContent(li) {
                        html += "<li>\(processInline(content))</li>"
                        i += 1
                    } else {
                        break
                    }
                }
                html += "</ol>"
                continue
            }

            // Regular paragraph — collect consecutive non-special lines
            var paraLines: [String] = []
            while i < lines.count {
                let pl = lines[i].trimmingCharacters(in: .whitespaces)
                if pl.isEmpty || pl.hasPrefix("```") || pl.hasPrefix("#") || pl.hasPrefix("|")
                    || pl.hasPrefix(">") || isUnorderedListItem(pl) || isOrderedListItem(pl)
                    || isHorizontalRule(pl) {
                    break
                }
                paraLines.append(processInline(pl))
                i += 1
            }
            if !paraLines.isEmpty {
                html += "<p>\(paraLines.joined(separator: "<br>"))</p>"
            }
        }

        return html
    }

    // MARK: - Helpers

    private static func isHorizontalRule(_ s: String) -> Bool {
        let dashes = s.filter { $0 == "-" }.count
        let stars = s.filter { $0 == "*" }.count
        let underscores = s.filter { $0 == "_" }.count
        if dashes >= 3 && s.allSatisfy({ $0 == "-" || $0 == " " }) { return true }
        if stars >= 3 && s.allSatisfy({ $0 == "*" || $0 == " " }) && !s.contains("**") { return true }
        if underscores >= 3 && s.allSatisfy({ $0 == "_" || $0 == " " }) { return true }
        return false
    }

    private static func isUnorderedListItem(_ s: String) -> Bool {
        s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("+ ")
    }

    private static func isOrderedListItem(_ s: String) -> Bool {
        orderedListContent(s) != nil
    }

    private static func orderedListContent(_ s: String) -> String? {
        guard let dotIdx = s.firstIndex(of: ".") else { return nil }
        let prefix = s[s.startIndex..<dotIdx]
        guard !prefix.isEmpty && prefix.allSatisfy({ $0.isNumber }) else { return nil }
        let afterDot = s[s.index(after: dotIdx)...]
        guard afterDot.hasPrefix(" ") else { return nil }
        return String(afterDot.dropFirst())
    }

    private static func renderTable(_ lines: [String]) -> String {
        guard !lines.isEmpty else { return "" }
        var html = "<table>"
        var headerDone = false
        for line in lines {
            let inner = line.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            let cells = inner.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            // Check if separator row
            let isSeparator = cells.allSatisfy { cell in
                let stripped = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":- "))
                return stripped.isEmpty && !cell.isEmpty
            }
            if isSeparator {
                headerDone = true
                continue
            }
            let tag = !headerDone ? "th" : "td"
            html += "<tr>" + cells.map { "<\(tag)>\(processInline($0))</\(tag)>" }.joined() + "</tr>"
        }
        html += "</table>"
        return html
    }

    // MARK: - Inline markdown processing

    private static func processInline(_ text: String) -> String {
        var result = escapeHTML(text)
        // Images ![alt](url)
        result = result.replacingOccurrences(
            of: "!\\[([^\\]]*)\\]\\(([^)]+)\\)",
            with: "<img src=\"$2\" alt=\"$1\">",
            options: .regularExpression
        )
        // Links [text](url)
        result = result.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\(([^)]+)\\)",
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )
        // Bold **text** or __text__
        result = result.replacingOccurrences(
            of: "\\*\\*(.+?)\\*\\*",
            with: "<strong>$1</strong>",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "__(.+?)__",
            with: "<strong>$1</strong>",
            options: .regularExpression
        )
        // Italic *text* or _text_
        result = result.replacingOccurrences(
            of: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)",
            with: "<em>$1</em>",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "(?<![\\w])_(.+?)_(?![\\w])",
            with: "<em>$1</em>",
            options: .regularExpression
        )
        // Strikethrough ~~text~~
        result = result.replacingOccurrences(
            of: "~~(.+?)~~",
            with: "<s>$1</s>",
            options: .regularExpression
        )
        // Inline code `text`
        result = result.replacingOccurrences(
            of: "`([^`]+)`",
            with: "<code>$1</code>",
            options: .regularExpression
        )
        return result
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

#Preview {
    DashboardView(
        viewModel: DashboardViewModel(
            openclawService: OpenClawService(
                commandExecutor: CommandExecutor(
                    permissionManager: PermissionManager()
                )
            ),
            settings: AppSettingsManager(),
            systemEnvironment: SystemEnvironment(
                commandExecutor: CommandExecutor(
                    permissionManager: PermissionManager()
                )
            ),
            commandExecutor: CommandExecutor(
                permissionManager: PermissionManager()
            )
        )
    )
    .frame(width: 960, height: 680)
}
