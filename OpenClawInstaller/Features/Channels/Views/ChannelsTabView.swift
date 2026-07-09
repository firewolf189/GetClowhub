import SwiftUI

struct ChannelsTabView: View {
    @ObservedObject var viewModel: DashboardViewModel

    @State private var showAddSheet = false

    var body: some View {
        SmoothScrollView {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text(I18n.t("dashboard.channels.title"))
                        .font(.headline)

                    if !viewModel.channels.isEmpty {
                        Text(I18n.format("dashboard.count.configured", Int64(viewModel.channels.count)))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: { showAddSheet = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text(I18n.t("dashboard.channels.add"))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isPerformingAction)

                    Button(action: {
                        Task { await viewModel.loadChannels() }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text(I18n.t("catalog.action.refresh"))
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoadingChannels || viewModel.isPerformingAction)

                    SettingsInlineRefreshStatus(isRefreshing: viewModel.isLoadingChannels)
                }

                if viewModel.channels.isEmpty {
                    if viewModel.isLoadingChannels {
                        SettingsStaticLoadingPlaceholder(
                            title: I18n.t("dashboard.channels.loading"),
                            systemImage: "bubble.left.and.bubble.right"
                        )
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text(I18n.t("dashboard.channels.empty.title"))
                                .foregroundColor(.secondary)
                            Text(I18n.t("dashboard.channels.empty.detail"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    }
                } else {
                    // Channel list
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.channels.enumerated()), id: \.element.id) { index, channel in
                            ChannelRow(
                                channel: channel,
                                isPerformingAction: viewModel.isPerformingAction,
                                onRemove: {
                                    Task { await viewModel.removeChannel(channel) }
                                }
                            )

                            if index < viewModel.channels.count - 1 {
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
            await viewModel.loadChannels()
        }
        .sheet(isPresented: $showAddSheet) {
            AddChannelSheet(
                viewModel: viewModel,
                isPresented: $showAddSheet
            )
        }
    }
}

// MARK: - Channel Row

struct ChannelRow: View {
    let channel: ChannelInfo
    let isPerformingAction: Bool
    let onRemove: () -> Void

    @State private var showRemoveConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            // Channel icon
            Image(systemName: channelIcon)
                .font(.system(size: 20))
                .foregroundColor(statusColor)
                .frame(width: 32)

            // Channel info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(channel.name)
                        .font(.body)
                        .fontWeight(.medium)

                    if channel.account != "default" {
                        Text("(\(channel.account))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Status tags
                HStack(spacing: 6) {
                    StatusTag(
                        text: channel.configured ? I18n.t("dashboard.channels.status.configured") : I18n.t("dashboard.channels.status.notConfigured"),
                        color: channel.configured ? .green : .orange
                    )

                    if channel.configured {
                        StatusTag(
                            text: channel.linked ? I18n.t("dashboard.channels.status.linked") : I18n.t("dashboard.channels.status.notLinked"),
                            color: channel.linked ? .green : .orange
                        )
                    }

                    if let error = channel.error {
                        let redundant = (error == "not linked" || error == "not configured")
                        if !redundant {
                            StatusTag(text: error, color: .red)
                        }
                    }
                }
            }

            Spacer()

            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            // Remove button
            Button(action: { showRemoveConfirm = true }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(isPerformingAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .alert(I18n.t("dashboard.channels.alert.removeTitle"), isPresented: $showRemoveConfirm) {
            Button(I18n.t("catalog.action.cancel"), role: .cancel) {}
            Button(I18n.t("catalog.action.remove"), role: .destructive) { onRemove() }
        } message: {
            Text(I18n.format("dashboard.channels.alert.removeMessage", channel.name))
        }
    }

    private var statusColor: Color {
        if channel.error != nil { return .red }
        if !channel.configured { return .orange }
        if !channel.linked { return .yellow }
        return .green
    }

    private var channelIcon: String {
        switch channel.name.lowercased() {
        case "whatsapp": return "message.fill"
        case "telegram": return "paperplane.fill"
        case "discord": return "gamecontroller.fill"
        case "imessage": return "bubble.left.fill"
        case "slack": return "number"
        case "signal": return "lock.shield.fill"
        case "mattermost": return "bubble.left.and.bubble.right.fill"
        case "google chat", "googlechat": return "ellipsis.bubble.fill"
        case "microsoft teams", "msteams": return "person.3.fill"
        case "irc": return "terminal.fill"
        case "matrix": return "square.grid.3x3.fill"
        case "line": return "bubble.right.fill"
        case "nextcloud talk", "nextcloud-talk": return "cloud.fill"
        case "synology chat", "synology-chat": return "server.rack"
        case "zalo": return "bubble.left.and.text.bubble.right.fill"
        case "dingtalk": return "bell.fill"
        case "feishu": return "bird.fill"
        case "nostr": return "antenna.radiowaves.left.and.right"
        case "tlon": return "globe"
        case "weixin": return "message.fill"
        default: return "bubble.left.and.bubble.right"
        }
    }
}

// MARK: - Status Tag

struct StatusTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

// MARK: - Add Channel Sheet

struct AddChannelSheet: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var isPresented: Bool

    @State private var selectedChannel = "telegram"
    @State private var token = ""
    @State private var appKey = ""
    @State private var appSecret = ""
    @State private var accountId = "default"
    @State private var displayName = ""
    @State private var pluginsLoaded = false
    @State private var installingRequiredPlugin = false

    private var usesAppKeyAuth: Bool {
        selectedChannel == "dingtalk" || selectedChannel == "feishu"
    }

    private var usesQRLogin: Bool {
        selectedChannel == "weixin"
    }

    /// Map channel type to known plugin ids/package aliases.
    private var expectedPluginAliases: [String] {
        switch selectedChannel {
        case "dingtalk": return ["dingtalk"]
        case "weixin": return ["weixin", "openclaw-weixin"]
        default: return [selectedChannel]
        }
    }

    private var requiredPluginInstallSpec: String? {
        switch selectedChannel {
        case "dingtalk": return "@openclaw-china/dingtalk"
        case "weixin": return "@tencent-weixin/openclaw-weixin-cli@latest"
        default: return nil
        }
    }

    /// Check if the plugin for the selected channel is installed
    private var isPluginInstalled: Bool {
        if !pluginsLoaded { return true } // Don't block while loading
        return viewModel.plugins.contains { plugin in
            Self.pluginMatchesChannel(plugin, aliases: expectedPluginAliases)
        }
    }

    nonisolated private static func pluginMatchesChannel(_ plugin: PluginInfo, aliases: [String]) -> Bool {
        let fields = ([plugin.pluginId, plugin.channel] + plugin.channelIds)
            .map(normalizedPluginLookupText)

        return aliases
            .map(normalizedPluginLookupText)
            .contains { alias in
                fields.contains { field in
                    field == alias || field.contains(alias)
                }
            }
    }

    nonisolated private static func normalizedPluginLookupText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private var canAdd: Bool {
        if !isPluginInstalled { return false }
        if viewModel.isPerformingAction || installingRequiredPlugin { return false }
        if usesQRLogin { return false }
        if accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if usesAppKeyAuth {
            return !appKey.trimmingCharacters(in: .whitespaces).isEmpty
                && !appSecret.trimmingCharacters(in: .whitespaces).isEmpty
        } else {
            return !token.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var missingPluginPrompt: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.orange)

            Text(I18n.format("dashboard.channels.sheet.pluginMissing", selectedChannel.capitalized))
                .font(.caption)
                .foregroundColor(.orange)

            Spacer(minLength: 8)

            if installingRequiredPlugin {
                ShimmeringStatusText(
                    text: I18n.t("catalog.action.installing"),
                    font: .caption,
                    foregroundStyle: .orange
                )
            } else if requiredPluginInstallSpec != nil {
                Button(I18n.t("catalog.action.install")) {
                    installRequiredPlugin()
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .disabled(viewModel.isPerformingAction)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(I18n.t("dashboard.channels.add"))
                    .font(.headline)

                Spacer()

                Button(I18n.t("catalog.action.cancel")) {
                    viewModel.resetWeixinLogin()
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                // Channel picker
                VStack(alignment: .leading, spacing: 6) {
                    Text(I18n.t("dashboard.channels.sheet.channelType"))
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Picker("", selection: $selectedChannel) {
                        ForEach(DashboardViewModel.availableChannelTypes, id: \.self) { type in
                            Text(type.capitalized).tag(type)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: selectedChannel) { _ in
                        token = ""
                        appKey = ""
                        appSecret = ""
                        accountId = "default"
                        displayName = ""
                        viewModel.resetWeixinLogin()
                    }
                }

                // Plugin not installed warning
                if !isPluginInstalled {
                    missingPluginPrompt
                }

                if usesQRLogin {
                    // Weixin QR Login Flow
                    VStack(spacing: 12) {
                        switch viewModel.weixinLoginStatus {
                        case .idle:
                            VStack(spacing: 12) {
                                Image(systemName: "qrcode")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)

                                Text(I18n.t("dashboard.channels.sheet.qr.startHelp"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Button(I18n.t("dashboard.channels.sheet.qr.start")) {
                                    viewModel.loginWeixinChannel()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!isPluginInstalled)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)

                        case .waitingScan:
                            if let qrImage = viewModel.weixinQRImage {
                                VStack(spacing: 8) {
                                    Text(I18n.t("dashboard.channels.sheet.qr.scan"))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)

                                    Image(nsImage: qrImage)
                                        .interpolation(.none)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 200, height: 200)
                                        .background(Color.white)
                                        .cornerRadius(8)

                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                        Text(I18n.t("dashboard.channels.sheet.qr.waiting"))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                VStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                    Text(I18n.t("dashboard.channels.sheet.qr.generating"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                            }

                        case .success:
                            VStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.green)

                                Text(I18n.t("dashboard.channels.sheet.qr.success"))
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Button(I18n.t("dashboard.channels.sheet.done")) {
                                    viewModel.resetWeixinLogin()
                                    isPresented = false
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)

                        case .failed(let message):
                            VStack(spacing: 12) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.red)

                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)

                                Button(I18n.t("common.action.retry")) {
                                    viewModel.loginWeixinChannel()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(I18n.t("dashboard.channels.sheet.accountId"))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        TextField("default", text: $accountId)
                            .textFieldStyle(.roundedBorder)

                        Text(I18n.t("dashboard.channels.sheet.accountHelp"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(I18n.t("dashboard.channels.sheet.displayName"))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        TextField(I18n.t("dashboard.channels.sheet.optional"), text: $displayName)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                if usesAppKeyAuth {
                    // Credential inputs
                    VStack(alignment: .leading, spacing: 6) {
                        Text(I18n.t("dashboard.channels.sheet.appKey"))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        SecureField(I18n.t("dashboard.channels.sheet.enterAppKey"), text: $appKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(I18n.t("dashboard.channels.sheet.appSecret"))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        SecureField(I18n.t("dashboard.channels.sheet.enterAppSecret"), text: $appSecret)
                            .textFieldStyle(.roundedBorder)
                    }

                    Text(selectedChannel == "dingtalk"
                         ? I18n.t("dashboard.channels.sheet.dingtalkHelp")
                         : I18n.t("dashboard.channels.sheet.feishuHelp"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(I18n.t("dashboard.channels.sheet.token"))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        SecureField(I18n.t("dashboard.channels.sheet.enterToken"), text: $token)
                            .textFieldStyle(.roundedBorder)

                        Text(I18n.t("dashboard.channels.sheet.tokenHelp"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Tip (not for Weixin)
                if !usesQRLogin {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(I18n.t("dashboard.channels.sheet.cliHelp"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("openclaw channels add --channel <type> --help")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(16)

            if !usesQRLogin {
                Divider()

                // Footer
                HStack {
                    Spacer()

                    Button(I18n.t("common.action.add")) {
                        Task {
                            if usesAppKeyAuth {
                                await viewModel.addChannel(
                                    channelType: selectedChannel,
                                    appKey: appKey,
                                    appSecret: appSecret,
                                    accountId: accountId,
                                    displayName: displayName
                                )
                            } else {
                                await viewModel.addChannel(
                                    channelType: selectedChannel,
                                    token: token,
                                    accountId: accountId,
                                    displayName: displayName
                                )
                            }
                            isPresented = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdd)
                }
                .padding(16)
            }
        }
        .frame(width: 480)
        .task {
            await viewModel.loadPlugins()
            pluginsLoaded = true
        }
    }

    private func installRequiredPlugin() {
        guard let spec = requiredPluginInstallSpec else { return }
        installingRequiredPlugin = true
        Task {
            if selectedChannel == "weixin" {
                await viewModel.installWeixinPlugin()
            } else {
                _ = await viewModel.installPluginAndReturnSuccess(spec: spec)
            }
            await viewModel.loadPlugins()
            await MainActor.run {
                pluginsLoaded = true
                installingRequiredPlugin = false
            }
        }
    }
}

#Preview {
    ChannelsTabView(
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
