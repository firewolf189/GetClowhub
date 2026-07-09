import SwiftUI

@MainActor
private func localizedString(_ key: String) -> String {
    I18n.t(key, fallback: key)
}

@MainActor
private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: I18n.t(key, fallback: key), arguments: arguments)
}

private func formatTokenCount(_ value: Int) -> String {
    if value >= 1_000_000 {
        return "\(value / 1_000_000)M"
    }
    if value >= 1_000 {
        return "\(value / 1_000)K"
    }
    return "\(value)"
}

enum SettingsPageSection: String, CaseIterable, Identifiable {
    case profile
    case preferences
    case persona
    case status
    case gateway
    case provider
    case budget
    case models
    case channels
    case logs

    var id: Self { self }

    private var titleKey: String {
        switch self {
        case .profile: return "Profile"
        case .preferences: return "Preferences"
        case .persona: return "Persona"
        case .status: return "Status"
        case .gateway: return "Gateway"
        case .provider: return "Providers"
        case .budget: return "Budget"
        case .models: return "Models"
        case .channels: return "Channels"
        case .logs: return "Logs"
        }
    }

    @MainActor
    func localizedTitle() -> String {
        localizedString(titleKey)
    }

    var systemImage: String {
        switch self {
        case .profile: return "person.crop.circle"
        case .preferences: return "paintbrush.pointed"
        case .persona: return "person.text.rectangle"
        case .status: return "chart.bar.fill"
        case .gateway: return "network"
        case .provider: return "cpu"
        case .budget: return "dollarsign.gauge.chart.lefthalf.righthalf"
        case .models: return "cube.fill"
        case .channels: return "bubble.left.and.bubble.right.fill"
        case .logs: return "doc.text.magnifyingglass"
        }
    }
}

