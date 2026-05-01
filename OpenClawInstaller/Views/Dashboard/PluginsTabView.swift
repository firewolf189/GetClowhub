import SwiftUI
import UniformTypeIdentifiers

struct PluginsTabView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showInstallSheet = false

    private var hasGlobalPlugins: Bool {
        viewModel.plugins.contains { $0.origin == .global }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("Plugins")
                        .font(.headline)

                    if !viewModel.plugins.isEmpty {
                        let loaded = viewModel.plugins.filter(\.enabled).count
                        let total = viewModel.plugins.count
                        Text("(\(loaded)/\(total) loaded)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if hasGlobalPlugins {
                        Button(action: {
                            Task { await viewModel.updateAllPlugins() }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Update All")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isLoadingPlugins || viewModel.isPerformingAction)
                    }

                    Button(action: {
                        showInstallSheet = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Install")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isPerformingAction)

                    Button(action: {
                        Task { await viewModel.loadPlugins() }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoadingPlugins || viewModel.isPerformingAction)
                }

                if viewModel.isLoadingPlugins && viewModel.plugins.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading plugins...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                } else if viewModel.plugins.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "puzzlepiece")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No plugins found")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                } else {
                    // Plugin list
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.plugins.enumerated()), id: \.element.id) { index, plugin in
                            PluginRow(
                                plugin: plugin,
                                viewModel: viewModel,
                                isPerformingAction: viewModel.isPerformingAction,
                                onEnable: {
                                    Task { await viewModel.enablePlugin(plugin) }
                                },
                                onDisable: {
                                    Task { await viewModel.disablePlugin(plugin) }
                                },
                                onUninstall: {
                                    Task { await viewModel.uninstallPlugin(plugin) }
                                },
                                onUpdate: {
                                    Task { await viewModel.updatePlugin(plugin) }
                                }
                            )

                            if index < viewModel.plugins.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }
            }
            .padding(24)
        }
        .task {
            await viewModel.loadPlugins()
        }
        .sheet(isPresented: $showInstallSheet) {
            InstallPluginSheet(
                viewModel: viewModel,
                isPresented: $showInstallSheet
            )
        }
    }
}

// MARK: - Plugin Row

struct PluginRow: View {
    let plugin: PluginInfo
    @ObservedObject var viewModel: DashboardViewModel
    let isPerformingAction: Bool
    let onEnable: () -> Void
    let onDisable: () -> Void
    let onUninstall: () -> Void
    let onUpdate: () -> Void

