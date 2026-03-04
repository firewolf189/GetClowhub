import SwiftUI

struct ConfigTabView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Gateway Configuration
                GatewayConfigSection(viewModel: viewModel)

                // Model Provider Configuration
                ModelConfigSection(viewModel: viewModel)

                // Save Buttons
                SaveButtonsSection(viewModel: viewModel)

                // Open Config File
                OpenConfigFileSection(viewModel: viewModel)
            }
            .padding(24)
        }
        .onAppear {
            // Sync edited fields from current in-memory settings
            // (no file re-read; AppSettingsManager.init already loaded)
            viewModel.syncEditedFieldsFromSettings()
        }
    }
}

// MARK: - Gateway Configuration

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
    }
}

// MARK: - Model Provider Configuration

struct ModelConfigSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showApiKey = false
    @State private var showAddModelSheet = false
    @State private var newModelId = ""
    @State private var newModelName = ""
    @State private var newModelContextWindow = "128000"
    @State private var newModelMaxTokens = "8192"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Model Provider")
                .font(.headline)

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
                    Text("Max Out")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .trailing)
                    // Spacer for delete button
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
                        Text(formatTokenCount(model.maxTokens))
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
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
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
}

// MARK: - Save Buttons

struct SaveButtonsSection: View {
    @ObservedObject var viewModel: DashboardViewModel

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
            .disabled(viewModel.isPerformingAction)

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
            .disabled(viewModel.isPerformingAction)
        }
    }
}

// MARK: - Open Config File

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