struct ConfigTabView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var selectedSection: SettingsPageSection
    @EnvironmentObject var languageManager: LanguageManager
    @AppStorage("appAppearance") private var appAppearance: String = "system"
    @AppStorage("appAccent") private var appAccent: String = "green"
    #if REQUIRE_LOGIN
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var membershipManager: MembershipManager
    #endif

    init(
        viewModel: DashboardViewModel,
        selectedSection: Binding<SettingsPageSection> = .constant(.profile)
    ) {
        self.viewModel = viewModel
        self._selectedSection = selectedSection
    }

    var body: some View {
        selectedSettingsContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            viewModel.syncEditedFieldsFromSettings()
        }
    }

    @ViewBuilder
    private var selectedSettingsContent: some View {
        switch selectedSection {
        case .profile:
            settingsScroll {
                #if REQUIRE_LOGIN
                ProfileSettingsCard()
                    .environmentObject(authManager)
                    .environmentObject(membershipManager)
                #else
                SettingsCard(title: localizedString("Profile"), systemImage: "person.crop.circle") {
                    Text(localizedString("Profile is available in signed builds."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                #endif
            }
        case .preferences:
            settingsScroll {
                PreferencesSettingsCard(appAppearance: $appAppearance, appAccent: $appAccent)
                    .environmentObject(languageManager)
            }
        case .persona:
            settingsScroll {
                AgentPersonaSettingsList(viewModel: viewModel)
            }
        case .status:
            StatusTabView(viewModel: viewModel)
        case .gateway:
            settingsScroll {
                GatewayConfigSection(viewModel: viewModel)
                SaveButtonsSection(viewModel: viewModel)
                OpenConfigFileSection(viewModel: viewModel)
            }
        case .provider:
            settingsScroll {
                ProviderSettingsIntro()
                #if REQUIRE_LOGIN
                GetClawHubServiceSection(viewModel: viewModel)
                    .environmentObject(authManager)
                    .environmentObject(membershipManager)
                CustomProviderListSection(viewModel: viewModel)
                #else
                CustomProviderListSection(viewModel: viewModel)
                #endif
            }
        case .budget:
            BudgetTabView(viewModel: viewModel)
        case .models:
            ModelsTabView(viewModel: viewModel)
        case .channels:
            ChannelsTabView(viewModel: viewModel)
        case .logs:
            LogsTabView(viewModel: viewModel)
        }
    }

    private func settingsScroll<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        SmoothScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(selectedSection.localizedTitle())
                    .font(.system(size: 24, weight: .semibold))

                content()
            }
            .frame(maxWidth: 880, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.headline)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

#if REQUIRE_LOGIN
private struct ProfileSettingsCard: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var membershipManager: MembershipManager

    var body: some View {
        SettingsCard(title: localizedString("Profile"), systemImage: "person.crop.circle") {
            switch authManager.state {
            case .loggedIn(let nickname):
                HStack {
                    Text(nickname)
                        .font(.system(size: 14, weight: .medium))
                    if let membership = membershipManager.membership {
                        Text("[\(membership.level.displayName)]")
                            .font(.caption.bold())
                            .foregroundColor(badgeColor(membership.level))
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    Button(localizedString("Manage")) {
                        openMemberAccount()
                    }
                    .buttonStyle(.bordered)
                    Button(localizedString("Log Out")) {
                        authManager.logout()
                    }
                    .buttonStyle(.bordered)
                }
            default:
                Text(localizedString("Not Logged In"))
                    .foregroundColor(.secondary)
                Button(localizedString("Log In")) {
                    authManager.login()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func badgeColor(_ level: MembershipLevel) -> Color {
        switch level {
        case .free: return .gray
        case .pro: return .blue
        case .max: return .purple
        }
    }

    private func openMemberAccount() {
        var urlString = "\(AuthConfig.baseURL)/member/account/"
        var params: [String] = []
        if let token = authManager.accessToken {
            params.append("token=\(token)")
        }
        if let uid = authManager.userId {
            params.append("user_id=\(uid)")
        }
        if !params.isEmpty {
            urlString += "?" + params.joined(separator: "&")
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
#endif

private struct PreferencesSettingsCard: View {
    @EnvironmentObject var languageManager: LanguageManager
    @Environment(\.colorScheme) private var colorScheme
    @Binding var appAppearance: String
    @Binding var appAccent: String

    private var selectedAppearance: AppAppearanceMode {
        AppAppearanceMode.storedValue(appAppearance)
    }

    private var selectedAccent: AppAccentPalette {
        AppAccentPalette.storedValue(appAccent)
    }

    var body: some View {
        SettingsCard(title: localizedString("Preferences"), systemImage: "paintbrush.pointed") {
            VStack(alignment: .leading, spacing: 18) {
                preferenceRow(title: localizedString("Language"), subtitle: localizedString("Use your preferred app language.")) {
                    Picker(localizedString("Language"), selection: $languageManager.selectedLanguage) {
                        ForEach(languageManager.supportedLanguages) { lang in
                            Text(lang.name).tag(lang.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                Divider()

                VStack(alignment: .leading, spacing: 14) {
                    preferenceRow(title: localizedString("Appearance"), subtitle: localizedString("Choose a mode and preview how the workspace will feel.")) {
                        Picker(localizedString("Appearance"), selection: $appAppearance) {
                            ForEach(AppAppearanceMode.allCases) { mode in
                                Label(localizedString(mode.title), systemImage: mode.systemImage)
                                    .tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 330)
                    }

                    AppearancePreview(
                        mode: selectedAppearance,
                        accent: selectedAccent,
                        systemScheme: colorScheme
                    )

                    preferenceRow(title: localizedString("Accent"), subtitle: localizedString("Applies to controls and selected states.")) {
                        HStack(spacing: 8) {
                            ForEach(AppAccentPalette.allCases) { accent in
                                Button {
                                    appAccent = accent.rawValue
                                } label: {
                                    AccentSwatch(accent: accent, isSelected: selectedAccent == accent)
                                }
                                .buttonStyle(.plain)
                                .help(localizedString(accent.title))
                            }
                        }
                    }
                }
            }
        }
    }

    private func preferenceRow<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 16)
            content()
        }
    }
}

private struct AccentSwatch: View {
    let accent: AppAccentPalette
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(accent.color)
                .frame(width: 24, height: 24)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 30, height: 30)
        .background(
            Circle()
                .stroke(isSelected ? accent.color.opacity(0.90) : Color.primary.opacity(0.10), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Circle())
    }
}

private struct AppearancePreview: View {
    let mode: AppAppearanceMode
    let accent: AppAccentPalette
    let systemScheme: ColorScheme

    private var isDark: Bool {
        mode.resolvesDark(using: systemScheme)
    }

    private var surfaceColor: Color {
        isDark ? Color(red: 0.13, green: 0.14, blue: 0.14) : Color(red: 0.96, green: 0.95, blue: 0.92)
    }

    private var sidebarColor: Color {
        isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.62)
    }

    private var panelColor: Color {
        isDark ? Color.white.opacity(0.09) : Color.white.opacity(0.86)
    }

    private var codeColor: Color {
        isDark ? Color.black.opacity(0.22) : Color.black.opacity(0.055)
    }

    private var textColor: Color {
        isDark ? Color.white.opacity(0.92) : Color.black.opacity(0.82)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(accent.color)
                        .frame(width: 8, height: 8)
                        Text("GetClawHub")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(textColor)
                }

                previewSidebarRow(icon: AppSystemSymbol.skills, title: localizedString("Skills"), active: true)
                previewSidebarRow(icon: "powerplug.portrait", title: localizedString("Plugins"), active: false)
                previewSidebarRow(icon: "gearshape", title: localizedString("Settings"), active: false)

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 154)
            .background(sidebarColor)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizedString(mode.title))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(textColor)
                        Text(localizedFormat("Accent %@", localizedString(accent.title)))
                            .font(.caption)
                            .foregroundColor(textColor.opacity(0.58))
                    }
                    Spacer()
                    Text("Aa")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accent.color)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(accent.color.opacity(isDark ? 0.18 : 0.12), in: Capsule())
                }

                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(textColor.opacity(0.58))
                        .frame(width: 124, height: 6)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(textColor.opacity(0.26))
                        .frame(width: 190, height: 6)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(textColor.opacity(0.18))
                        .frame(width: 152, height: 6)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(panelColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(index == 0 ? accent.color.opacity(0.82) : codeColor)
                            .frame(height: 18)
                    }
                }
            }
            .padding(12)
        }
        .frame(height: 150)
        .background(surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(isDark ? 0.12 : 0.08), lineWidth: 1)
        )
    }

    private func previewSidebarRow(icon: String, title: String, active: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 12)
            Text(title)
                .font(.system(size: 11, weight: .medium))
            Spacer()
        }
        .foregroundColor(active ? textColor : textColor.opacity(0.62))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(active ? accent.color.opacity(isDark ? 0.28 : 0.16) : Color.clear)
        )
    }
}

