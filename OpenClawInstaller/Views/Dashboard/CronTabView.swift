import SwiftUI

struct CronTabView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.locale) private var locale

    @State private var showAddSheet = false

    var body: some View {
        SmoothScrollView {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text(I18n.t("dashboard.cron.title"))
                        .font(.headline)

                    if !viewModel.cronJobs.isEmpty {
                        Text("(\(viewModel.cronJobs.count))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: { showAddSheet = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text(I18n.t("dashboard.cron.add"))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isPerformingAction)

                    Button(action: {
                        Task { await viewModel.loadCronJobs() }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text(I18n.t("catalog.action.refresh"))
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoadingCronJobs || viewModel.isPerformingAction)

                    if viewModel.isLoadingCronJobs && !viewModel.cronJobs.isEmpty {
                        Text(I18n.t("dashboard.cron.refreshing"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let error = viewModel.cronJobsLoadError, viewModel.cronJobs.isEmpty {
                    CronStateView(
                        systemImage: "exclamationmark.triangle",
                        title: I18n.t("dashboard.cron.loadFailed.title"),
                        detail: error,
                        actionTitle: I18n.t("common.action.retry"),
                        action: {
                            Task { await viewModel.loadCronJobs() }
                        }
                    )
                } else if !viewModel.hasLoadedCronJobs && viewModel.cronJobs.isEmpty {
                    CronStateView(
                        systemImage: "clock.badge",
                        title: I18n.t("dashboard.cron.checking.title"),
                        detail: I18n.t("dashboard.cron.checking.detail"),
                        actionTitle: nil,
                        action: nil
                    )
                } else if viewModel.cronJobs.isEmpty {
                    CronStateView(
                        systemImage: "clock.badge",
                        title: I18n.t("dashboard.cron.empty.title"),
                        detail: I18n.t("dashboard.cron.empty.detail"),
                        actionTitle: nil,
                        action: nil
                    )
                } else {
                    // Cron job list
                    VStack(spacing: 12) {
                        if let error = viewModel.cronJobsLoadError {
                            CronInlineWarning(
                                message: error,
                                onRetry: {
                                    Task { await viewModel.loadCronJobs() }
                                }
                            )
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(viewModel.cronJobs.enumerated()), id: \.element.id) { index, job in
                                CronJobRow(
                                    job: job,
                                    isPerformingAction: viewModel.isPerformingAction,
                                    onToggle: {
                                        Task {
                                            if job.enabled {
                                                await viewModel.disableCronJob(job)
                                            } else {
                                                await viewModel.enableCronJob(job)
                                            }
                                        }
                                    },
                                    onRemove: {
                                        Task { await viewModel.removeCronJob(job) }
                                    }
                                )

                                if index < viewModel.cronJobs.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)
                    }
                }
            }
            .padding(24)
        }
        .task {
            await viewModel.loadCronJobs()
        }
        .sheet(isPresented: $showAddSheet) {
            AddCronJobSheet(
                viewModel: viewModel,
                isPresented: $showAddSheet
            )
            .environment(\.locale, locale)
        }
    }
}

private struct CronStateView: View {
    let systemImage: String
    let title: String
    let detail: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundColor(systemImage == "exclamationmark.triangle" ? .orange : .secondary)

            Text(title)
                .font(.body)
                .foregroundColor(.secondary)

            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

private struct CronInlineWarning: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            Spacer()

            Button(I18n.t("common.action.retry"), action: onRetry)
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
    }
}

// MARK: - Cron Job Row

struct CronJobRow: View {
    let job: CronJobInfo
    let isPerformingAction: Bool
    let onToggle: () -> Void
    let onRemove: () -> Void

    @State private var showRemoveConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            // Job info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(job.name)
                        .font(.body)
                        .fontWeight(.medium)

                    Text(job.schedule)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                }

                HStack(spacing: 8) {
                    if !job.agentId.isEmpty {
                        StatusTag(text: I18n.format("dashboard.cron.agentTag", job.agentId), color: .blue)
                    }

                    if !job.sessionTarget.isEmpty {
                        StatusTag(text: job.sessionTarget, color: .purple)
                    }

                    if !job.timezone.isEmpty {
                        StatusTag(text: job.timezone, color: .secondary)
                    }
                }

                HStack(spacing: 12) {
                    if !job.nextRun.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: 10))
                            Text(I18n.format("dashboard.cron.next", job.nextRun))
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }

                    if !job.lastRun.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 10))
                            Text(I18n.format("dashboard.cron.last", job.lastRun))
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                }

                if !job.message.isEmpty {
                    Text(job.message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Enable/Disable toggle
            Button(action: onToggle) {
                Image(systemName: job.enabled ? "pause.circle" : "play.circle")
                    .font(.system(size: 18))
                    .foregroundColor(job.enabled ? .orange : .green)
            }
            .buttonStyle(.plain)
            .disabled(isPerformingAction)
            .unifiedTooltip(UnifiedTooltipContent(title: job.enabled ? I18n.t("catalog.action.disable") : I18n.t("catalog.action.enable")))

            // Delete button
            Button(action: { showRemoveConfirm = true }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(isPerformingAction)
            .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("catalog.action.remove")))
            .alert(I18n.t("dashboard.cron.alert.removeTitle"), isPresented: $showRemoveConfirm) {
                Button(I18n.t("catalog.action.cancel"), role: .cancel) {}
                Button(I18n.t("catalog.action.remove"), role: .destructive) { onRemove() }
            } message: {
                Text(I18n.format("dashboard.cron.alert.removeMessage", job.name))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusColor: Color {
        if !job.enabled { return .gray }
        switch job.status.lowercased() {
        case "failed", "error": return .red
        case "running": return .blue
        default: return .green
        }
    }
}

// MARK: - Add Cron Job Sheet

struct AddCronJobSheet: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var isPresented: Bool

    @State private var name = ""
    @State private var schedule = ""
    @State private var timezone = "Asia/Shanghai"
    @State private var selectedAgentId = "main"
    @State private var message = ""
    @State private var sessionTarget = "isolated"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(I18n.t("dashboard.cron.sheet.title"))
                    .font(.headline)

                Spacer()

                Button(I18n.t("catalog.action.cancel")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Name
                    VStack(alignment: .leading, spacing: 6) {
                        Text(I18n.t("dashboard.cron.sheet.name"))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        TextField(I18n.t("dashboard.cron.sheet.namePlaceholder"), text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Cron expression
                    VStack(alignment: .leading, spacing: 6) {
                        Text(I18n.t("dashboard.cron.sheet.expression"))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        TextField(I18n.t("dashboard.cron.sheet.expressionPlaceholder"), text: $schedule)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        Text(I18n.t("dashboard.cron.sheet.expressionHelp"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Timezone
                    VStack(alignment: .leading, spacing: 6) {
                        Text(I18n.t("dashboard.cron.sheet.timezone"))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        TextField(I18n.t("dashboard.cron.sheet.timezonePlaceholder"), text: $timezone)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Agent picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text(I18n.t("dashboard.cron.sheet.agent"))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Picker("", selection: $selectedAgentId) {
                            ForEach(viewModel.availableAgents) { agent in
                                Text(agent.name)
                                    .tag(agent.id)
                            }
                        }
                        .labelsHidden()
                    }

                    // Session Target
                    VStack(alignment: .leading, spacing: 6) {
                        Text(I18n.t("dashboard.cron.sheet.sessionTarget"))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Picker("", selection: $sessionTarget) {
                            Text(I18n.t("dashboard.cron.sheet.session.isolated")).tag("isolated")
                            Text(I18n.t("dashboard.cron.sheet.session.main")).tag("main")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)

                        Text(I18n.t("dashboard.cron.sheet.sessionHelp"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Message
                    VStack(alignment: .leading, spacing: 6) {
                        Text(I18n.t("dashboard.cron.sheet.message"))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        ZStack(alignment: .topLeading) {
                            if message.isEmpty {
                                Text(I18n.t("dashboard.cron.sheet.messagePlaceholder"))
                                    .foregroundColor(Color(NSColor.placeholderTextColor))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }

                            TextEditor(text: $message)
                                .font(.body)
                                .frame(minHeight: 80, maxHeight: 160)
                                .scrollContentBackground(.hidden)
                                .padding(2)
                        }
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
                .padding(16)
            }

            Divider()

            // Footer
            HStack {
                Spacer()

                Button(I18n.t("common.action.add")) {
                    Task {
                        await viewModel.addCronJob(
                            name: name,
                            schedule: schedule,
                            timezone: timezone,
                            agentId: selectedAgentId,
                            message: message,
                            sessionTarget: sessionTarget
                        )
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || schedule.isEmpty || viewModel.isPerformingAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 580)
        .onAppear {
            viewModel.loadAvailableAgents()
        }
    }
}

#Preview {
    CronTabView(
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
