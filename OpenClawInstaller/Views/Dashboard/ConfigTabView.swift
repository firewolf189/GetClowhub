import SwiftUI

struct ConfigTabView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Gateway Configuration — red border
                GatewayConfigSection(viewModel: viewModel)

                #if REQUIRE_LOGIN
                // GetClawHub Official Service + Custom API Provider — side by side
                HStack(alignment: .top, spacing: 16) {
                    GetClawHubServiceSection(viewModel: viewModel)
                    ModelConfigSection(viewModel: viewModel)
                }
                #else
                ModelConfigSection(viewModel: viewModel)
                #endif

                // Save Buttons
                SaveButtonsSection(viewModel: viewModel)

                // Advanced — gray border
                OpenConfigFileSection(viewModel: viewModel)
            }
            .padding(24)
        }
        .onAppear {
            viewModel.syncEditedFieldsFromSettings()
        }
    }
}

// MARK: - Gateway Configuration (Red Border)

struct GatewayConfigSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showAuthToken = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Gateway")
                .font(.headline)

            // Port
            HStack {
                Text("Port")
                    .frame(width: 120, alignment: .leading)

                TextField("18789", text: $viewModel.editedPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)

                Text("Gateway listening port")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Auth Token
            HStack {
                Text("Auth Token")
                    .frame(width: 120, alignment: .leading)

                ZStack {
                    if showAuthToken {
                        TextField("Enter auth token", text: $viewModel.editedAuthToken)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Enter auth token", text: $viewModel.editedAuthToken)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .frame(maxWidth: 300)

                Button(action: { showAuthToken.toggle() }) {
                    Image(systemName: showAuthToken ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless)
                .help(showAuthToken ? "Hide" : "Show")

                Text("Authentication token for gateway access")
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

// MARK: - Shared Model Table

private func formatTokenCount(_ count: Int) -> String {
    if count >= 1_000_000 {
        let value = Double(count) / 1_000_000.0
        return value.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(value))M"
            : String(format: "%.1fM", value)
    } else if count >= 1000 {
        let value = Double(count) / 1000.0
        return value.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(value))K"
            : String(format: "%.1fK", value)
    }
    return "\(count)"
}

/// Readonly model table used by GetClawHub section
private struct ReadonlyModelTable: View {
    let models: [PresetModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Table header
            HStack(spacing: 0) {
                Text("Model ID")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Context")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 4)

            ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                HStack(spacing: 0) {
                    Text(model.id)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(formatTokenCount(model.contextWindow))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .background(index % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(4)
            }
        }
    }
}

#if REQUIRE_LOGIN
// MARK: - GetClawHub Official Service (Blue Border + Radio)

struct GetClawHubServiceSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var membershipManager: MembershipManager
    @State private var showApiKey = false
    @State private var isExpanded = true

    private var isSelected: Bool {
        viewModel.editedActiveServiceSource == "getclawhub"
    }

    private var presetModels: [PresetModel] {
        let allModels = viewModel.presetManager.findProvider(byKey: "getclawhub")?.models ?? []
        // Use fallback models based on membership level, ignore backend models
        let allowedModels = membershipManager.membership?.level.defaultModels ?? []
        if !allowedModels.isEmpty {
            let allowedSet = Set(allowedModels)
            return allModels.filter { allowedSet.contains($0.id) }
        }
        return allModels
    }

    private var presetBaseUrl: String {
        viewModel.presetManager.findProvider(byKey: "getclawhub")?.baseUrl ?? "https://ai.getclawhub.com/v1"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Radio + Title + Expand/Collapse
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.system(size: 16))
                    .onTapGesture { viewModel.editedActiveServiceSource = "getclawhub" }

                Text("GetClawHub Official Service")
                    .font(.headline)

                Text("Recommended")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .cornerRadius(4)

                Spacer()

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help(isExpanded ? "Collapse" : "Expand")
            }

            if isExpanded {
                Spacer().frame(height: 16)

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
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(isSelected ? 0.6 : 0.3), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { viewModel.editedActiveServiceSource = "getclawhub" }
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

    // MARK: - Logged In Content

    private func loggedInContent(_ membership: MembershipInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Membership
            HStack {
                Text("Membership")
                    .frame(width: 120, alignment: .leading)

                Text(membership.level.displayName)
                    .fontWeight(.semibold)
                    .foregroundColor(badgeColor(membership.level))

                if let expiresAt = membership.expiresAt {
                    Text("(expires \(expiresAt.formatted(.dateTime.year().month().day())))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Manage") {
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

            // Budget
            HStack {
                Text("Budget")
                    .frame(width: 120, alignment: .leading)

                Text("¥\(String(format: "%.0f", membership.maxBudget)) / month")
                    .foregroundColor(.primary)

                Spacer()

                Text("\(membership.rpmLimit) RPM")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Base URL (readonly) — above API Key
            HStack {
                Text("API Base URL")
                    .frame(width: 120, alignment: .leading)

                TextField("", text: .constant(presetBaseUrl))
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
                    .frame(maxWidth: .infinity)
            }

            // API Key (editable)
            if let _ = membershipManager.apiKeys.last(where: { $0.isActive }) {
                HStack {
                    Text("API Key")
                        .frame(width: 120, alignment: .leading)

                    ZStack {
                        if showApiKey {
                            TextField("Enter API Key", text: $viewModel.editedGetClawHubApiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Enter API Key", text: $viewModel.editedGetClawHubApiKey)
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
                            Text("Sync")
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

            Divider()

            // Models (readonly from preset)
            HStack {
                Text("Models")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text("\(presetModels.count) models")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ReadonlyModelTable(models: presetModels)
        }
    }

    // MARK: - No Key Guidance

    private func noKeyGuidanceView(_ membership: MembershipInfo) -> some View {
        HStack {
            Text("API Key")
                .frame(width: 120, alignment: .leading)

            Image(systemName: "key.slash")
                .foregroundColor(.orange)

            Text("No API Key yet")
                .font(.callout)
                .foregroundColor(.secondary)

            Spacer()

            Button("Generate Key") {
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

            Button("Sync") {
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
                    Text("Syncing membership info...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            } else if case .error(let msg) = membershipManager.syncState {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Sync failed: \(msg)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Retry") {
                        Task { await membershipManager.syncProfile() }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                HStack {
                    Text("Loading membership info...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Sync") {
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
                Text("Log in to use GetClawHub AI service")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Button("Log In") {
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

// MARK: - Custom API Provider (Blue Border + Radio)

struct ModelConfigSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showApiKey = false
    @State private var showAddModelSheet = false
    @State private var newModelId = ""
    @State private var newModelName = ""
    @State private var newModelContextWindow = "128000"
    @State private var newModelMaxTokens = "8192"
    @State private var isExpanded = true

    #if REQUIRE_LOGIN
    private var isSelected: Bool {
        viewModel.editedActiveServiceSource == "custom"
    }
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title row
            HStack(spacing: 8) {
                #if REQUIRE_LOGIN
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.system(size: 16))
                    .onTapGesture { viewModel.editedActiveServiceSource = "custom" }
                #endif

                Text("Custom API Provider")
                    .font(.headline)

                #if REQUIRE_LOGIN
                Text("Use your own API Key")
                    .font(.caption)
                    .foregroundColor(.secondary)
                #endif

                Spacer()

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help(isExpanded ? "Collapse" : "Expand")
            }

            if isExpanded {
                // Provider Picker
                HStack {
                    Text("Provider")
                        .frame(width: 120, alignment: .leading)

                    Picker("", selection: Binding(
                        get: { viewModel.editedSelectedProviderKey },
                        set: { newKey in
                            viewModel.requestSwitchProvider(to: newKey)
                        }
                    )) {
                        ForEach(viewModel.availableProviders) { provider in
                            Text(provider.displayName).tag(provider.key)
                        }
                    }
                    .frame(width: 200)
                }

                // Base URL
                HStack {
                    Text("API Base URL")
                        .frame(width: 120, alignment: .leading)

                    TextField("https://api.example.com/v1", text: $viewModel.editedModelBaseUrl)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                }

                // API Key
                HStack {
                    Text("API Key")
                        .frame(width: 120, alignment: .leading)

                    ZStack {
                        if showApiKey {
                            TextField("Enter API key", text: $viewModel.editedModelApiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Enter API key", text: $viewModel.editedModelApiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Button(action: { showApiKey.toggle() }) {
                        Image(systemName: showApiKey ? "eye" : "eye.slash")
                    }
                    .buttonStyle(.borderless)
                    .help(showApiKey ? "Hide" : "Show")
                }

                Divider()

                // Models List
                HStack {
                    Text("Models")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Button(action: { showAddModelSheet = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Add Model")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if viewModel.editedConfiguredModels.isEmpty {
                    Text("No models configured. Add models or select a provider preset.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    // Table header
                    HStack(spacing: 0) {
                        Text("Model ID")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Context")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        Spacer().frame(width: 32)
                    }
                    .padding(.horizontal, 4)

                    ForEach(Array(viewModel.editedConfiguredModels.enumerated()), id: \.element.id) { index, model in
                        HStack(spacing: 0) {
                            Text(model.id)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(formatTokenCount(model.contextWindow))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .trailing)
                            Button(action: {
                                viewModel.removeModel(at: index)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .frame(width: 32)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                        .background(index % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(4)
                    }
                }
            } // end isExpanded
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        #if REQUIRE_LOGIN
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(isSelected ? 0.6 : 0.3), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { viewModel.editedActiveServiceSource = "custom" }
        #endif
        .alert("Switch Provider", isPresented: $viewModel.showProviderSwitchConfirm) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelSwitchProvider()
            }
            Button("Switch", role: .destructive) {
                viewModel.confirmSwitchProvider()
            }
        } message: {
            Text("Switching provider will replace the current Base URL and model list. API Key will be cleared. Continue?")
        }
        .sheet(isPresented: $showAddModelSheet) {
            addModelSheet
        }
    }

    private var addModelSheet: some View {
        VStack(spacing: 16) {
            Text("Add Model")
                .font(.headline)

            HStack {
                Text("Model ID")
                    .frame(width: 100, alignment: .leading)
                TextField("e.g. gpt-4o", text: $newModelId)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("Name")
                    .frame(width: 100, alignment: .leading)
                TextField("Display name (optional)", text: $newModelName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("Context Window")
                    .frame(width: 100, alignment: .leading)
                TextField("128000", text: $newModelContextWindow)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }

            HStack {
                Text("Max Tokens")
                    .frame(width: 100, alignment: .leading)
                TextField("8192", text: $newModelMaxTokens)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }

            HStack {
                Button("Cancel") {
                    resetAddModelFields()
                    showAddModelSheet = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Add") {
                    let model = PresetModel(
                        id: newModelId,
                        name: newModelName.isEmpty ? newModelId : newModelName,
                        reasoning: false,
                        input: ["text"],
                        cost: PresetModelCost(),
                        contextWindow: Int(newModelContextWindow) ?? 128000,
                        maxTokens: Int(newModelMaxTokens) ?? 8192
                    )
                    viewModel.addModel(model)
                    resetAddModelFields()
                    showAddModelSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newModelId.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func resetAddModelFields() {
        newModelId = ""
        newModelName = ""
        newModelContextWindow = "128000"
        newModelMaxTokens = "8192"
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
            return viewModel.editedModelApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        #else
        return viewModel.editedModelApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        #endif
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                viewModel.resetConfiguration()
            }) {
                Text("Reset")
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
                    Text("Save")
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
                    Text("Save & Restart")
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
            Text("Advanced")
                .font(.headline)

            HStack {
                Text("Edit the full configuration file directly for advanced settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    viewModel.openProviderPresetFile()
                }) {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("Open Providers Preset")
                    }
                }
                .buttonStyle(.bordered)

                Button(action: {
                    viewModel.openConfigFile()
                }) {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("Open Config File")
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

            Text("You have unsaved changes")
                .font(.body)
                .foregroundColor(.primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
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
    .frame(width: 700, height: 600)
}