private struct AgentPersonaSettingsList: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var expandedAgentId: String?
    @State private var areMoreFilesExpanded = false

    private let optionalPersonaFiles: [PersonaFileDescriptor] = [
        PersonaFileDescriptor(fileName: "USER.md", icon: "person.fill"),
        PersonaFileDescriptor(fileName: "AGENTS.md", icon: "person.3.fill"),
        PersonaFileDescriptor(fileName: "BOOTSTRAP.md", icon: "power"),
        PersonaFileDescriptor(fileName: "HEARTBEAT.md", icon: "heart.text.clipboard"),
        PersonaFileDescriptor(fileName: "TOOLS.md", icon: "wrench.and.screwdriver")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(viewModel.availableAgents) { agent in
                agentRow(agent)
            }
        }
        .onAppear {
            viewModel.loadAvailableAgents()
        }
    }

    private func agentRow(_ agent: AgentOption) -> some View {
        let isExpanded = expandedAgentId == agent.id
        let unsavedCount = unsavedFileCount(for: agent)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleAgent(agent)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 14)

                    Image(systemName: "person.text.rectangle")
                        .foregroundColor(.accentColor)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(agent.name)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)

                            Text(agent.id)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        HStack(spacing: 8) {
                            if !agent.model.isEmpty {
                                Label(agent.model, systemImage: "cpu")
                                    .lineLimit(1)
                            }

                            Label(compactWorkspacePath(for: agent), systemImage: "folder")
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        if !agent.description.isEmpty {
                            Text(agent.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 8) {
                        Text(personaStatusText(for: agent))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        if unsavedCount > 0 {
                            Text(localizedFormat("%lld unsaved", unsavedCount))
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.14))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 14)

                agentPersonaEditors
                    .padding(14)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(isExpanded ? 0.88 : 0.58))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isExpanded ? Color.accentColor.opacity(0.42) : Color.gray.opacity(0.18), lineWidth: 1)
        )
    }

    private var agentPersonaEditors: some View {
        VStack(alignment: .leading, spacing: 12) {
            MarkdownFileEditor(
                title: "IDENTITY.md",
                icon: "person.crop.circle",
                content: viewModel.settingsBinding(for: .identity),
                isDirty: viewModel.selectedAgentDetail?.identityDirty ?? false,
                onSave: {
                    viewModel.saveAgentPersonaFile(file: .identity)
                },
                initiallyExpanded: false
            )

            MarkdownFileEditor(
                title: "SOUL.md",
                icon: "heart.fill",
                content: viewModel.settingsBinding(for: .soul),
                isDirty: viewModel.selectedAgentDetail?.soulDirty ?? false,
                onSave: {
                    viewModel.saveAgentPersonaFile(file: .soul)
                },
                initiallyExpanded: false
            )

            MarkdownFileEditor(
                title: "MEMORY.md",
                icon: "brain.head.profile",
                content: viewModel.settingsBinding(for: .memory),
                isDirty: viewModel.selectedAgentDetail?.memoryDirty ?? false,
                onSave: {
                    viewModel.saveAgentPersonaFile(file: .memory)
                },
                initiallyExpanded: false
            )

            let visibleOptionalFiles = optionalPersonaFiles.filter { file in
                let fileName = file.fileName
                return viewModel.hasPersonaFile(fileName)
            }

            if !visibleOptionalFiles.isEmpty {
                DisclosureGroup(isExpanded: $areMoreFilesExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(visibleOptionalFiles) { file in
                            let fileName = file.fileName
                            MarkdownFileEditor(
                                title: fileName,
                                icon: file.icon,
                                content: viewModel.settingsBindingByName(fileName),
                                isDirty: viewModel.isFileDirtyByName(fileName),
                                onSave: {
                                    viewModel.savePersonaFileByName(fileName)
                                },
                                initiallyExpanded: false
                            )
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.gearshape")
                            .foregroundColor(.secondary)
                        Text(localizedString("More files"))
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(visibleOptionalFiles.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
                .padding(12)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func toggleAgent(_ agent: AgentOption) {
        if expandedAgentId == agent.id {
            expandedAgentId = nil
            return
        }

        expandedAgentId = agent.id
        areMoreFilesExpanded = false
        viewModel.selectedAgentId = agent.id
        viewModel.loadSelectedAgentDetail()
    }

    private func personaStatusText(for agent: AgentOption) -> String {
        let workspace = DashboardViewModel.resolveAgentWorkspace(agent.id)
        let files = ["IDENTITY.md", "SOUL.md", "MEMORY.md"] + optionalPersonaFiles.map(\.fileName)
        let count = files.filter { fileName in
            FileManager.default.fileExists(atPath: (workspace as NSString).appendingPathComponent(fileName))
        }.count
        return localizedFormat("%lld files", count)
    }

    private func unsavedFileCount(for agent: AgentOption) -> Int {
        guard let detail = viewModel.selectedAgentDetail, detail.id == agent.id else {
            return 0
        }

        return [
            detail.identityDirty,
            detail.soulDirty,
            detail.memoryDirty,
            detail.userDirty,
            detail.agentsDirty,
            detail.bootstrapDirty,
            detail.heartbeatDirty,
            detail.toolsDirty
        ].filter { $0 }.count
    }

    private func compactWorkspacePath(for agent: AgentOption) -> String {
        let workspace = DashboardViewModel.resolveAgentWorkspace(agent.id)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return workspace.replacingOccurrences(of: home, with: "~")
    }
}

private struct PersonaFileDescriptor: Identifiable {
    let fileName: String
    let icon: String

    var id: String {
        fileName
    }
}

// MARK: - Gateway Settings Group

struct GatewaySettingsGroup: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localizedString("Gateway"))
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 16) {
                GatewayConfigSection(viewModel: viewModel, showsTitle: false)

                #if REQUIRE_LOGIN
                HStack(alignment: .top, spacing: 16) {
                    GetClawHubServiceSection(viewModel: viewModel)
                    ModelConfigSection(viewModel: viewModel)
                }
                #else
                ModelConfigSection(viewModel: viewModel)
                #endif
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.gray.opacity(0.22), lineWidth: 1)
            )
        }
    }
}

// MARK: - Gateway Configuration (Red Border)

