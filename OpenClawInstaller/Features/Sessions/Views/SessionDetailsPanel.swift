import SwiftUI
import AppKit

// MARK: - Session Details Panel (right column on chat tab)

/// Right-side panel matching the redesign: surfaces metadata about the
/// currently active chat session (agent, model, tool status, session info)
/// plus a destructive "Clear Conversation" action. Two-tab top picker:
/// 会话详情 / 执行记录.
struct SessionDetailsPanel: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var tab: PanelTab = .details

    /// Collapsed by default per redesign — the full 300pt panel takes
    /// a lot of width and most of the time users only need to glance at
    /// the agent / counts. Stored in UserDefaults so the user's
    /// preference persists across launches.
    @AppStorage("dashboard.sessionPanelExpanded") private var expanded: Bool = false

    enum PanelTab: String, CaseIterable {
        case details
        case logs
    }

    var body: some View {
        Group {
            if expanded {
                expandedBody
            } else {
                collapsedBody
            }
        }
        // Pre-load the model list, overview, and skills once when the panel
        // first appears. Applied here (outer group) instead of only on the
        // expanded variant so the collapsed view's tool count badge also
        // populates without waiting for the user to expand. Each viewModel
        // function guards against double-load itself.
        .task {
            if viewModel.availableModelsForSettings.isEmpty {
                await viewModel.loadModelsForSettings()
            }
            if viewModel.modelOverview.defaultModel.isEmpty
                || viewModel.modelOverview.defaultModel == "-" {
                await viewModel.loadModels()
            }
            if viewModel.skills.isEmpty {
                await viewModel.loadSkillMarket()
            }
        }
    }

    // MARK: - Collapsed (default)

    /// Slim vertical strip — mirrors the same content as the expanded
    /// panel but stripped to icons + counts. Toggle handle lives on the
    /// leading edge (vertically centered) — see `edgeChevronHandle`.
    private var collapsedBody: some View {
        VStack(spacing: 14) {
            // Tab labels (clickable — switch tab AND expand). Padded to match
            // the gap left by the old top-chevron so the panel head doesn't
            // butt up against the window's top edge.
            VStack(spacing: 8) {
                ForEach(PanelTab.allCases, id: \.self) { t in
                    Button {
                        tab = t
                        expanded = true
                    } label: {
                        Text(t == .details ? "详情" : "记录")
                            .font(.system(size: 12, weight: tab == t ? .semibold : .regular))
                            .foregroundColor(tab == t ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 16)

            Divider().padding(.horizontal, 12)

            // Agent avatar + name (no picker in collapsed view to save space;
            // user can expand to switch).
            VStack(spacing: 4) {
                if let agent = viewModel.availableAgents.first(where: { $0.id == viewModel.selectedAgentId }) {
                    AgentAvatarImage(size: 24)
                    Text(agent.name)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            // Stats — same data as expanded view, vertical compact form.
            // Each block: label (tiny secondary) + value (small primary).
            // Uptime uses a compact formatter — full HH:MM:SS doesn't
            // fit in 52pt width and gets truncated to "00:00:" mid-string.
            VStack(spacing: 10) {
                statBlock(label: "工具",
                          value: viewModel.skillsSummary.total > 0
                                 ? "\(viewModel.skillsSummary.ready)/\(viewModel.skillsSummary.total)"
                                 : "—")
                statBlock(label: "消息",
                          value: "\(viewModel.chatMessages.count)")
                statBlock(label: "时长",
                          value: Self.formatUptimeCompact(viewModel.openclawService.uptime))
            }

            Spacer()

            // Clear conversation — bottom, destructive red icon-only.
            Button {
                viewModel.chatMessagesByAgent[viewModel.selectedAgentId] = []
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(.red)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.red.opacity(0.45), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("dashboard.tooltip.clearConversation")))
            .padding(.bottom, 16)
        }
        .frame(width: 52)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .leading) { Divider() }
        .overlay(alignment: .leading) { edgeChevronHandle }
    }

    /// Vertical edge handle used by both collapsed and expanded bodies.
    /// Lives on the panel's leading edge, vertically centered. Replaces
    /// the previous top-aligned chevron — feels more like a draggable
    /// panel tab (Notion/Linear convention) and frees the top of the
    /// panel for content. The button is offset half outward so it
    /// visually straddles the divider, giving a "handle sticking out"
    /// affordance.
    private var edgeChevronHandle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                expanded.toggle()
            }
        } label: {
            Image(systemName: expanded ? "chevron.right" : "chevron.left")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 14, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.22), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .unifiedTooltip(UnifiedTooltipContent(title: expanded ? I18n.t("dashboard.tooltip.collapseSessionDetails") : I18n.t("dashboard.tooltip.expandSessionDetails")))
        .offset(x: -7)  // half-out / half-in; the button visually sits on the divider
    }

    /// Short uptime label for the collapsed column. Falls back to a few
    /// distinct formats sized to fit ≤ 5 chars:
    ///   - < 1 min: `<1m`
    ///   - < 1 hr:  `Xm` (e.g. 7m, 42m)
    ///   - < 1 day: `Xh` (e.g. 2h, 23h)
    ///   - 1+ day:  `Xd`
    /// Long-form HH:MM:SS lives on the expanded view's "Uptime" row.
    static func formatUptimeCompact(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "—" }
        let s = Int(seconds)
        if s < 60 { return "<1m" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }

    /// Small label/value block used in the collapsed stats column.
    private func statBlock(label: LocalizedStringKey, value: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }

    // MARK: - Expanded (existing layout)

    private var expandedBody: some View {
        VStack(spacing: 0) {
            // Top tab strip — the collapse chevron used to sit before the
            // first tab; it now lives on the panel's leading edge (see
            // `edgeChevronHandle`), so tabs span the full strip cleanly.
            HStack(spacing: 0) {
                ForEach(PanelTab.allCases, id: \.self) { t in
                    Button {
                        tab = t
                    } label: {
                        VStack(spacing: 4) {
                            Text(t == .details ? "Session Details" : "Activity")
                                .font(.system(size: 13, weight: tab == t ? .semibold : .regular))
                                .foregroundColor(tab == t ? .accentColor : .secondary)
                            Rectangle()
                                .fill(tab == t ? Color.accentColor : Color.clear)
                                .frame(height: 2)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 12)

            Divider()

            // Tab content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch tab {
                    case .details:
                        detailsContent
                    case .logs:
                        activityContent
                    }
                }
                .padding(16)
            }

            Divider()

            // Clear conversation — destructive red button matching the
            // latest design mockup. Wipes the in-memory thread for the
            // active agent (persistence layer continues writing on next
            // turn). Quick action; long-press / right-click on a session
            // in the sidebar still surfaces Export / Rename.
            Button {
                viewModel.chatMessagesByAgent[viewModel.selectedAgentId] = []
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text(I18n.t("dashboard.chat.clearConversation"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.55), lineWidth: 1)
                )
                .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .padding(16)
        }
        .frame(width: 300)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .leading) { Divider() }
        .overlay(alignment: .leading) { edgeChevronHandle }
    }

    // MARK: - Details tab

    @ViewBuilder
    private var detailsContent: some View {
        // Current agent card
        sectionTitle("Current Agent")
        agentCard

        // Model
        sectionTitle("Model")
        modelRow

        // Tool status (mock — wire to real state once backend data is available).
        // Header + count are rendered together inside toolStatusList so the
        // count sits on the same line as the section name, per the design.
        toolStatusList

        // Session info
        sectionTitle("Session Info")
        sessionInfoList
    }

    @ViewBuilder
    private var activityContent: some View {
        if recentActivity.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
                Text(I18n.t("dashboard.activity.empty"))
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            ForEach(recentActivity, id: \.id) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.icon)
                        .font(.system(size: 11))
                        .foregroundColor(item.color)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            if !item.isUser {
                                AgentAvatarImage(size: 12)
                            }
                            Text(item.isUser ? "User" : "Assistant")
                                .font(.system(size: 12, weight: .medium))
                        }
                        Text(item.subtitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Sub-blocks

    private var agentCard: some View {
        // Flat layout — avatar + name + pencil on the left, agent Picker
        // pushed to the right edge. Two distinct entries:
        //   - **Picker** (right side): SWITCH to a different agent.
        //     Writes `viewModel.selectedAgentId`; SwiftUI auto-propagates
        //     the change to the top header read-out and the left-sidebar
        //     agent list.
        //   - **Pencil** (next to name): EDIT the current agent's
        //     identity / soul / model (opens AgentSettingsPanel as a
        //     trailing overlay).
        let agent = viewModel.availableAgents.first { $0.id == viewModel.selectedAgentId }
        return HStack(spacing: 10) {
            AgentAvatarImage(size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent?.name ?? viewModel.selectedAgentId)
                        .font(.system(size: 14, weight: .semibold))
                    Button {
                        viewModel.loadSelectedAgentDetail()
                        Task { await viewModel.loadModelsForSettings() }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.agentSettingsOpen = true
                        }
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("dashboard.tooltip.editAgent")))
                }
                if let desc = agent?.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                } else {
                    Text(I18n.t("dashboard.agent.fallbackDescription"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Agent switch picker — right-aligned, distinct visual unit.
            // Uses a Menu so the trigger renders the current agent's
            // name with a chevron, matching the mock-up's bordered
            // popup-button look.
            Menu {
                ForEach(viewModel.availableAgents) { a in
                    Button {
                        if viewModel.selectedAgentId != a.id {
                            viewModel.selectedAgentId = a.id
                        }
                    } label: {
                        if a.id == viewModel.selectedAgentId {
                            Label(a.name, systemImage: "checkmark")
                        } else {
                            Text(a.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(agent?.name ?? viewModel.selectedAgentId)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    /// Resolves the model that should display for the *current* agent.
    /// Falls back to the global default when an agent has no per-agent model
    /// override — that mirrors the runtime behavior of openclaw.
    /// The **raw** per-agent model override. Empty string means "inherit
    /// the global default" — same semantics as `AgentSettingsPanel`'s
    /// model picker. Was previously returning the RESOLVED model (the
    /// global default substituted in when the agent had no override),
    /// which caused two bugs:
    ///   1. Inconsistency: the sidebar showed e.g. "deepseek-v4-pro"
    ///      while the agent settings panel showed "Default (inherit)"
    ///      for the same agent.
    ///   2. Picker `set:` saw `newValue == currentAgentModel` whenever
    ///      the user picked the same model that was being inherited,
    ///      so the binding was silently a no-op — "无法切换".
    private var currentAgentModel: String {
        viewModel.availableAgents
            .first { $0.id == viewModel.selectedAgentId }?
            .model ?? ""
    }

    /// Display label for the resolved default (shown in parentheses after
    /// "Default (inherit)" so the user can see WHAT they're inheriting).
    private var resolvedDefaultModel: String {
        let defaultModel = viewModel.modelOverview.defaultModel
        return defaultModel.isEmpty || defaultModel == "-"
            ? ""
            : Self.stripProviderPrefix(defaultModel)
    }

    private var modelRow: some View {
        ModelPickerRow(viewModel: viewModel,
                       currentRawModel: currentAgentModel,
                       resolvedDefaultModel: resolvedDefaultModel)
    }

    /// Skills panel — sourced from real `openclaw skills list` data via
    /// viewModel.skills. Top 5 skills shown (sorted by status: ready first),
    /// with a "view all" link below if the user has more than 5 — clicking
    /// jumps to the Skills tab where the full list lives.
    ///
    /// Originally labeled "Tool Status" (→ "工具状态" in zh-Hans), which
    /// was a UI/data-source mismatch: every other surface — the left-nav
    /// label, the Skills tab header, the help FAQ ("技能状态含义？"),
    /// and the openclaw CLI itself (`openclaw skills list`) — calls
    /// these "skills". Renamed to keep terminology consistent across
    /// the app.
    private var toolStatusList: some View {
        let skills = viewModel.skills
        let summary = viewModel.skillsSummary
        let visible = Array(skills.prefix(5))
        return VStack(alignment: .leading, spacing: 6) {
            // Combined section header + count, matching the mockup's
            // single-line "Skills     X / Y enabled" presentation.
            HStack {
                Text(I18n.t("dashboard.skills.title"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if summary.total > 0 {
                    Text(I18n.format("dashboard.skills.enabledCount", Int64(summary.ready), Int64(summary.total)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(I18n.t("dashboard.skills.loading"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 4)

            if visible.isEmpty {
                Text(I18n.t("dashboard.skills.empty"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(visible) { skill in
                    // Each row is a Button that jumps to the Skills tab
                    // — chevron and full row are clickable. Hover gives
                    // the standard pointer feedback so it's obviously
                    // interactive (was a static decoration before).
                    Button {
                        viewModel.selectedTab = .skills
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(skill.status == .ready ? Color.green : Color.secondary.opacity(0.4))
                                .frame(width: 7, height: 7)
                            Text(skill.name)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                        .contentShape(Rectangle())  // make the entire row hit-testable
                    }
                    .buttonStyle(.plain)
                    .help(localizedSkillHelp(for: skill))
                }
            }

            if skills.count > visible.count {
                Button {
                    viewModel.selectedTab = .skills
                } label: {
                    HStack {
                        Text(I18n.format("dashboard.skills.viewAll", Int64(skills.count)))
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func localizedSkillHelp(for skill: SkillInfo) -> String {
        if let catalogItem = SkillNameIndex.firstByName(viewModel.skillCatalog, name: { $0.name })[skill.name] {
            let localizedDescription = I18n.skillDisplay(for: catalogItem).description.trimmingCharacters(in: .whitespacesAndNewlines)
            if !localizedDescription.isEmpty {
                return localizedDescription
            }
        }
        let rawDescription = skill.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return rawDescription.isEmpty ? skill.name : rawDescription
    }

    private var sessionInfoList: some View {
        let activeId = viewModel.selectedSessionIdByAgent[viewModel.selectedAgentId]
        let meta = activeId.flatMap { sid in
            viewModel.sessionsByAgent[viewModel.selectedAgentId]?.first { $0.id == sid }
        }
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm"
            return f
        }()
        return VStack(alignment: .leading, spacing: 6) {
            infoRow("Created",
                    value: meta.map { formatter.string(from: $0.createdAt) } ?? "—")
            infoRow("Messages",
                    value: "\(viewModel.chatMessages.count)")
            infoRow("Session ID",
                    value: activeId.map { Self.shortId($0) } ?? "—")
            infoRow("Uptime",
                    value: Self.formatUptime(viewModel.openclawService.uptime))
        }
    }

    private func infoRow(_ label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.primary)
            .padding(.top, 4)
    }

    /// Activity feed sourced from chat messages — surfaces user/assistant
    /// turns with cancelled / timed-out states highlighted. A full activity
    /// log would pull from openclawService logs but for now this is enough
    /// to give the panel content while .activity tab is selected.
    private struct ActivityItem {
        let id: UUID
        let icon: String
        let color: SwiftUI.Color
        let isUser: Bool
        let subtitle: String
    }

    private var recentActivity: [ActivityItem] {
        viewModel.chatMessages.suffix(20).reversed().map { msg in
            let icon: String
            let color: SwiftUI.Color
            switch msg.taskStatus {
            case .completed:
                icon = "checkmark.circle.fill"
                color = .green
            case .cancelled:
                icon = "xmark.circle.fill"
                color = .red
            case .timedOut:
                icon = "clock.fill"
                color = .orange
            case .background:
                icon = "tray.fill"
                color = .blue
            case .loading:
                icon = "ellipsis.circle"
                color = .secondary
            }
            let preview = msg.content.prefix(80).replacingOccurrences(of: "\n", with: " ")
            return ActivityItem(
                id: msg.id,
                icon: icon,
                color: color,
                isUser: msg.role == .user,
                subtitle: String(preview)
            )
        }
    }

    // MARK: - Helpers

    /// Strip a provider prefix like "getclawhub/" so the model name reads
    /// cleanly in tight UI ("deepseek-v4-pro" rather than the full path).
    static func stripProviderPrefix(_ s: String) -> String {
        if let slash = s.lastIndex(of: "/") {
            return String(s[s.index(after: slash)...])
        }
        return s
    }

    private static func shortId(_ id: UUID) -> String {
        let s = id.uuidString.lowercased()
        return s.prefix(8) + "…" + s.suffix(4)
    }

    private static func formatUptime(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "00:00:00" }
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
