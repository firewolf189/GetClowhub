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
            .alert("Remove Channel", isPresented: $showRemoveConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) { onRemove() }
            } message: {
                Text("Are you sure you want to remove the \(channel.name) channel? This will delete its configuration.")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Channel")
                    .font(.headline)

                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                // Channel picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Channel Type")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Picker("", selection: $selectedChannel) {
                        ForEach(DashboardViewModel.availableChannelTypes, id: \.self) { type in
                            Text(type.capitalized).tag(type)
                        }
                    }
                    .labelsHidden()
                }

                // Token input
                VStack(alignment: .leading, spacing: 6) {
                    Text("Token")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    SecureField("Enter bot token or API key", text: $token)
                        .textFieldStyle(.roundedBorder)

                    Text("For Telegram/Discord: bot token. For Slack: bot token (xoxb-...). Other channels may require different credentials.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Tip
                VStack(alignment: .leading, spacing: 4) {
                    Text("For channels with complex setup (Slack, Matrix, etc.), use the command line:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("openclaw channels add --channel <type> --help")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(16)

            Divider()

            // Footer
            HStack {
                Spacer()

                Button("Add") {
                    Task {
                        await viewModel.addChannel(channelType: selectedChannel, token: token)
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(token.isEmpty || viewModel.isPerformingAction)
            }
            .padding(16)
        }
        .frame(width: 480)
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
