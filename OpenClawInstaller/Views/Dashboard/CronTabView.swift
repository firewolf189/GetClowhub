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
                    Text("Cron Jobs")
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
                            Text("Add Job")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isPerformingAction)

                    Button(action: {
                        Task { await viewModel.loadCronJobs() }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoadingCronJobs || viewModel.isPerformingAction)

                    if viewModel.isLoadingCronJobs && !viewModel.cronJobs.isEmpty {
                        Text("Refreshing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let error = viewModel.cronJobsLoadError, viewModel.cronJobs.isEmpty {
                    CronStateView(
                        systemImage: "exclamationmark.triangle",
                        title: "Could not load cron jobs",
                        detail: error,
                        actionTitle: "Retry",
                        action: {
                            Task { await viewModel.loadCronJobs() }
                        }
                    )
                } else if !viewModel.hasLoadedCronJobs && viewModel.cronJobs.isEmpty {
                    CronStateView(
                        systemImage: "clock.badge",
                        title: "Checking cron jobs",
                        detail: "Reading scheduled automation tasks...",
                        actionTitle: nil,
                        action: nil
                    )
                } else if viewModel.cronJobs.isEmpty {
                    CronStateView(
                        systemImage: "clock.badge",
                        title: "No cron jobs configured",
                        detail: "Add a cron job to schedule automated tasks",
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

            Button("Retry", action: onRetry)
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
                        StatusTag(text: "Agent: \(job.agentId)", color: .blue)
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
                            Text("Next: \(job.nextRun)")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }

                    if !job.lastRun.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 10))
                            Text("Last: \(job.lastRun)")
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
            .help(job.enabled ? "Disable" : "Enable")

            // Delete button
            Button(action: { showRemoveConfirm = true }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(isPerformingAction)
            .alert("Remove Cron Job", isPresented: $showRemoveConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) { onRemove() }
            } message: {
                Text("Are you sure you want to remove the cron job '\(job.name)'? This action cannot be undone.")
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
                Text("Add Cron Job")
                    .font(.headline)

                Spacer()

                Button("Cancel") {
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
                        Text("Name")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        TextField("e.g. daily-report", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Cron expression
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cron Expression")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        TextField("e.g. 0 9 * * *", text: $schedule)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        Text("Format: minute hour day month weekday (e.g. \"0 9 * * *\" = every day at 9:00 AM)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Timezone
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Timezone")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        TextField("e.g. Asia/Shanghai", text: $timezone)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Agent picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Agent")
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
                        Text("Session Target")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Picker("", selection: $sessionTarget) {
                            Text("Isolated").tag("isolated")
                            Text("Main").tag("main")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)

                        Text("Isolated: each run in a separate session. Main: reuse the main session.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Message
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Message")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        ZStack(alignment: .topLeading) {
                            if message.isEmpty {
                                Text("The message/instruction to send when the cron job triggers...")
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

                Button("Add") {
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
