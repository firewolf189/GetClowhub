import SwiftUI

struct StatusTabView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Service Status Card
                ServiceStatusCard(viewModel: viewModel)

                // Control Buttons
                ControlButtonsSection(viewModel: viewModel)

                // System Information
                SystemInfoSection(viewModel: viewModel)

            }
            .padding(24)
        }
    }
}

// MARK: - Service Status Card

struct ServiceStatusCard: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(spacing: 20) {
            // Large status icon
            Image(systemName: viewModel.openclawService.status.icon)
                .font(.system(size: 64))
                .foregroundColor(statusColor)

            // Status text
            VStack(spacing: 8) {
                Text(viewModel.openclawService.status.rawValue)
                    .font(.title)
                    .fontWeight(.bold)

                if viewModel.openclawService.status == .running {
                    Text("Running on port \(String(viewModel.openclawService.port))")
                        .font(.body)
                        .foregroundColor(.secondary)

                    if viewModel.openclawService.uptime > 0 {
                        Text("Uptime: \(formatUptime(viewModel.openclawService.uptime))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Version info
            if !viewModel.openclawService.version.isEmpty {
                Text("Version \(viewModel.openclawService.version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
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

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, secs)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }
}

// MARK: - Control Buttons

struct ControlButtonsSection: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Start button
                Button(action: {
                    Task {
                        await viewModel.startService()
                    }
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(viewModel.openclawService.status == .running
                    || viewModel.openclawService.status == .starting
                    || viewModel.openclawService.status == .stopping
                    || viewModel.openclawService.status == .unknown
                    || viewModel.isPerformingAction)

                // Stop button
                Button(action: {
                    Task {
                        await viewModel.stopService()
                    }
                }) {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("Stop")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(viewModel.openclawService.status != .running || viewModel.isPerformingAction)

                // Restart button
                Button(action: {
                    Task {
                        await viewModel.restartService()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Restart")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.openclawService.status != .running || viewModel.isPerformingAction)
            }

            if viewModel.isPerformingAction {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
    }
}

// MARK: - System Information

struct SystemInfoSection: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Information")
                .font(.headline)

            VStack(spacing: 8) {
                InfoRow(
                    label: "macOS Version",
                    value: viewModel.systemEnvironment.osVersion
                )

                InfoRow(
                    label: "Architecture",
                    value: viewModel.systemEnvironment.architecture
                )

                InfoRow(
                    label: "Available Space",
                    value: viewModel.systemEnvironment.availableDiskSpace
                )

                Divider()

                if let nodeInfo = viewModel.systemEnvironment.nodeInfo {
                    InfoRow(
                        label: "Node.js",
                        value: nodeInfo.version
                    )
                }

                if let openclawInfo = viewModel.systemEnvironment.openclawInfo {
                    InfoRow(
                        label: "OpenClaw Path",
                        value: openclawInfo.path
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 150, alignment: .leading)

            Text(value)
                .fontWeight(.medium)

            Spacer()
        }
        .font(.system(.body, design: .monospaced))
    }
}

#Preview {
    StatusTabView(
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
