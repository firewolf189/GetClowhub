import SwiftUI

struct StatusTabView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1. Service Status (compact) + Control Buttons
                ServiceStatusCard(viewModel: viewModel)
                ControlButtonsSection(viewModel: viewModel)

                // 2. Monitoring cards (2x2 grid)
                if viewModel.openclawService.status == .running {
                    HStack(alignment: .top, spacing: 16) {
                        AgentSessionsCard(viewModel: viewModel)
                        CronHealthCard(viewModel: viewModel)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        ChannelStatusCard(viewModel: viewModel)
                        TokenUsageCard(viewModel: viewModel)
                    }
                }

                // 3. System Information
                SystemInfoSection(viewModel: viewModel)
            }
            .padding(24)
        }
        .task {
            if viewModel.openclawService.status == .running {
                async let s: () = viewModel.loadSessionsSummary()
                async let ch: () = viewModel.loadChannels()
                async let cr: () = viewModel.loadCronJobs()
                _ = await (s, ch, cr)
            }
        }
    }
}

// MARK: - Service Status Card (Compact)

struct ServiceStatusCard: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator dot
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)

            Text(viewModel.openclawService.status.rawValue)
                .font(.headline)
                .fontWeight(.bold)

            if viewModel.openclawService.status == .running {
                (Text("Port") + Text(" \(String(viewModel.openclawService.port))"))
                    .font(.body)
                    .foregroundColor(.secondary)

                if viewModel.openclawService.uptime > 0 {
                    (Text("Uptime") + Text(" \(formatUptime(viewModel.openclawService.uptime))"))
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if !viewModel.openclawService.version.isEmpty {
                (Text("Version") + Text(" \(viewModel.openclawService.version)"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
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

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
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

// MARK: - Agent Sessions Card

struct AgentSessionsCard: View {
    @ObservedObject var viewModel: DashboardViewModel

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Agent Sessions", systemImage: "person.3.fill")
                .font(.headline)

            if viewModel.isLoadingSessionsSummary {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .frame(minHeight: 60)
            } else if let summary = viewModel.sessionsSummary, !summary.agents.isEmpty {
                VStack(spacing: 6) {
                    ForEach(summary.agents) { agent in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)

                            Text(agent.agentId)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)

                            Text(agent.model)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color(NSColor.quaternaryLabelColor).opacity(0.3))
                                .cornerRadius(4)
                                .lineLimit(1)

                            Spacer()

                            if let date = agent.lastActiveAt {
                                Text(Self.dateFormatter.string(from: date))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Divider()

                (Text("Total: ") + Text("\(summary.agents.count)") + Text(" agents"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No sessions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Cron Health Card

struct CronHealthCard: View {
    @ObservedObject var viewModel: DashboardViewModel

    private var enabledCount: Int {
        viewModel.cronJobs.filter { $0.enabled }.count
    }

    private var nextJob: CronJobInfo? {
        viewModel.cronJobs
            .filter { $0.enabled && !$0.nextRun.isEmpty }
            .sorted { $0.nextRun < $1.nextRun }
            .first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Cron Health", systemImage: "clock.badge")
                .font(.headline)

            if viewModel.isLoadingCronJobs {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .frame(minHeight: 60)
            } else if !viewModel.cronJobs.isEmpty {
                // Summary line
                HStack(spacing: 12) {
                    (Text("Total: ") + Text("\(viewModel.cronJobs.count)"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    (Text("Active: ") + Text("\(enabledCount)"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let next = nextJob {
                    (Text("Next: ") + Text("\(next.nextRun) (\(next.name))"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 6) {
                    ForEach(viewModel.cronJobs) { job in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(job.enabled ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)

                            Text(job.name)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)

                            Spacer()

                            if job.enabled {
                                Text(job.schedule)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("(disabled)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } else {
                Text("No cron jobs")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Channel Status Card

struct ChannelStatusCard: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Channels", systemImage: "bubble.left.and.bubble.right.fill")
                .font(.headline)

            if viewModel.isLoadingChannels {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .frame(minHeight: 60)
            } else if !viewModel.channels.isEmpty {
                VStack(spacing: 6) {
                    ForEach(viewModel.channels) { channel in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(channelStatusColor(channel))
                                .frame(width: 8, height: 8)

                            Text(channel.name)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)

                            Spacer()

                            Text(LocalizedStringKey(channelStatusLabel(channel)))
                                .font(.caption)
                                .foregroundColor(channelStatusColor(channel))
                        }
                    }
                }

                Divider()

                (Text("\(viewModel.channels.count) ") + Text("channels"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No channels configured")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func channelStatusColor(_ channel: ChannelInfo) -> Color {
        if channel.linked { return .green }
        if channel.configured { return .orange }
        return .gray
    }

    private func channelStatusLabel(_ channel: ChannelInfo) -> String {
        if channel.linked { return "Connected" }
        if channel.configured && !channel.linked { return "Not Linked" }
        if channel.configured { return "Configured" }
        return "Not Configured"
    }
}

// MARK: - Token Usage Card

struct TokenUsageCard: View {
    @ObservedObject var viewModel: DashboardViewModel

    private var globalBudget: BudgetSnapshot? {
        viewModel.budgetSnapshots.first(where: { $0.scope == .global })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Token Usage", systemImage: "chart.bar.fill")
                .font(.headline)

            if viewModel.isLoadingSessionsSummary {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .frame(minHeight: 60)
            } else if let summary = viewModel.sessionsSummary {
                // Totals
                VStack(spacing: 4) {
                    tokenRow(label: "Total:", value: summary.totalTokens)
                }

                // Budget status section
                if let budget = globalBudget {
                    Divider()

                    if budget.tokenLimit > 0 {
                        HStack(spacing: 4) {
                            Text(String(localized: "budget.status.label", defaultValue: "Budget:", bundle: LanguageManager.shared.localizedBundle))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(formatCompact(budget.tokensUsed)) / \(formatCompact(budget.tokenLimit))")
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.medium)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(NSColor.separatorColor))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(budgetStatusColor(budget.tokenStatus))
                                    .frame(
                                        width: max(0, min(geo.size.width, geo.size.width * budget.tokenPercent)),
                                        height: 6
                                    )
                            }
                        }
                        .frame(height: 6)
                    }

                    if budget.costLimit > 0 {
                        HStack(spacing: 4) {
                            Text(String(localized: "Cost:", bundle: LanguageManager.shared.localizedBundle))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "$%.2f / $%.2f", budget.estimatedCost, budget.costLimit))
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.medium)
                        }
                    } else if budget.estimatedCost > 0 {
                        HStack(spacing: 4) {
                            Text(String(localized: "budget.estcost.label", defaultValue: "Est. Cost:", bundle: LanguageManager.shared.localizedBundle))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "$%.2f", budget.estimatedCost))
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.medium)
                        }
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(budgetStatusColor(budget.overallStatus))
                            .frame(width: 8, height: 8)
                        Text(LocalizedStringKey(budget.overallStatus.label))
                            .font(.caption)
                            .foregroundColor(budgetStatusColor(budget.overallStatus))
                    }
                }

                if globalBudget == nil, !summary.agents.isEmpty {
                    Divider()

                    // Top agents by token usage (original behavior)
                    let topAgents = summary.agents
                        .sorted { $0.totalTokens > $1.totalTokens }
                        .prefix(5)

                    VStack(spacing: 4) {
                        ForEach(Array(topAgents)) { agent in
                            HStack {
                                Text(agent.agentId)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(formatNumber(agent.totalTokens))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } else {
                Text("No token data")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(budgetBorderColor, lineWidth: budgetBorderColor == .clear ? 0 : 1.5)
        )
        .task {
            await viewModel.loadBudgets()
        }
    }

    private var budgetBorderColor: Color {
        guard let budget = globalBudget else { return .clear }
        switch budget.overallStatus {
        case .ok: return .clear
        case .warn: return .orange.opacity(0.5)
        case .over: return .red.opacity(0.5)
        }
    }

    private func budgetStatusColor(_ status: BudgetStatus) -> Color {
        switch status {
        case .ok: return .green
        case .warn: return .orange
        case .over: return .red
        }
    }

    private func tokenRow(label: String, value: Int) -> some View {
        HStack {
            Text(label)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            Spacer()
            Text(formatNumber(value))
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
        }
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func formatCompact(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000.0)
        } else if n >= 1_000 {
            return String(format: "%.1fK", Double(n) / 1_000.0)
        }
        return "\(n)"
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
