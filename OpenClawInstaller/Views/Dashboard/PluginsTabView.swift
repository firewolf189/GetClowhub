import SwiftUI

struct PluginsTabView: View {
    @ObservedObject var viewModel: DashboardViewModel

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
                                isPerformingAction: viewModel.isPerformingAction,
                                onEnable: {
                                    Task { await viewModel.enablePlugin(plugin) }
                                },
                                onDisable: {
                                    Task { await viewModel.disablePlugin(plugin) }
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
    }
}

// MARK: - Plugin Row

struct PluginRow: View {
    let plugin: PluginInfo
    let isPerformingAction: Bool
    let onEnable: () -> Void
    let onDisable: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Channel icon
            Image(systemName: channelIcon)
                .font(.system(size: 20))
                .foregroundColor(plugin.enabled ? .blue : .secondary)
                .frame(width: 32)

            // Plugin info
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.channel)
                    .font(.body)
                    .fontWeight(.medium)

                Text(plugin.pluginId)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontDesign(.monospaced)
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

            // Enable/Disable button
            Button(action: plugin.enabled ? onDisable : onEnable) {
                Text(plugin.enabled ? "Disable" : "Enable")
                    .frame(width: 60)
            }
            .buttonStyle(.bordered)
            .tint(plugin.enabled ? .orange : .green)
            .disabled(isPerformingAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
