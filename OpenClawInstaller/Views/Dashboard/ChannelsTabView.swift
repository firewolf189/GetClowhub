import SwiftUI

struct ChannelsTabView: View {
    @ObservedObject var viewModel: DashboardViewModel

    @State private var showAddSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("Channels")
                        .font(.headline)

                    if !viewModel.channels.isEmpty {
                        Text("(\(viewModel.channels.count) configured)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: { showAddSheet = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Add Channel")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isPerformingAction)

                    Button(action: {
                        Task { await viewModel.loadChannels() }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoadingChannels || viewModel.isPerformingAction)
                }

                if viewModel.isLoadingChannels && viewModel.channels.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading channels...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                } else if viewModel.channels.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No channels configured")
                            .foregroundColor(.secondary)
                        Text("Add a channel to get started")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
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
                        text: channel.configured ? "Configured" : "Not Configured",
                        color: channel.configured ? .green : .orange
                    )

                    if channel.configured {
                        StatusTag(
                            text: channel.linked ? "Linked" : "Not Linked",
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
        .alert("Remove Channel", isPresented: $showRemoveConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { onRemove() }
        } message: {
            Text("Are you sure you want to remove the \(channel.name) channel? This will delete its configuration.")
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
    @State private var pluginsLoaded = false

    private var usesAppKeyAuth: Bool {
        selectedChannel == "dingtalk" || selectedChannel == "feishu"
    }

    private var usesQRLogin: Bool {
        selectedChannel == "weixin"
    }

    /// Map channel type to expected plugin ID
    private var expectedPluginId: String {
        switch selectedChannel {
        case "weixin": return "openclaw-weixin"
        default: return selectedChannel
        }
    }

    /// Check if the plugin for the selected channel is installed
    private var isPluginInstalled: Bool {
        if !pluginsLoaded { return true } // Don't block while loading
        let target = expectedPluginId.lowercased()
        return viewModel.plugins.contains { plugin in
            plugin.pluginId.lowercased() == target
        }
    }

    private var canAdd: Bool {
        if !isPluginInstalled { return false }
        if viewModel.isPerformingAction { return false }
        if usesQRLogin { return false }
        if usesAppKeyAuth {
            return !appKey.trimmingCharacters(in: .whitespaces).isEmpty
                && !appSecret.trimmingCharacters(in: .whitespaces).isEmpty
        } else {
            return !token.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(String(localized: "Add Channel", bundle: LanguageManager.shared.localizedBundle))
                    .font(.headline)

                Spacer()

                Button(String(localized: "Cancel", bundle: LanguageManager.shared.localizedBundle)) {
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
                    Text(String(localized: "Channel Type", bundle: LanguageManager.shared.localizedBundle))
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
                        viewModel.resetWeixinLogin()
                    }
                }

                // Plugin not installed warning
                if !isPluginInstalled {
                    Label(
                        String(localized: "Plugin for \(selectedChannel.capitalized) is not installed. Please install the plugin first.", bundle: LanguageManager.shared.localizedBundle),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundColor(.orange)
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

                                Text(String(localized: "Click the button below to start WeChat QR login", bundle: LanguageManager.shared.localizedBundle))
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Button(String(localized: "Start QR Login", bundle: LanguageManager.shared.localizedBundle)) {
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
                                    Text(String(localized: "Scan with WeChat to connect", bundle: LanguageManager.shared.localizedBundle))
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
                                        Text(String(localized: "Waiting for scan...", bundle: LanguageManager.shared.localizedBundle))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                VStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                    Text(String(localized: "Generating QR code...", bundle: LanguageManager.shared.localizedBundle))
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

                                Text(String(localized: "WeChat connected successfully!", bundle: LanguageManager.shared.localizedBundle))
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Button(String(localized: "Done", bundle: LanguageManager.shared.localizedBundle)) {
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

                                Button(String(localized: "Retry", bundle: LanguageManager.shared.localizedBundle)) {
                                    viewModel.loginWeixinChannel()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        }
                    }
                } else if usesAppKeyAuth {
                    // Credential inputs
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "App Key", bundle: LanguageManager.shared.localizedBundle))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        SecureField(String(localized: "Enter App Key", bundle: LanguageManager.shared.localizedBundle), text: $appKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "App Secret", bundle: LanguageManager.shared.localizedBundle))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        SecureField(String(localized: "Enter App Secret", bundle: LanguageManager.shared.localizedBundle), text: $appSecret)
                            .textFieldStyle(.roundedBorder)
                    }

                    Text(selectedChannel == "dingtalk"
                         ? String(localized: "Go to DingTalk Open Platform to create an app and get the App Key and App Secret.", bundle: LanguageManager.shared.localizedBundle)
                         : String(localized: "Go to Feishu Open Platform to create an app and get the App ID and App Secret.", bundle: LanguageManager.shared.localizedBundle))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Token", bundle: LanguageManager.shared.localizedBundle))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        SecureField(String(localized: "Enter bot token or API key", bundle: LanguageManager.shared.localizedBundle), text: $token)
                            .textFieldStyle(.roundedBorder)

                        Text(String(localized: "For Telegram/Discord: bot token. For Slack: bot token (xoxb-...). Other channels may require different credentials.", bundle: LanguageManager.shared.localizedBundle))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Tip (not for Weixin)
                if !usesQRLogin {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "For channels with complex setup (Slack, Matrix, etc.), use the command line:", bundle: LanguageManager.shared.localizedBundle))
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

                    Button(String(localized: "Add", bundle: LanguageManager.shared.localizedBundle)) {
                        Task {
                            if usesAppKeyAuth {
                                await viewModel.addChannel(channelType: selectedChannel, appKey: appKey, appSecret: appSecret)
                            } else {
                                await viewModel.addChannel(channelType: selectedChannel, token: token)
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
            if viewModel.plugins.isEmpty {
                await viewModel.loadPlugins()
            }
            pluginsLoaded = true
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
