import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
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
        switch viewModel.selectedTab {
        case .chat:
            ChatView(viewModel: viewModel)
        case .status:
            StatusTabView(viewModel: viewModel)
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
        case .logs:
            LogsTabView(viewModel: viewModel)
        }
    }
}

// MARK: - Chat View

struct ChatView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    if viewModel.chatMessages.isEmpty {
                        ChatWelcomeView()
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.chatMessages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }

                            if viewModel.isSendingMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "brain.head.profile")
                                        .font(.system(size: 24))
                                        .foregroundColor(.orange)
                                        .frame(width: 32, height: 32)

                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                        Text("Thinking...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(10)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(12)

                                    Spacer()
                                }
                                .id("loading")
                            }
                        }
                        .padding(20)
                    }
                }
                .onChange(of: viewModel.chatMessages.count) { _ in
                    withAnimation {
                        if viewModel.isSendingMessage {
                            proxy.scrollTo("loading", anchor: .bottom)
                        } else if let last = viewModel.chatMessages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input bar
            HStack(spacing: 8) {
                Button(action: { viewModel.clearChat() }) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("New Conversation")

                TextField("Describe a task or ask any question", text: $inputText)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .onSubmit { sendMessage() }
                    .disabled(viewModel.isSendingMessage)

                Button(action: { sendMessage() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(canSend ? .accentColor : .gray)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(12)
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !viewModel.isSendingMessage
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        Task { await viewModel.sendChatMessage(text) }
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

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant {
                // AI avatar
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 24))
                    .foregroundColor(.orange)
                    .frame(width: 32, height: 32)
            }

            if message.role == .user { Spacer(minLength: 60) }

            Text(message.content)
                .padding(10)
                .background(backgroundColor)
                .foregroundColor(message.role == .user ? .white : .primary)
                .cornerRadius(12)
                .textSelection(.enabled)

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