    @State private var isExpanded = false
    @State private var detailInfo: String?
    @State private var isLoadingDetail = false
    @State private var showUninstallConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 12) {
                // Channel icon
                Image(systemName: channelIcon)
                    .font(.system(size: 20))
                    .foregroundColor(plugin.enabled ? .blue : .secondary)
                    .frame(width: 32)

                // Plugin info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(plugin.channel)
                            .font(.body)
                            .fontWeight(.medium)

                        if !plugin.version.isEmpty {
                            Text("v\(plugin.version)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color(NSColor.quaternaryLabelColor).opacity(0.3))
                                .cornerRadius(4)
                        }
                    }

                    HStack(spacing: 6) {
                        Text(plugin.pluginId)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontDesign(.monospaced)

                        if plugin.origin == .bundled {
                            Text("built-in")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        } else if plugin.origin == .global {
                            Text("installed")
                                .font(.caption2)
                                .foregroundColor(.purple)
                        }
                    }
                }

                Spacer()

                // Status badge
                if plugin.enabled {
                    Label("Loaded", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Label("Disabled", systemImage: "minus.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Action buttons for global plugins
                if plugin.origin == .global {
                    Button(action: onUpdate) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .disabled(isPerformingAction)
                    .help("Update plugin")

                    Button(action: {
                        showUninstallConfirm = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isPerformingAction)
                    .help("Uninstall plugin")
                }

                // Enable/Disable button
                Button(action: plugin.enabled ? onDisable : onEnable) {
                    Text(plugin.enabled ? "Disable" : "Enable")
                        .frame(width: 60)
                }
                .buttonStyle(.bordered)
                .tint(plugin.enabled ? .orange : .green)
                .disabled(isPerformingAction)

                // Expand chevron
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                    if isExpanded && detailInfo == nil {
                        loadDetail()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Expanded detail section
            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                if isLoadingDetail {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading plugin info...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                } else if let detail = detailInfo {
                    Text(detail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .padding(16)
                } else {
                    Text("No detail information available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(16)
                }
            }
        }
        .alert("Uninstall Plugin", isPresented: $showUninstallConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) {
                onUninstall()
            }
        } message: {
            Text("Are you sure you want to uninstall '\(plugin.channel)'?")
        }
    }

    private func loadDetail() {
        isLoadingDetail = true
        Task {
            let info = await viewModel.getPluginInfo(plugin)
            await MainActor.run {
                detailInfo = info
                isLoadingDetail = false
            }
        }
    }

    private var channelIcon: String {
        // Match by pluginId (short form from openclaw plugins list)
        switch plugin.pluginId {
        case "whatsapp": return "message.fill"
        case "telegram": return "paperplane.fill"
        case "discord": return "gamecontroller.fill"
        case "imessage", "bluebubbles": return "bubble.left.fill"
        case "slack": return "number"
        case "signal": return "lock.shield.fill"
        case "mattermost": return "bubble.left.and.bubble.right.fill"
        case "googlechat": return "ellipsis.bubble.fill"
        case "msteams": return "person.3.fill"
        case "irc": return "terminal.fill"
        case "matrix": return "square.grid.3x3.fill"
        case "line": return "bubble.right.fill"
        case "nextcloud-talk": return "cloud.fill"
        case "synology-chat": return "server.rack"
        case "zalo", "zalouser": return "bubble.left.and.text.bubble.right.fill"
        case "dingtalk": return "bell.fill"
        case "feishu": return "bird.fill"
        case "nostr": return "antenna.radiowaves.left.and.right"
        case "twitch": return "play.tv.fill"
        case "voice-call", "talk-voice": return "phone.fill"
        case "memory-core", "memory-lancedb": return "brain"
        case "diffs": return "doc.text.magnifyingglass"
        case "acpx": return "cpu"
        case "device-pair": return "link"
        case "phone-control": return "iphone"
        case "copilot-proxy": return "arrow.triangle.branch"
        case "diagnostics-otel": return "waveform.path.ecg"
        case "lobster": return "flowchart"
        case "llm-task": return "text.bubble"
        case "open-prose": return "doc.richtext"
        case "thread-ownership": return "bubble.left.and.exclamationmark.bubble.right"
        case "tlon": return "globe"
        default: return "puzzlepiece.fill"
        }
    }
}

// MARK: - Install Plugin Sheet

enum InstallMethod: String, CaseIterable {
    case npm = "npm"
    case file = "File"
    case link = "Link"
}

enum PluginPreset: String, CaseIterable {
    case custom = "Custom"
    case dingtalk = "DingTalk"
    case weixin = "Weixin"

    var packageName: String? {
        switch self {
        case .custom: return nil
        case .dingtalk: return "@openclaw-china/dingtalk"
        case .weixin: return "@tencent-weixin/openclaw-weixin-cli@latest"
        }
    }

    /// Keywords to match against installed plugin's pluginId, channel name, or source
    var matchKeywords: [String] {
        switch self {
        case .custom: return []
        case .dingtalk: return ["dingtalk", "@openclaw-china/dingtalk"]
        case .weixin: return ["weixin", "openclaw-weixin", "@tencent-weixin/openclaw-weixin"]
        }
    }
}

struct InstallPluginSheet: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var isPresented: Bool

    @State private var installMethod: InstallMethod = .npm
    @State private var selectedPreset: PluginPreset = .custom
    @State private var packageName = ""
    @State private var filePath = ""
    @State private var dirPath = ""
    @State private var isInstalling = false

    private var currentSpec: String {
        switch installMethod {
        case .npm: return packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        case .file: return filePath
        case .link: return dirPath
        }
    }

    private var isPresetAlreadyInstalled: Bool {
        guard selectedPreset != .custom else { return false }
        let keywords = selectedPreset.matchKeywords
        return viewModel.plugins.contains { plugin in
            let id = plugin.pluginId.lowercased()
            let name = plugin.channel.lowercased()
            let source = plugin.source.lowercased()
            return keywords.contains { keyword in
                id.contains(keyword) || name.contains(keyword) || source.contains(keyword)
            }
        }
    }

    private var canInstall: Bool {
        if isPresetAlreadyInstalled { return false }
        return !currentSpec.isEmpty && !isInstalling && !viewModel.isPerformingAction
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(String(localized: "Install Plugin", bundle: LanguageManager.shared.localizedBundle))
                    .font(.headline)
                Spacer()
                Button(String(localized: "Cancel", bundle: LanguageManager.shared.localizedBundle)) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Install method picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Install Method", bundle: LanguageManager.shared.localizedBundle))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Picker("", selection: $installMethod) {
                            ForEach(InstallMethod.allCases, id: \.self) { method in
                                Text(method.rawValue).tag(method)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Method-specific input
                    switch installMethod {
                    case .npm:
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "Quick Select", bundle: LanguageManager.shared.localizedBundle))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Picker("", selection: $selectedPreset) {
                                ForEach(PluginPreset.allCases, id: \.self) { preset in
                                    Text(preset.rawValue).tag(preset)
                                }
                            }
                            .labelsHidden()
                            .onChange(of: selectedPreset) { newValue in
                                if let name = newValue.packageName {
                                    packageName = name
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "Package Name", bundle: LanguageManager.shared.localizedBundle))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            TextField(String(localized: "e.g. @openclaw/discord", bundle: LanguageManager.shared.localizedBundle), text: $packageName)
                                .textFieldStyle(.roundedBorder)
                                .disabled(selectedPreset == .weixin)

                            if isPresetAlreadyInstalled {
                                Label(String(localized: "\(selectedPreset.rawValue) plugin is already installed", bundle: LanguageManager.shared.localizedBundle), systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }

                    case .file:
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "Plugin File", bundle: LanguageManager.shared.localizedBundle))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            HStack {
                                TextField(String(localized: "Select a plugin file...", bundle: LanguageManager.shared.localizedBundle), text: $filePath)
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(true)

                                Button(String(localized: "Browse", bundle: LanguageManager.shared.localizedBundle)) {
                                    browseFile()
                                }
                            }

                            Text(String(localized: "Supported: .ts .js .zip .tgz .tar.gz", bundle: LanguageManager.shared.localizedBundle))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                    case .link:
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "Plugin Directory", bundle: LanguageManager.shared.localizedBundle))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            HStack {
                                TextField(String(localized: "Select a plugin directory...", bundle: LanguageManager.shared.localizedBundle), text: $dirPath)
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(true)

                                Button(String(localized: "Browse", bundle: LanguageManager.shared.localizedBundle)) {
                                    browseDirectory()
                                }
                            }

                            Text(String(localized: "Select a local plugin directory for development linking", bundle: LanguageManager.shared.localizedBundle))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            // Footer
            HStack {
                if isInstalling {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(String(localized: "Installing...", bundle: LanguageManager.shared.localizedBundle))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(String(localized: "Install", bundle: LanguageManager.shared.localizedBundle)) {
                    performInstall()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canInstall)
            }
            .padding(16)
        }
        .frame(width: 480, height: 320)
    }

    private func browseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .init(filenameExtension: "ts")!,
            .init(filenameExtension: "js")!,
            .init(filenameExtension: "zip")!,
            .init(filenameExtension: "tgz")!,
            .init(filenameExtension: "gz")!
        ].compactMap { $0 }

        if panel.runModal() == .OK, let url = panel.url {
            filePath = url.path
        }
    }

    private func browseDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        if panel.runModal() == .OK, let url = panel.url {
            dirPath = url.path
        }
    }

    private func performInstall() {
        isInstalling = true
        let spec = currentSpec
        let isLink = installMethod == .link
        let isWeixin = selectedPreset == .weixin
        Task {
            if isWeixin {
                await viewModel.installWeixinPlugin()
            } else {
                await viewModel.installPlugin(spec: spec, link: isLink)
            }
            await MainActor.run {
                isInstalling = false
                isPresented = false
            }
        }
    }
}

#Preview {
    PluginsTabView(
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