struct GatewayConfigSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    var showsTitle: Bool = true
    @State private var showAuthToken = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsTitle {
                Text(localizedString("Gateway"))
                    .font(.headline)
            }

            // Port
            HStack {
                Text(localizedString("Port"))
                    .frame(width: 120, alignment: .leading)

                TextField("18789", text: $viewModel.editedPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)

                Text(localizedString("Gateway listening port"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Auth Token
            HStack {
                Text(localizedString("Auth Token"))
                    .frame(width: 120, alignment: .leading)

                ZStack {
                    if showAuthToken {
                        TextField(localizedString("Enter auth token"), text: $viewModel.editedAuthToken)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField(localizedString("Enter auth token"), text: $viewModel.editedAuthToken)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .frame(maxWidth: 300)

                Button(action: { showAuthToken.toggle() }) {
                    Image(systemName: showAuthToken ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless)
                .help(showAuthToken ? localizedString("Hide") : localizedString("Show"))

                Text(localizedString("Authentication token for gateway access"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.4), lineWidth: 1)
        )
    }
}

private struct ProviderSettingsIntro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localizedString("Choose the model provider used by the local gateway. Custom providers stay saved, but only the selected provider is edited here."))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ProviderStatusBadgeTone {
    case selected
    case configured
    case warning
    case neutral

    var foreground: Color {
        switch self {
        case .selected: return .blue
        case .configured: return .secondary
        case .warning: return .orange
        case .neutral: return .secondary
        }
    }

    var background: Color {
        switch self {
        case .selected: return Color.blue.opacity(0.12)
        case .configured: return Color.primary.opacity(0.06)
        case .warning: return Color.orange.opacity(0.12)
        case .neutral: return Color.primary.opacity(0.05)
        }
    }
}

private struct ProviderStatusBadge: View {
    let text: String
    let tone: ProviderStatusBadgeTone

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(tone.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tone.background)
            .clipShape(Capsule())
    }
}

#if REQUIRE_LOGIN
// MARK: - GetClawHub Official Service (Blue Border + Radio)

struct GetClawHubServiceSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var membershipManager: MembershipManager
    @State private var showApiKey = false
    @State private var isExpanded = false
    @State private var areModelsExpanded = false

    private var isSelected: Bool {
        viewModel.editedActiveServiceSource == "getclawhub"
    }

    private var presetBaseUrl: String {
        viewModel.presetManager.findProvider(byKey: "getclawhub")?.baseUrl ?? "https://ai.getclawhub.com/v1"
    }

    private var officialPresetModels: [PresetModel] {
        viewModel.presetManager.findProvider(byKey: "getclawhub")?.models ?? []
    }

    private var officialAvailableModels: [PresetModel] {
        membershipManager.filterAllowedGetClawHubModels(officialPresetModels)
    }

    private var officialModelSummary: String {
        let names = officialAvailableModels.prefix(3).map { $0.name.isEmpty ? $0.id : $0.name }
        guard !names.isEmpty else {
            return localizedString("No models available")
        }
        let suffix = officialAvailableModels.count > names.count ? "..." : ""
        return names.joined(separator: ", ") + suffix
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            providerHeader

            if isExpanded {
                if case .loggedIn = authManager.state {
                    if let membership = membershipManager.membership {
                        loggedInContent(membership)
                    } else {
                        syncingOrErrorView
                    }
                } else {
                    notLoggedInView
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(isSelected ? 0.6 : 0.3), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { toggleOfficialProviderExpansion() }
        .onAppear {
            // Initialize editable key from synced data (use latest key)
            if let activeKey = membershipManager.apiKeys.last(where: { $0.isActive }) {
                viewModel.editedGetClawHubApiKey = activeKey.fullKey
            }
        }
        .onChange(of: membershipManager.apiKeys) { newKeys in
            if let activeKey = newKeys.last(where: { $0.isActive }) {
                viewModel.editedGetClawHubApiKey = activeKey.fullKey
            }
        }
    }

    private var providerHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "key")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isSelected ? .blue : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(localizedString("GetClawHub Official"))
                        .font(.system(size: 14, weight: .semibold))
                    ProviderStatusBadge(text: localizedString("Recommended"), tone: .selected)
                }

                Text(localizedString("Uses your GetClawHub membership, synced API key, and official model access."))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(action: { toggleOfficialProviderExpansion() }) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? localizedString("Collapse") : localizedString("Expand"))
        }
    }

    private func toggleOfficialProviderExpansion() {
        let shouldCollapse = isSelected && isExpanded
        let shouldPersistSelection = !isSelected
        viewModel.editedActiveServiceSource = "getclawhub"
        withAnimation(.easeInOut(duration: 0.18)) {
            isExpanded = !shouldCollapse
        }
        if shouldPersistSelection && !viewModel.editedGetClawHubApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task {
                _ = await viewModel.persistProviderConfiguration()
            }
        }
    }

    // MARK: - Logged In Content

    private func loggedInContent(_ membership: MembershipInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Membership
            HStack {
                Text(localizedString("Membership"))
                    .frame(width: 120, alignment: .leading)

                Text(membership.level.displayName)
                    .fontWeight(.semibold)
                    .foregroundColor(badgeColor(membership.level))

                if let expiresAt = membership.expiresAt {
                    Text(localizedFormat("(expires %@)", expiresAt.formatted(.dateTime.year().month().day())))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(localizedString("Manage")) {
                    var urlString = "\(AuthConfig.baseURL)/member/account/"
                    var params: [String] = []
                    if let token = authManager.accessToken {
                        params.append("token=\(token)")
                    }
                    if let uid = authManager.userId {
                        params.append("user_id=\(uid)")
                    }
                    if !params.isEmpty {
                        urlString += "?" + params.joined(separator: "&")
                    }
                    if let url = URL(string: urlString) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            availableModelsView

            // Base URL (readonly) — above API Key
            HStack {
                Text(localizedString("API Base URL"))
                    .frame(width: 120, alignment: .leading)

                TextField("", text: .constant(presetBaseUrl))
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
                    .frame(maxWidth: .infinity)
            }

            // API Key (editable)
            if let _ = membershipManager.apiKeys.last(where: { $0.isActive }) {
                HStack {
                    Text(localizedString("API Key"))
                        .frame(width: 120, alignment: .leading)

                    ZStack {
                        if showApiKey {
                            TextField(localizedString("Enter API Key"), text: $viewModel.editedGetClawHubApiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField(localizedString("Enter API Key"), text: $viewModel.editedGetClawHubApiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Button(action: { showApiKey.toggle() }) {
                        Image(systemName: showApiKey ? "eye" : "eye.slash")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        Task { await membershipManager.syncProfile() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(localizedString("Sync"))
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(membershipManager.syncState == .syncing)
                }
            } else {
                // No key guidance
                noKeyGuidanceView(membership)
            }

            HStack {
                Spacer()
                Button {
                    Task {
                        await viewModel.persistProviderConfiguration(showSuccessMessage: true)
                    }
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isPersistingProviderConfiguration {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark")
                        }
                        Text(localizedString("Save"))
                    }
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(
                    viewModel.isPersistingProviderConfiguration ||
                    viewModel.editedGetClawHubApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

        }
    }

    private var availableModelsView: some View {
        HStack(alignment: .top) {
            Text(localizedString("Available Models"))
                .frame(width: 120, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                if officialAvailableModels.isEmpty {
                    Text(localizedString("No matching models found in the official provider preset."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            areModelsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(localizedFormat("%lld models available", officialAvailableModels.count))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text(officialModelSummary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            Image(systemName: areModelsExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    if areModelsExpanded {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 8)], alignment: .leading, spacing: 8) {
                                ForEach(officialAvailableModels) { model in
                                    officialModelPill(model)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func officialModelPill(_ model: PresetModel) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(model.name.isEmpty ? model.id : model.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if model.input.contains("image") {
                    Image(systemName: "photo")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.blue)
                }

                if model.reasoning {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.purple)
                }
            }

            Text("\(formatTokenCount(model.contextWindow)) ctx")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - No Key Guidance

    private func noKeyGuidanceView(_ membership: MembershipInfo) -> some View {
        HStack {
            Text(localizedString("API Key"))
                .frame(width: 120, alignment: .leading)

            Image(systemName: "key.slash")
                .foregroundColor(.orange)

            Text(localizedString("No API Key yet"))
                .font(.callout)
                .foregroundColor(.secondary)

            Spacer()

            Button(localizedString("Generate Key")) {
                var urlString = "\(AuthConfig.baseURL)/member/api-keys/"
                if let uid = authManager.userId {
                    urlString += "?user_id=\(uid)"
                }
                if let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button(localizedString("Sync")) {
                Task { await membershipManager.syncProfile() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(membershipManager.syncState == .syncing)
        }
    }

    // MARK: - Syncing / Error

    private var syncingOrErrorView: some View {
        Group {
            if membershipManager.syncState == .syncing {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(localizedString("Syncing membership info..."))
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            } else if case .error(let msg) = membershipManager.syncState {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(localizedFormat("Sync failed: %@", msg))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(localizedString("Retry")) {
                        Task { await membershipManager.syncProfile() }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                HStack {
                    Text(localizedString("Loading membership info..."))
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(localizedString("Sync")) {
                        Task { await membershipManager.syncProfile() }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Not Logged In

    private var notLoggedInView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .foregroundColor(.secondary)
                Text(localizedString("Log in to use GetClawHub AI service"))
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Button(localizedString("Log In")) {
                authManager.login()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func badgeColor(_ level: MembershipLevel) -> Color {
        switch level {
        case .free: return .gray
        case .pro: return .blue
        case .max: return .purple
        }
    }
}
#endif

private func providerTitle(for provider: ConfiguredCustomProvider) -> String {
    providerTitle(baseUrl: provider.baseUrl, key: provider.key, fallback: provider.key)
}

private func providerTitle(baseUrl: String, key: String, fallback: String) -> String {
    let trimmedBaseUrl = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    if let host = URLComponents(string: trimmedBaseUrl)?.host, !host.isEmpty {
        let cleanedHost = host
            .replacingOccurrences(of: "www.", with: "")
            .replacingOccurrences(of: "api.", with: "")
        if cleanedHost.rangeOfCharacter(from: CharacterSet.letters) == nil {
            return cleanedHost
        }
        if let firstSegment = cleanedHost.split(separator: ".").first, !firstSegment.isEmpty {
            return String(firstSegment).capitalized
        }
        return cleanedHost
    }

    if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return key
            .split(separator: "-")
            .map { part in
                guard let first = part.first else { return "" }
                return first.uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }

    return fallback
}

struct CustomProviderListSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var expandedProviderKey: String?
    @State private var isShowingAddProviderSheet = false
    @State private var pendingDeleteProviderKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(localizedString("Custom Providers"))
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button {
                    clearPendingProviderDelete()
                    isShowingAddProviderSheet = true
                } label: {
                    Label(localizedString("Add Provider"), systemImage: "plus")
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            VStack(spacing: 12) {
                if viewModel.configuredCustomProviders.isEmpty {
                    EmptyCustomProvidersView()
                }

                ForEach(viewModel.configuredCustomProviders) { provider in
                    VStack(alignment: .leading, spacing: 12) {
                        CustomProviderCard(
                            provider: provider,
                            isHighlighted: expandedProviderKey == provider.key,
                            isExpanded: expandedProviderKey == provider.key,
                            isDeleteArmed: pendingDeleteProviderKey == provider.key,
                            isConfigured: isConfigured(provider),
                            modelCount: modelCount(for: provider),
                            onPrimaryTap: {
                                activateProviderCard(provider)
                            },
                            onToggleExpansion: {
                                toggleProviderExpansion(provider)
                            },
                            onDeleteTap: {
                                confirmOrArmProviderDelete(provider)
                            }
                        )

                        SettingsCollapsibleContent(
                            isExpanded: expandedProviderKey == provider.key
                        ) {
                            CustomProviderDetailsSection(viewModel: viewModel, provider: provider)
                                .padding(.top, 2)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingAddProviderSheet) {
            AddCustomProviderSheet(viewModel: viewModel) { providerKey in
                clearPendingProviderDelete()
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedProviderKey = providerKey
                }
            }
        }
    }

    private func isConfigured(_ provider: ConfiguredCustomProvider) -> Bool {
        !provider.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !provider.models.isEmpty
    }

    private func modelCount(for provider: ConfiguredCustomProvider) -> Int {
        provider.models.count
    }

    private func activateProviderCard(_ provider: ConfiguredCustomProvider) {
        clearPendingProviderDelete()
        toggleProviderExpansion(provider)
    }

    private func toggleProviderExpansion(_ provider: ConfiguredCustomProvider) {
        clearPendingProviderDelete()
        withAnimation(.easeInOut(duration: 0.18)) {
            if expandedProviderKey == provider.key {
                expandedProviderKey = nil
            } else {
                expandedProviderKey = provider.key
            }
        }
    }

    private func confirmOrArmProviderDelete(_ provider: ConfiguredCustomProvider) {
        if pendingDeleteProviderKey == provider.key {
            Task {
                guard await viewModel.deleteCustomProviderAndPersist(provider) else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    if expandedProviderKey == provider.key {
                        expandedProviderKey = nil
                    }
                }
                pendingDeleteProviderKey = nil
            }
        } else {
            pendingDeleteProviderKey = provider.key
        }
    }

    private func clearPendingProviderDelete() {
        pendingDeleteProviderKey = nil
    }
}

private struct AddCustomProviderSheet: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onProviderAdded: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var baseUrl = ""
    @State private var apiKey = ""
    @State private var showApiKey = false
    @State private var isAdding = false

    private var canAdd: Bool {
        !baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localizedString("settings.provider.custom.addTitle"))
                    .font(.system(size: 16, weight: .semibold))
                Text(localizedString("settings.provider.custom.addSubtitle"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("http://192.168.0.10:8080/v1", text: $baseUrl)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    ZStack {
                        if showApiKey {
                            TextField(localizedString("settings.provider.custom.apiKeyOptional"), text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField(localizedString("settings.provider.custom.apiKeyOptional"), text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    Button {
                        showApiKey.toggle()
                    } label: {
                        Image(systemName: showApiKey ? "eye" : "eye.slash")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .help(showApiKey ? localizedString("Hide") : localizedString("Show"))
                }
            }

            HStack {
                Spacer()
                Button(localizedString("Cancel")) {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button {
                    Task {
                        isAdding = true
                        let providerKey = await viewModel.addCustomProvider(baseUrl: baseUrl,
                            apiKey: apiKey,
                            api: "openai-completions",
                            fetchModels: true
                        )
                        isAdding = false
                        if let providerKey {
                            onProviderAdded(providerKey)
                            dismiss()
                        }
                    }
                } label: {
                    if isAdding || viewModel.isFetchingProviderModels {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "plus")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canAdd || isAdding || viewModel.isFetchingProviderModels || viewModel.isPersistingProviderConfiguration)
                .help(localizedString("Add Provider"))
            }
        }
        .padding(20)
        .frame(width: 430, alignment: .leading)
    }
}

private struct CustomProviderCard: View {
    let provider: ConfiguredCustomProvider
    let isHighlighted: Bool
    let isExpanded: Bool
    let isDeleteArmed: Bool
    let isConfigured: Bool
    let modelCount: Int
    let onPrimaryTap: () -> Void
    let onToggleExpansion: () -> Void
    let onDeleteTap: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "key")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(isHighlighted ? .blue : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(providerTitle(for: provider))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    ProviderStatusBadge(
                        text: statusText,
                        tone: statusTone
                    )
                }

                HStack(spacing: 8) {
                    Text(provider.baseUrl)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if modelCount > 0 {
                        Text("•")
                        Text(localizedFormat("%lld models", modelCount))
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                onDeleteTap()
            } label: {
                Image(systemName: isDeleteArmed ? "trash.fill" : "trash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isDeleteArmed ? Color.red : Color.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color.red.opacity(isDeleteArmed ? 0.14 : 0))
                    )
            }
            .buttonStyle(.plain)
            .help(deleteHelpText)

            Button {
                onToggleExpansion()
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? localizedString("Collapse") : localizedString("Expand"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isHighlighted ? Color.blue.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: isHighlighted ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onPrimaryTap)
    }

    private var statusText: String {
        if isConfigured { return localizedString("Configured") }
        return localizedString("settings.provider.custom.needsSetup")
    }

    private var statusTone: ProviderStatusBadgeTone {
        if isConfigured { return .configured }
        return .warning
    }

    private var deleteHelpText: String {
        if isDeleteArmed {
            return localizedString("settings.provider.custom.confirmDelete")
        }
        return localizedString("Delete Provider")
    }
}

private struct EmptyCustomProvidersView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(localizedString("settings.provider.custom.emptyTitle"))
                    .font(.system(size: 13, weight: .medium))
                Text(localizedString("settings.provider.custom.emptyDetail"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Custom API Provider (Blue Border + Radio)

struct ModelConfigSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showApiKey = false
    @State private var areModelsExpanded = false
    @State private var isShowingAddModelSheet = false

    #if REQUIRE_LOGIN
    private var isSelected: Bool {
        viewModel.editedActiveServiceSource == "custom"
    }
    #endif

    private var canSaveProviderDetails: Bool {
        !viewModel.editedSelectedProviderKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !viewModel.editedModelBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedProviderDisplayName: String {
        if let provider = viewModel.configuredCustomProviders.first(where: { $0.key == viewModel.editedSelectedProviderKey }) {
            return providerTitle(for: provider)
        }
        let fallback = viewModel.editedSelectedProviderKey.isEmpty
            ? localizedString("Custom API Provider")
            : viewModel.editedSelectedProviderKey
        if !viewModel.editedModelBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return providerTitle(
                baseUrl: viewModel.editedModelBaseUrl,
                key: viewModel.editedSelectedProviderKey,
                fallback: fallback
            )
        }
        return viewModel.editedSelectedProviderKey.isEmpty
            ? localizedString("Custom API Provider")
            : viewModel.editedSelectedProviderKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(selectedProviderDisplayName)
                    .font(.system(size: 13, weight: .semibold))
                Text(localizedString("Provider details"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            // Base URL
            HStack {
                Text(localizedString("API Base URL"))
                    .frame(width: 120, alignment: .leading)

                TextField("https://api.example.com/v1", text: $viewModel.editedModelBaseUrl)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
            }

            // API Key
            HStack {
                Text(localizedString("API Key"))
                    .frame(width: 120, alignment: .leading)

                ZStack {
                    if showApiKey {
                        TextField(localizedString("Enter API key"), text: $viewModel.editedModelApiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField(localizedString("Enter API key"), text: $viewModel.editedModelApiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .frame(maxWidth: .infinity)

                Button(action: { showApiKey.toggle() }) {
                    Image(systemName: showApiKey ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless)
                .help(showApiKey ? localizedString("Hide") : localizedString("Show"))
            }

            customProviderModelsView

            providerDetailActions
        }
        .padding(16)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        #if REQUIRE_LOGIN
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.blue.opacity(isSelected ? 0.18 : 0.08), lineWidth: 1)
        )
        #endif
        .sheet(isPresented: $isShowingAddModelSheet) {
            AddProviderModelSheet { model in
                Task {
                    await viewModel.addModelAndPersist(model)
                }
                areModelsExpanded = true
            }
        }
    }

    private var customProviderModelsView: some View {
        HStack(alignment: .top) {
            Text(localizedString("Models"))
                .frame(width: 120, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(localizedFormat("%lld models configured", viewModel.editedConfiguredModels.count))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    Button {
                        isShowingAddModelSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text(localizedString("Add Model"))
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        Task { await viewModel.fetchModelsForSelectedProvider() }
                    } label: {
                        HStack(spacing: 4) {
                            if viewModel.isFetchingProviderModels {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text(localizedString("Fetch Models"))
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isFetchingProviderModels || viewModel.isPersistingProviderConfiguration || viewModel.editedModelBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !viewModel.editedConfiguredModels.isEmpty {
                    Text(viewModel.editedConfiguredModels.prefix(4).map { $0.name.isEmpty ? $0.id : $0.name }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(localizedString("Fetch models from this provider or add them before saving."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !viewModel.editedConfiguredModels.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            areModelsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(modelListToggleTitle)
                                .font(.caption)
                            Image(systemName: areModelsExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)

                    SettingsCollapsibleContent(isExpanded: areModelsExpanded) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(viewModel.editedConfiguredModels.enumerated()), id: \.element.id) { index, model in
                                    customModelRow(model, index: index)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .frame(maxHeight: 210)
                    }
                }

                if !viewModel.providerModelFetchMessage.isEmpty {
                    Text(viewModel.providerModelFetchMessage)
                        .font(.caption)
                        .foregroundColor(viewModel.providerModelFetchMessage.hasPrefix("Fetched") ? .secondary : .red)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func customModelRow(_ model: PresetModel, index: Int) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name.isEmpty ? model.id : model.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(model.id) · \(formatTokenCount(model.contextWindow)) ctx")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(role: .destructive) {
                Task {
                    await viewModel.removeModelAndPersist(at: index)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isPersistingProviderConfiguration)
            .help(localizedString("settings.provider.custom.removeModel"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var modelListToggleTitle: String {
        areModelsExpanded
            ? localizedString("settings.provider.custom.hideModelList")
            : localizedString("settings.provider.custom.showModelList")
    }

    private var providerDetailActions: some View {
        HStack(spacing: 10) {
            Spacer()

            Button {
                viewModel.resetProviderConfiguration()
            } label: {
                Text(localizedString("Reset"))
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isPersistingProviderConfiguration)

            Button {
                Task {
                    await viewModel.persistProviderConfiguration(showSuccessMessage: true)
                }
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isPersistingProviderConfiguration {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark")
                    }
                    Text(localizedString("Save"))
                }
            }
            .font(.caption)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!canSaveProviderDetails || viewModel.isPersistingProviderConfiguration)
        }
    }
}

private struct CustomProviderDetailsSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    let provider: ConfiguredCustomProvider

    @State private var draftBaseUrl: String
    @State private var draftApiKey: String
    @State private var draftModels: [PresetModel]
    @State private var showApiKey = false
    @State private var areModelsExpanded = false
    @State private var isShowingAddModelSheet = false
    @State private var isFetchingModels = false
    @State private var fetchMessage = ""

    init(viewModel: DashboardViewModel, provider: ConfiguredCustomProvider) {
        self.viewModel = viewModel
        self.provider = provider
        _draftBaseUrl = State(initialValue: provider.baseUrl)
        _draftApiKey = State(initialValue: provider.apiKey)
        _draftModels = State(initialValue: provider.models)
    }

    private var canSaveProviderDetails: Bool {
        !draftBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var providerDisplayName: String {
        providerTitle(
            baseUrl: draftBaseUrl,
            key: provider.key,
            fallback: providerTitle(for: provider)
        )
    }

    private var draftProvider: ConfiguredCustomProvider {
        ConfiguredCustomProvider(
            key: provider.key,
            baseUrl: draftBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: draftApiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            api: provider.api.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "openai-completions" : provider.api,
            models: draftModels
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(providerDisplayName)
                    .font(.system(size: 13, weight: .semibold))
                Text(localizedString("Provider details"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            HStack {
                Text(localizedString("API Base URL"))
                    .frame(width: 120, alignment: .leading)

                TextField("https://api.example.com/v1", text: $draftBaseUrl)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
            }

            HStack {
                Text(localizedString("API Key"))
                    .frame(width: 120, alignment: .leading)

                ZStack {
                    if showApiKey {
                        TextField(localizedString("Enter API key"), text: $draftApiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField(localizedString("Enter API key"), text: $draftApiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .frame(maxWidth: .infinity)

                Button(action: { showApiKey.toggle() }) {
                    Image(systemName: showApiKey ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless)
                .help(showApiKey ? localizedString("Hide") : localizedString("Show"))
            }

            customProviderModelsView

            providerDetailActions
        }
        .padding(16)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.blue.opacity(0.12), lineWidth: 1)
        )
        .sheet(isPresented: $isShowingAddModelSheet) {
            AddProviderModelSheet { model in
                addDraftModelAndPersist(model)
                areModelsExpanded = true
            }
        }
    }

    private var customProviderModelsView: some View {
        HStack(alignment: .top) {
            Text(localizedString("Models"))
                .frame(width: 120, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(localizedFormat("%lld models configured", draftModels.count))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    Button {
                        isShowingAddModelSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text(localizedString("Add Model"))
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isPersistingProviderConfiguration)

                    Button {
                        fetchDraftModels()
                    } label: {
                        HStack(spacing: 4) {
                            if isFetchingModels {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text(localizedString("Fetch Models"))
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isFetchingModels || viewModel.isPersistingProviderConfiguration || draftBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !draftModels.isEmpty {
                    Text(draftModels.prefix(4).map { $0.name.isEmpty ? $0.id : $0.name }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(localizedString("Fetch models from this provider or add them before saving."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !draftModels.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            areModelsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(modelListToggleTitle)
                                .font(.caption)
                            Image(systemName: areModelsExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)

                    SettingsCollapsibleContent(isExpanded: areModelsExpanded) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(draftModels.enumerated()), id: \.element.id) { index, model in
                                    customModelRow(model, index: index)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .frame(maxHeight: 210)
                    }
                }

                if !fetchMessage.isEmpty {
                    Text(fetchMessage)
                        .font(.caption)
                        .foregroundColor(fetchMessage.hasPrefix("Fetched") ? .secondary : .red)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func customModelRow(_ model: PresetModel, index: Int) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name.isEmpty ? model.id : model.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(model.id) · \(formatTokenCount(model.contextWindow)) ctx")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(role: .destructive) {
                removeDraftModelAndPersist(at: index)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isPersistingProviderConfiguration)
            .help(localizedString("settings.provider.custom.removeModel"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var providerDetailActions: some View {
        HStack(spacing: 10) {
            Spacer()

            Button {
                resetDraft()
            } label: {
                Text(localizedString("Reset"))
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isPersistingProviderConfiguration)

            Button {
                Task {
                    await saveDraft(showSuccessMessage: true)
                }
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isPersistingProviderConfiguration {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark")
                    }
                    Text(localizedString("Save"))
                }
            }
            .font(.caption)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!canSaveProviderDetails || viewModel.isPersistingProviderConfiguration)
        }
    }

    private var modelListToggleTitle: String {
        areModelsExpanded
            ? localizedString("settings.provider.custom.hideModelList")
            : localizedString("settings.provider.custom.showModelList")
    }

    private func resetDraft() {
        draftBaseUrl = provider.baseUrl
        draftApiKey = provider.apiKey
        draftModels = provider.models
        fetchMessage = ""
    }

    @discardableResult
    private func saveDraft(showSuccessMessage: Bool = false) async -> Bool {
        await viewModel.updateCustomProviderAndPersist(
            draftProvider,
            showSuccessMessage: showSuccessMessage
        )
    }

    private func fetchDraftModels() {
        Task {
            guard !isFetchingModels else { return }
            isFetchingModels = true
            fetchMessage = ""
            defer { isFetchingModels = false }

            do {
                let models = try await viewModel.fetchModelsForCustomProvider(
                    baseUrl: draftBaseUrl,
                    apiKey: draftApiKey
                )
                let previousModels = draftModels
                draftModels = models
                fetchMessage = "Fetched \(models.count) model\(models.count == 1 ? "" : "s")."
                guard await saveDraft() else {
                    draftModels = previousModels
                    return
                }
            } catch {
                fetchMessage = error.localizedDescription
            }
        }
    }

    private func addDraftModelAndPersist(_ model: PresetModel) {
        let previousModels = draftModels
        upsertDraftModel(model)
        Task {
            guard await saveDraft() else {
                draftModels = previousModels
                return
            }
        }
    }

    private func removeDraftModelAndPersist(at index: Int) {
        guard index >= 0, index < draftModels.count else { return }
        let previousModels = draftModels
        draftModels.remove(at: index)
        Task {
            guard await saveDraft() else {
                draftModels = previousModels
                return
            }
        }
    }

    private func upsertDraftModel(_ model: PresetModel) {
        let trimmedId = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return }
        var normalized = model
        normalized.id = trimmedId
        if normalized.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized.name = trimmedId
        }
        if let index = draftModels.firstIndex(where: { $0.id == trimmedId }) {
            draftModels[index] = normalized
        } else {
            draftModels.append(normalized)
        }
    }
}

private struct AddProviderModelSheet: View {
    let onAdd: (PresetModel) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var modelId = ""
    @State private var displayName = ""
    @State private var contextWindow = "128000"
    @State private var maxTokens = "8192"
    @State private var supportsImage = false
    @State private var supportsReasoning = false

    private var canAdd: Bool {
        !modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localizedString("Add Model"))
                    .font(.system(size: 16, weight: .semibold))
                Text(localizedString("settings.provider.custom.addModelSubtitle"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("model-id", text: $modelId)
                    .textFieldStyle(.roundedBorder)
                TextField(localizedString("Display Name"), text: $displayName)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    TextField(localizedString("Context Window"), text: $contextWindow)
                        .textFieldStyle(.roundedBorder)
                    TextField(localizedString("Max Tokens"), text: $maxTokens)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle(localizedString("settings.provider.custom.supportsImageInput"), isOn: $supportsImage)
                Toggle(localizedString("settings.provider.custom.supportsReasoning"), isOn: $supportsReasoning)
            }

            HStack {
                Spacer()
                Button(localizedString("Cancel")) {
                    dismiss()
                }
                .buttonStyle(.bordered)

	                Button(localizedString("Add")) {
	                    let trimmedId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let model = PresetModel(
                        id: trimmedId,
                        name: trimmedName.isEmpty ? trimmedId : trimmedName,
                        reasoning: supportsReasoning,
                        input: supportsImage ? ["text", "image"] : ["text"],
                        cost: PresetModelCost(),
                        contextWindow: Int(contextWindow.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 128000,
                        maxTokens: Int(maxTokens.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 8192
                    )
	                    onAdd(model)
	                    dismiss()
	                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 430, alignment: .leading)
    }
}

// MARK: - Save Buttons

struct SaveButtonsSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    #if REQUIRE_LOGIN
    @EnvironmentObject var membershipManager: MembershipManager
    #endif

    private var isApiKeyMissing: Bool {
        #if REQUIRE_LOGIN
        if viewModel.editedActiveServiceSource == "getclawhub" {
            // GetClawHub selected: check both the edited key field AND whether user has any active key
            let editedKeyEmpty = viewModel.editedGetClawHubApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let noActiveKey = !membershipManager.apiKeys.contains(where: { $0.isActive })
            return editedKeyEmpty || noActiveKey
        } else {
            return viewModel.editedModelBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        #else
        return viewModel.editedModelBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        #endif
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                viewModel.resetConfiguration()
            }) {
                Text(localizedString("Reset"))
                    .frame(width: 100)
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(action: {
                Task {
                    await viewModel.saveConfiguration()
                }
            }) {
                HStack {
                    Image(systemName: "checkmark")
                    Text(localizedString("Save"))
                }
                .frame(width: 120)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isPerformingAction || isApiKeyMissing)

            Button(action: {
                Task {
                    await viewModel.saveAndRestartService()
                }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text(localizedString("Save & Restart"))
                }
                .frame(width: 160)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isPerformingAction || isApiKeyMissing)
        }
    }
}

// MARK: - Advanced (Gray Border)

struct OpenConfigFileSection: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localizedString("Advanced"))
                .font(.headline)

            HStack {
                Text(localizedString("Edit the full configuration file directly for advanced settings."))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    viewModel.openProviderPresetFile()
                }) {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text(localizedString("Open Providers Preset"))
                    }
                }
                .buttonStyle(.bordered)

                Button(action: {
                    viewModel.openConfigFile()
                }) {
                    HStack {
                        Image(systemName: "doc.text")
                        Text(localizedString("Open Config File"))
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Unsaved Changes Warning

struct UnsavedChangesWarning: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text(localizedString("You have unsaved changes"))
                .font(.body)
                .foregroundColor(.primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

private struct ConfigTabPreviewWrapper: View {
    var body: some View {
        ConfigTabView(
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
    }
}

#Preview {
    ConfigTabPreviewWrapper()
        .frame(width: 700, height: 600)
}
