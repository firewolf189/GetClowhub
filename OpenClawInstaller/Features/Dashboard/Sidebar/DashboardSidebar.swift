import SwiftUI
import SwiftTerm
import UniformTypeIdentifiers
import AVKit
import Combine
import Quartz
import AppKit
import WebKit
import os.log

// Split from DashboardView.swift — file move only, no behavior change.

struct DashboardSidebarState: Equatable {
    let selectedTab: DashboardViewModel.DashboardTab
    let selectedAgentId: String
    let selectedSessionIdByAgent: [String: UUID]
    let availableAgents: [AgentOption]
    let projectSessionsByAgent: [String: [ProjectSessionGroup]]
    let generalSessionsByAgent: [String: [ChatSessionMetadata]]
    let pinnedSessions: [ChatSessionMetadata]
    let inflightSessionIds: Set<UUID>
    let unreadSessionIds: Set<UUID>
    let sessionListFilter: ChatSessionListFilter
    let serviceStatus: ServiceStatus
    let serviceFailureReason: String?
    let serviceVersion: String
    let settingsShortcut: SettingsShortcutState
}

struct DashboardSidebarActions {
    /// Claude-style sidebar: clicking an agent row selects the agent and shows
    /// its chat; the chevron alone toggles expansion.
    let selectAgentChat: (String) -> Void
    let createNewSession: () -> Void
    let openGlobalSessionSearch: () -> Void
    let selectTab: (DashboardViewModel.DashboardTab) -> Void
    let createSessionForAgent: (String) -> Void
    let createSessionForProject: (String, String) -> Void
    /// Session click inside an agent's group: activates the session AND that
    /// agent. There is deliberately NO agent-agnostic variant here — the view
    /// model's `switchSession(to:)` applies the session to whatever agent is
    /// selected, which is exactly the bug this replaced: clicking a session
    /// under another agent left the OLD agent active and pointed it at that
    /// session, so the next send built `agent:<wrong-agent>:<session>`.
    let switchSessionInAgent: (UUID, String) -> Void
    let switchSessionGlobally: (UUID) -> Void
    let togglePinSession: (UUID) -> Void
    let deleteSession: (UUID) -> Void
    let archiveSession: (UUID) -> Void
    let unarchiveSession: (UUID) -> Void
    let setSessionListFilter: (ChatSessionListFilter) -> Void
    let exportSession: (UUID) -> Void
    let toggleProjectCollapse: (String, String) -> Void
    let revealProjectInFinder: (String) -> Void
    let removeProject: (String, String) -> Void
    let openProject: (String) -> Void
    let requestCreateAgent: () -> Void
    let requestRenameSession: (ChatSessionMetadata) -> Void
    let openSettingsSection: (SettingsPageSection) -> Void
    let removeAgent: (String) -> Void
    let loadSettingsShortcutData: () async -> Void
}

struct SidebarView: View {
    let state: DashboardSidebarState
    let actions: DashboardSidebarActions
    @ObservedObject var createAgentVM: SubAgentsViewModel
    @EnvironmentObject var sparkleUpdater: SparkleUpdater
    @EnvironmentObject var languageManager: LanguageManager
    #if REQUIRE_LOGIN
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var membershipManager: MembershipManager
    #endif
    @AppStorage("appAppearance") private var appAppearance: String = "system"
    @Environment(\.colorScheme) private var colorScheme

    private enum SidebarChromeAction: Hashable {
        case newChat
        case searchChats
    }

    // Agent context menu state
    @State private var deleteAgentConfirmId: String?

    // Chat session management state
    @State private var confirmingDeleteSessionId: UUID?

    @State private var hoveredSessionId: UUID?
    @State private var hoveredSidebarTab: DashboardViewModel.DashboardTab?
    @State private var hoveredSidebarAction: SidebarChromeAction?
    @State private var areAgentsCollapsed = false
    @State private var expandedAgentIds: Set<String> = []
    /// Agents whose session list shows ALL rows. By default each expanded agent
    /// renders only the most recent `collapsedSessionRowLimit` sessions plus a
    /// "show more" row — long histories otherwise inflate the sidebar's view
    /// tree (every row carries hover/context-menu/gesture machinery).
    @State private var fullyExpandedSessionAgents: Set<String> = []
    private static let collapsedSessionRowLimit = 8
    @State private var isPinnedSessionsExpanded = true
    @State private var isAgentSectionHeaderHovering = false

    init(
        state: DashboardSidebarState,
        actions: DashboardSidebarActions,
        createAgentVM: SubAgentsViewModel
    ) {
        self.state = state
        self.actions = actions
        self.createAgentVM = createAgentVM
    }

    private var isDark: Bool {
        AppAppearanceMode.storedValue(appAppearance).resolvesDark(using: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarTopHeader
            sidebarMainList
            Divider()
            sidebarBottomBar
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
        .alert(I18n.t("dashboard.agent.remove.title"), isPresented: Binding<Bool>(
            get: { deleteAgentConfirmId != nil },
            set: { if !$0 { deleteAgentConfirmId = nil } }
        )) {
            Button(I18n.t("catalog.action.remove"), role: .destructive) {
                if let agentId = deleteAgentConfirmId {
                    actions.removeAgent(agentId)
                    expandedAgentIds.remove(agentId)
                }
                deleteAgentConfirmId = nil
            }
            Button(I18n.t("catalog.action.cancel"), role: .cancel) {
                deleteAgentConfirmId = nil
            }
        } message: {
            if let agentId = deleteAgentConfirmId,
               let agent = state.availableAgents.first(where: { $0.id == agentId }) {
                Text(I18n.format("dashboard.agent.remove.message", agent.name))
            }
        }
        .onChange(of: state.selectedAgentId) { agentId in
            if state.selectedTab == .chat {
                expandedAgentIds.insert(agentId)
            }
        }
    }

    // MARK: - Sidebar Top Header

    /// Top of the sidebar — text-only app label. NavigationSplitView's own
    /// toggle in the window toolbar handles sidebar collapse.
    private var sidebarTopHeader: some View {
        HStack(spacing: 8) {
            Text("GetClawHub")
                .font(.system(size: 14, weight: .semibold))

            // App's own client version (CFBundleShortVersionString), always
            // visible so users don't need the macOS About panel. Distinct from
            // the gateway/openclaw version shown in ServiceStatusBadge below.
            Text("v\(sparkleUpdater.currentVersion)")
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(.secondary)
                .unifiedTooltip(UnifiedTooltipContent(
                    title: I18n.format("app.update.currentVersion", sparkleUpdater.currentVersion)
                ))

            if sparkleUpdater.updateAvailable {
                Button {
                    cancelSessionDeleteConfirmation()
                    sparkleUpdater.checkForUpdates()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 10))
                        Text("v\(sparkleUpdater.latestVersion)")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(isDark ? 0.16 : 0.10))
                    )
                }
                .buttonStyle(.plain)
                .unifiedTooltip(UnifiedTooltipContent(
                    title: I18n.format("app.update.toVersion", sparkleUpdater.latestVersion),
                    detail: I18n.t("app.update.installLatest")
                ))
            } else {
                // Always-visible "check for updates" affordance with feedback:
                // idle = refresh icon, checking = spinner, up-to-date = brief
                // green tick (SparkleUpdater auto-clears checkSucceeded after 2s).
                Button {
                    cancelSessionDeleteConfirmation()
                    Task { await sparkleUpdater.checkLatestVersion(showSuccessPulse: true) }
                } label: {
                    if sparkleUpdater.isCheckingVersion {
                        ProgressView()
                            .controlSize(.small)
                    } else if sparkleUpdater.checkSucceeded {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                            Text(I18n.t("app.update.upToDate"))
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.green)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(sparkleUpdater.isCheckingVersion)
                .unifiedTooltip(UnifiedTooltipContent(
                    title: I18n.t("app.update.check"),
                    detail: I18n.t("app.update.lookForLatest")
                ))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Sidebar Main List (the new unified list)

    /// Primary app sidebar. Rows use custom buttons so selected state can
    /// stay quiet gray instead of macOS' blue list selection.
    private var sidebarMainList: some View {
        SmoothScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ServiceStatusBadge(
                    status: state.serviceStatus,
                    version: state.serviceVersion,
                    failureReason: state.serviceFailureReason
                )
                    .padding(.bottom, 8)

                Button {
                    cancelSessionDeleteConfirmation()
                    actions.createNewSession()
                    actions.selectTab(.chat)
                } label: {
                    let isNewChatActive = state.selectedTab == .chat
                        && state.selectedSessionIdByAgent[state.selectedAgentId] == nil

                    sidebarRowContent(title: String(localized: "New chat", bundle: languageManager.localizedBundle), systemImage: "plus.circle")
                        .foregroundColor(.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(sidebarItemHighlightColor(
                                    isActive: isNewChatActive,
                                    isHovering: hoveredSidebarAction == .newChat
                                ))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    updateSidebarActionHover(.newChat, hovering: hovering)
                }

                Button {
                    cancelSessionDeleteConfirmation()
                    actions.openGlobalSessionSearch()
                } label: {
                    sidebarRowContent(title: String(localized: "Search chats", bundle: languageManager.localizedBundle), systemImage: "magnifyingglass")
                        .foregroundColor(.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(sidebarItemHighlightColor(
                                    isActive: false,
                                    isHovering: hoveredSidebarAction == .searchChats
                                ))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    updateSidebarActionHover(.searchChats, hovering: hovering)
                }
                .help(I18n.t("dashboard.tooltip.searchChats", fallback: "Search chats"))

                navRow(.skills, title: String(localized: "Skills", bundle: languageManager.localizedBundle), systemImage: AppSystemSymbol.skills)
                navRow(.plugins, title: String(localized: "Plugins", bundle: languageManager.localizedBundle), systemImage: "powerplug.portrait")
                navRow(.tasksLogs, title: String(localized: "Automation", bundle: languageManager.localizedBundle), systemImage: "clock.badge")
                navRow(.market, title: String(localized: "AgentsMarket", bundle: languageManager.localizedBundle), systemImage: "storefront")

                globalPinnedSessionsSection
                agentSectionContent

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func navRow(_ tab: DashboardViewModel.DashboardTab, title: String, systemImage: String, assetImage: String? = nil) -> some View {
        Button {
            cancelSessionDeleteConfirmation()
            actions.selectTab(tab)
        } label: {
            sidebarRowContent(title: title, systemImage: systemImage, assetImage: assetImage)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(sidebarItemHighlightColor(
                            isActive: state.selectedTab == tab,
                            isHovering: hoveredSidebarTab == tab
                        ))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            updateSidebarTabHover(tab, hovering: hovering)
        }
    }

    private func sidebarRowContent(title: String, systemImage: String, assetImage: String? = nil) -> some View {
        HStack(spacing: 10) {
            sidebarIcon(systemImage: systemImage, assetImage: assetImage)
                .frame(width: DashboardSidebarMetrics.sidebarIconSlotWidth, height: DashboardSidebarMetrics.sidebarIconSlotWidth)
            Text(title)
                .lineLimit(1)
            Spacer()
        }
        .font(DashboardTypography.sidebarRow)
        .foregroundColor(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func sidebarIcon(systemImage: String, assetImage: String?) -> some View {
        if let assetImage {
            Image(assetImage)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: systemImage)
        }
    }

    // MARK: - Sessions Section Content (extracted so it stays readable)

    @ViewBuilder
    private func sessionsSectionContent(for agent: AgentOption) -> some View {
        let projectGroups = state.projectSessionsByAgent[agent.id] ?? []
        let generalSessions = state.generalSessionsByAgent[agent.id] ?? []

        if projectGroups.isEmpty && generalSessions.isEmpty {
            Text(I18n.t(state.sessionListFilter.emptyCopyKey))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)
        } else {
            projectFoldersSectionContent(for: agent)
            generalSessionsSectionContent(for: agent)
        }
    }

    @ViewBuilder
    private func projectFoldersSectionContent(for agent: AgentOption) -> some View {
        let projectGroups = state.projectSessionsByAgent[agent.id] ?? []

        ForEach(projectGroups) { group in
            projectFolderRow(group: group, agent: agent)
        }
    }

    @ViewBuilder
    private func generalSessionsSectionContent(for agent: AgentOption) -> some View {
        let generalSessions = state.generalSessionsByAgent[agent.id] ?? []
        let limit = Self.collapsedSessionRowLimit
        let showAll = fullyExpandedSessionAgents.contains(agent.id)
        let visible = showAll ? generalSessions : Array(generalSessions.prefix(limit))
        let hiddenCount = generalSessions.count - visible.count

        sessionRows(visible, for: agent)

        if hiddenCount > 0 {
            showMoreSessionsRow(agentId: agent.id, hiddenCount: hiddenCount)
        }
    }

    private func showMoreSessionsRow(agentId: String, hiddenCount: Int) -> some View {
        Button {
            cancelSessionDeleteConfirmation()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                _ = fullyExpandedSessionAgents.insert(agentId)
            }
        } label: {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: DashboardSidebarMetrics.sessionTitleLeadingSpacer)
                Text(I18n.format("dashboard.session.showMore", String(hiddenCount)))
                    .font(DashboardTypography.sidebarSessionTitle)
                    .foregroundColor(.secondary)
                Spacer(minLength: 4)
            }
            .frame(height: DashboardSidebarMetrics.sessionRowContentHeight)
            .padding(.horizontal, 8)
            .padding(.vertical, DashboardSidebarMetrics.sessionRowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sessionRows(
        _ agentSessions: [ChatSessionMetadata],
        for agent: AgentOption? = nil,
        switchGlobally: Bool = false
    ) -> some View {
        ForEach(agentSessions) { meta in
            let isSessionActive = state.selectedTab == .chat
                && state.selectedAgentId == meta.agentId
                && state.selectedSessionIdByAgent[meta.agentId] == meta.id
            let isSessionHovering = hoveredSessionId == meta.id

            ChatSessionRow(
                meta: meta,
                isActive: isSessionActive,
                isExecuting: state.inflightSessionIds.contains(meta.id),
                isUnread: state.unreadSessionIds.contains(meta.id) && !isSessionActive,
                isHovering: isSessionHovering,
                isDeleteConfirming: confirmingDeleteSessionId == meta.id,
                onPinToggle: {
                    cancelSessionDeleteConfirmation()
                    actions.togglePinSession(meta.id)
                },
                onDeleteIntent: {
                    setSessionDeleteConfirmation(meta.id)
                },
                onDeleteConfirm: {
                    actions.deleteSession(meta.id)
                    cancelSessionDeleteConfirmation()
                }
            )
            .padding(.horizontal, 8)
            .padding(.vertical, DashboardSidebarMetrics.sessionRowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(sessionRowHighlightColor(isActive: isSessionActive, isHovering: isSessionHovering))
            )
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                cancelSessionDeleteConfirmation()
                actions.requestRenameSession(meta)
            }
            .onTapGesture {
                cancelSessionDeleteConfirmation()
                if switchGlobally {
                    actions.switchSessionGlobally(meta.id)
                } else {
                    // The row's own agent, not the selected one: clicking a
                    // session under another agent must bring that agent forward
                    // (the highlight below is already keyed on meta.agentId).
                    let ownerAgentId = agent.map(\.id).flatMap { $0.isEmpty ? nil : $0 } ?? meta.agentId
                    actions.switchSessionInAgent(meta.id, ownerAgentId)
                }
                actions.selectTab(.chat)
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    if hovering {
                        hoveredSessionId = meta.id
                    } else if hoveredSessionId == meta.id {
                        cancelSessionDeleteConfirmation()
                        hoveredSessionId = nil
                    }
                }
            }
            .contextMenu {
                Button {
                    cancelSessionDeleteConfirmation()
                    actions.requestRenameSession(meta)
                } label: {
                    Label(I18n.t("dashboard.session.action.rename"), systemImage: "pencil")
                }
                Button {
                    actions.togglePinSession(meta.id)
                } label: {
                    Label(meta.isPinned ? I18n.t("dashboard.session.action.unpin") : I18n.t("dashboard.session.action.pin"),
                          systemImage: meta.isPinned ? "pin.slash" : "pin")
                }
                Button {
                    actions.exportSession(meta.id)
                } label: {
                    Label(I18n.t("dashboard.session.action.export"), systemImage: "square.and.arrow.up")
                }
                Divider()
                if meta.isArchived {
                    Button {
                        cancelSessionDeleteConfirmation()
                        actions.unarchiveSession(meta.id)
                    } label: {
                        Label(I18n.t("dashboard.session.action.unarchive"), systemImage: "archivebox")
                    }
                } else {
                    Button {
                        cancelSessionDeleteConfirmation()
                        actions.archiveSession(meta.id)
                    } label: {
                        Label(I18n.t("dashboard.session.action.archive"), systemImage: "archivebox")
                    }
                }
                Button(role: .destructive) {
                    setSessionDeleteConfirmation(meta.id)
                } label: {
                    Label(I18n.t("common.action.delete"), systemImage: "trash")
                }
            }
        }
    }

    private func projectFolderRow(group: ProjectSessionGroup, agent: AgentOption) -> some View {
        AgentProjectFolderRow(
            group: group,
            backgroundColor: { isHovering in
                sidebarItemHighlightColor(isActive: false, isHovering: isHovering)
            },
            onToggle: {
                cancelSessionDeleteConfirmation()
                actions.toggleProjectCollapse(agent.id, group.project.id)
            },
            onNewSession: {
                cancelSessionDeleteConfirmation()
                actions.createSessionForProject(agent.id, group.project.id)
                actions.selectTab(.chat)
            },
            onRevealInFinder: {
                actions.revealProjectInFinder(group.project.id)
            },
            onRemoveFromAgent: {
                actions.removeProject(group.project.id, agent.id)
            },
            sessions: {
                sessionRows(group.sessions, for: agent)
            }
        )
    }

    @ViewBuilder
    private var globalPinnedSessionsSection: some View {
        if !state.pinnedSessions.isEmpty {
            SidebarCollapsibleRow(
                title: I18n.t("dashboard.sidebar.pinned"),
                titleFont: DashboardTypography.sidebarAgent(active: false),
                isExpanded: isPinnedSessionsExpanded,
                rowHeight: 24,
                verticalPadding: 4,
                backgroundColor: { isHovering in
                    sidebarItemHighlightColor(isActive: false, isHovering: isHovering)
                },
                onToggle: {
                    cancelSessionDeleteConfirmation()
                    isPinnedSessionsExpanded.toggle()
                },
                icon: {
                    Image(systemName: "pin")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                },
                actions: {
                    EmptyView()
                },
                children: {
                    sessionRows(state.pinnedSessions, switchGlobally: true)
                }
            )
            .padding(.top, 6)
        }
    }

    // MARK: - Agent Section Content

    @ViewBuilder
    private var agentSectionContent: some View {
        let visibleAgents = state.availableAgents.filter {
            !DashboardViewModel.internalAgentIds.contains($0.id)
        }

        HStack(spacing: 6) {
            HStack(spacing: DashboardSidebarMetrics.agentTitleSpacing) {
                Image(systemName: "person")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.primary)
                    .frame(width: DashboardSidebarMetrics.sidebarIconSlotWidth, height: 20)
                Text(String(localized: "Agent", bundle: languageManager.localizedBundle))
                    .font(DashboardTypography.sidebarSectionTitle)
                    .foregroundColor(.primary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 12, height: 20)
                    .rotationEffect(.degrees(areAgentsCollapsed ? 0 : 90))
                    .opacity(isAgentSectionHeaderHovering ? 1 : 0)
                    .animation(.easeInOut(duration: 0.16), value: areAgentsCollapsed)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                toggleAgentSectionCollapse()
            }

        }
        .frame(height: 20)
        .overlay(alignment: .trailing) {
            HStack(spacing: 0) {
                sessionListFilterMenu
                Button {
                    cancelSessionDeleteConfirmation()
                    actions.requestCreateAgent()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .opacity(isAgentSectionHeaderHovering ? 1 : 0)
                .disabled(!isAgentSectionHeaderHovering)
                .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("subAgents.action.new")))
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isAgentSectionHeaderHovering = hovering
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isAgentSectionHeaderHovering)

        Group {
            if !areAgentsCollapsed {
                Group {
                    if visibleAgents.isEmpty {
                        Text(String(localized: "No agents yet", bundle: languageManager.localizedBundle))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                    } else {
                        ForEach(visibleAgents) { agent in
                            agentSidebarRow(agent)
                        }
                    }
                }
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
                .clipped()
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: areAgentsCollapsed)
    }

    // MARK: - Sidebar Bottom Bar

    private var sidebarBottomBar: some View {
        SettingsShortcutPanelButton(
            shortcutState: state.settingsShortcut,
            loadShortcutData: actions.loadSettingsShortcutData,
            isActive: state.selectedTab == .config,
            highlightColor: { isOpen in
                sidebarItemHighlightColor(isActive: state.selectedTab == .config, isHovering: isOpen)
            },
            onBeforeToggle: {
                cancelSessionDeleteConfirmation()
            },
            onOpenSettingsSection: actions.openSettingsSection
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Agents List

    /// Agents grouped by division for the sidebar
    private var agentsByDivisionGrouped: [(division: String, agents: [AgentOption])] {
        let grouped = Dictionary(grouping: state.availableAgents.filter {
            $0.id != "commander" && $0.id != "main" && !$0.division.isEmpty
        }) { $0.division }

        // Sort: Custom first, then alphabetical
        let divisionOrder = ["Custom"] + Self.divisionEmoji.keys.sorted()
        return divisionOrder.compactMap { div in
            guard let agents = grouped[div], !agents.isEmpty else { return nil }
            return (division: div, agents: agents)
        }
    }

    private func agentSidebarRow(_ agent: AgentOption) -> some View {
        let isActive = state.selectedAgentId == agent.id && state.selectedTab == .chat

        return SidebarCollapsibleRow(
            title: agent.name,
            titleFont: DashboardTypography.sidebarAgent(active: isActive),
            isExpanded: expandedAgentIds.contains(agent.id),
            rowHeight: 24,
            verticalPadding: 4,
            backgroundColor: { isHovering in
                sidebarItemHighlightColor(isActive: isActive, isHovering: isHovering)
            },
            onToggle: {
                toggleAgentSelection(agent)
            },
            onSelect: {
                cancelSessionDeleteConfirmation()
                // Claude-style: the row body opens the agent's chat (and keeps
                // it expanded); collapsing is the chevron's job.
                expandedAgentIds.insert(agent.id)
                actions.selectAgentChat(agent.id)
            },
            showsChevronAlways: true,
            showsIconSlot: false,
            icon: {
                EmptyView()
            },
            actions: {
                Button {
                    cancelSessionDeleteConfirmation()
                    actions.openProject(agent.id)
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("dashboard.agent.addWorkFolder")))

                Button {
                    createSession(for: agent)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("dashboard.session.newChat")))
            },
            children: {
                sessionsSectionContent(for: agent)
            }
        )
        .contextMenu {
            Button {
                actions.openProject(agent.id)
            } label: {
                Label(I18n.t("dashboard.agent.addWorkFolder"), systemImage: "folder.badge.plus")
            }
            Divider()
            if canDeleteAgent(agent) {
                Button(role: .destructive) {
                    deleteAgentConfirmId = agent.id
                } label: {
                    Label(I18n.t("dashboard.agent.remove.title"), systemImage: "trash")
                }
            }
        }
    }

    private func canDeleteAgent(_ agent: AgentOption) -> Bool {
        agent.id != "main"
            && agent.id != "commander"
            && !DashboardViewModel.internalAgentIds.contains(agent.id)
    }

    private func sidebarItemHighlightColor(isActive: Bool, isHovering: Bool) -> SwiftUI.Color {
        if isActive {
            return SwiftUI.Color.primary.opacity(isDark ? 0.15 : 0.085)
        }
        if isHovering {
            return SwiftUI.Color.primary.opacity(isDark ? 0.10 : 0.058)
        }
        return SwiftUI.Color.clear
    }

    private func updateSidebarTabHover(_ tab: DashboardViewModel.DashboardTab, hovering: Bool) {
        withAnimation(.easeInOut(duration: 0.12)) {
            if hovering {
                hoveredSidebarTab = tab
            } else if hoveredSidebarTab == tab {
                hoveredSidebarTab = nil
            }
        }
    }

    private func updateSidebarActionHover(_ action: SidebarChromeAction, hovering: Bool) {
        withAnimation(.easeInOut(duration: 0.12)) {
            if hovering {
                hoveredSidebarAction = action
            } else if hoveredSidebarAction == action {
                hoveredSidebarAction = nil
            }
        }
    }

    private func sessionRowHighlightColor(isActive: Bool, isHovering: Bool) -> SwiftUI.Color {
        if isActive {
            return SwiftUI.Color.primary.opacity(isDark ? 0.16 : 0.11)
        }
        if isHovering {
            return SwiftUI.Color.primary.opacity(isDark ? 0.11 : 0.07)
        }
        return SwiftUI.Color.clear
    }

    private var sessionListFilterMenu: some View {
        Menu {
            ForEach(ChatSessionListFilter.allCases, id: \.self) { filter in
                Button {
                    cancelSessionDeleteConfirmation()
                    actions.setSessionListFilter(filter)
                } label: {
                    if state.sessionListFilter == filter {
                        Label(I18n.t(filter.titleKey), systemImage: "checkmark")
                    } else {
                        Text(I18n.t(filter.titleKey))
                    }
                }
            }
        } label: {
            Image(systemName: state.sessionListFilter == .active
                  ? "line.3.horizontal.decrease"
                  : "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(state.sessionListFilter == .active ? .secondary : .accentColor)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("dashboard.session.filter.tooltip")))
    }

    private func setSessionDeleteConfirmation(_ sessionId: UUID) {
        confirmingDeleteSessionId = sessionId
        hoveredSessionId = sessionId
    }

    private func cancelSessionDeleteConfirmation() {
        confirmingDeleteSessionId = nil
        hoveredSessionId = nil
    }

    private func toggleAgentSectionCollapse() {
        cancelSessionDeleteConfirmation()

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            areAgentsCollapsed.toggle()
        }
    }

    private func toggleAgentSelection(_ agent: AgentOption) {
        cancelSessionDeleteConfirmation()

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            if expandedAgentIds.contains(agent.id) {
                expandedAgentIds.remove(agent.id)
            } else {
                expandedAgentIds.insert(agent.id)
            }
        }
    }

    private func createSession(for agent: AgentOption) {
        cancelSessionDeleteConfirmation()
        actions.createSessionForAgent(agent.id)
        actions.selectTab(.chat)
    }

    private static let divisionEmoji: [String: String] = [
        "Academic": "🎓",
        "Design": "🎨",
        "Engineering": "⚙️",
        "Game Development": "🎮",
        "Marketing": "📣",
        "Paid Media": "💰",
        "Product": "📦",
        "Project Management": "📋",
        "Sales": "🤝",
        "Spatial Computing": "🥽",
        "Specialized": "⭐",
        "Support": "🛟",
        "Testing": "🧪",
    ]

}

struct SidebarCollapsibleRow<Icon: View, Actions: View, Children: View>: View {
    private static var expansionAnimation: Animation {
        .spring(response: 0.28, dampingFraction: 0.86)
    }

    private static var hoverAnimation: Animation {
        .easeInOut(duration: 0.12)
    }

    private static var childTransition: AnyTransition {
        .asymmetric(insertion: .opacity, removal: .identity)
    }

    let title: String
    let titleFont: Font
    let isExpanded: Bool
    let rowHeight: CGFloat
    let verticalPadding: CGFloat
    let backgroundColor: (Bool) -> SwiftUI.Color
    let onToggle: () -> Void
    /// Claude-style split interaction: when set, tapping the row body invokes
    /// this (select) and ONLY the chevron toggles expansion. When nil the whole
    /// row toggles (legacy behavior, e.g. the pinned-sessions header).
    var onSelect: (() -> Void)? = nil
    /// Keep the chevron visible even when not hovering (Claude keeps the
    /// disclosure indicator persistently next to the name).
    var showsChevronAlways: Bool = false
    /// Claude-style rows have no leading icon — the name starts flush. When
    /// false the icon slot is not rendered at all (agent rows); legacy callers
    /// (pinned header) keep their icon.
    var showsIconSlot: Bool = true
    @ViewBuilder let icon: () -> Icon
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let children: () -> Children

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowContent

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    children()
                }
                .transition(Self.childTransition)
                .clipped()
            }
        }
        .animation(Self.expansionAnimation, value: isExpanded)
        .clipped()
    }

    private var rowContent: some View {
        HStack(spacing: DashboardSidebarMetrics.agentTitleSpacing) {
            if showsIconSlot {
                icon()
                    .frame(width: DashboardSidebarMetrics.sidebarIconSlotWidth, height: DashboardSidebarMetrics.agentAvatarSize)
            }

            Text(title)
                .font(titleFont)
                .lineLimit(1)

            chevron

            Spacer(minLength: 8)
        }
        .frame(height: rowHeight)
        .overlay(alignment: .trailing) {
            HStack(spacing: 2) {
                actions()
            }
            .opacity(isHovering ? 1 : 0)
            .disabled(!isHovering)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor(isHovering))
        )
        .onTapGesture {
            if let onSelect {
                onSelect()
            } else {
                withAnimation(Self.expansionAnimation) {
                    onToggle()
                }
            }
        }
        .onHover { hovering in
            withAnimation(Self.hoverAnimation) {
                isHovering = hovering
            }
        }
    }

    @ViewBuilder
    private var chevron: some View {
        let chevronImage = Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .frame(
                width: DashboardSidebarMetrics.disclosureChevronWidth,
                height: DashboardSidebarMetrics.disclosureChevronHeight
            )
            .opacity(showsChevronAlways || isHovering || isExpanded ? 1 : 0)
            .animation(Self.hoverAnimation, value: isHovering)

        if onSelect != nil {
            // Dedicated hit target: only the chevron toggles when row taps select.
            Button {
                withAnimation(Self.expansionAnimation) {
                    onToggle()
                }
            } label: {
                chevronImage
                    .frame(width: 18, height: rowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            chevronImage
        }
    }
}

// MARK: - Pulsing Dot (green breathing animation)

// MARK: - Marketplace Agent Row

private struct MarketplaceAgentRow: View {
    let agent: MarketplaceAgent
    @EnvironmentObject var languageManager: LanguageManager

    private var display: MarketplaceAgentDisplay {
        agent.localizedDisplay(localeID: languageManager.currentLocale.identifier)
    }

    var body: some View {
        HStack(spacing: 10) {
            AgentAvatarImage(size: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(display.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                if !display.description.isEmpty {
                    Text(display.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                Text(display.division)
                    .font(.system(size: 10))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundColor(.accentColor)
                    .cornerRadius(3)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 8, height: 8)
            .opacity(isPulsing ? 1.0 : 0.3)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

// MARK: - Service Status Badge

struct ServiceStatusBadge: View {
    let status: ServiceStatus
    let version: String
    /// Why the gateway is unhappy, in the gateway's own words. Shown instead of
    /// the version line, because "not running" without a reason is what turned a
    /// rejected plugin config into an unexplained restart loop.
    var failureReason: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(status.rawValue)
                    .font(.headline)

                if let failureReason, !failureReason.isEmpty {
                    Text(failureReason)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(failureReason)
                } else if !version.isEmpty {
                    Text("v\(version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: SwiftUI.Color {
        switch status {
        case .running: return .green
        case .stopped: return .gray
        case .starting, .stopping: return .orange
        case .error: return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - Detail Content

// MARK: - Chat Session Row (sidebar)

/// Single row inside the Sessions sidebar section. Renders the title and
/// hover-only actions; the parent sidebar section drives `switchSession(to:)`.
/// The leading dot on a sidebar session row. Three states, Claude-style:
/// hollow bullet by default; solid + breathing while a task streams in the
/// session; solid and STEADY once the reply finished but the user hasn't
/// opened the session yet (unread). The pulse animates opacity only — a
/// render-layer property that never dirties layout (keep it that way: this
/// sidebar has a livelock history).
private struct SessionBulletDot: View {
    let isActive: Bool
    let isExecuting: Bool
    let isUnread: Bool

    @State private var pulseDimmed = false

    var body: some View {
        Group {
            if isExecuting {
                Circle()
                    .fill(Color.accentColor)
                    .opacity(pulseDimmed ? 0.3 : 1)
                    .onAppear {
                        pulseDimmed = false
                        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                            pulseDimmed = true
                        }
                    }
                    .onDisappear { pulseDimmed = false }
            } else if isUnread {
                Circle()
                    .fill(Color.accentColor)
            } else {
                Circle()
                    .strokeBorder(Color.secondary.opacity(isActive ? 0.9 : 0.55), lineWidth: 1)
            }
        }
        .frame(width: 6, height: 6)
    }
}

struct ChatSessionRow: View {
    let meta: ChatSessionMetadata
    let isActive: Bool
    /// True when a foreground task is currently streaming inside this
    /// session (whether or not the session is the visible one).
    let isExecuting: Bool
    /// True when the session's latest run finished while the user was away —
    /// the dot stays solid (no pulse) until the session is opened.
    var isUnread: Bool = false
    let isHovering: Bool
    let isDeleteConfirming: Bool
    let onPinToggle: () -> Void
    let onDeleteIntent: () -> Void
    let onDeleteConfirm: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Claude-style bullet: small dot, tight fixed spacing (4pt inset,
            // 6pt dot, 8pt gap to the title). While a task is streaming in the
            // session the dot turns solid and pulses.
            Color.clear.frame(width: 4)
            SessionBulletDot(isActive: isActive, isExecuting: isExecuting, isUnread: isUnread)
            Color.clear.frame(width: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(meta.title.isEmpty ? I18n.t("dashboard.session.newChat") : meta.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(.primary)
                    .font(DashboardTypography.sidebarSessionTitle)
                    .fontWeight(isActive ? .medium : .regular)
                Text(I18n.format("dashboard.session.row.messageCount", Int64(meta.messageCount)))
                    .lineLimit(1)
                    .foregroundColor(.secondary)
                    .font(DashboardTypography.sidebarSessionMeta)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .trailing) {
                Text(Self.shortRelative(meta.updatedAt))
                    .lineLimit(1)
                    .foregroundColor(.secondary)
                    .font(DashboardTypography.sidebarSessionMeta)
                    .opacity(isHovering || isDeleteConfirming ? 0 : 1)

                HStack(spacing: 2) {
                    Button(action: onPinToggle) {
                        Image(systemName: meta.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: DashboardSidebarMetrics.sessionRowActionSize, height: DashboardSidebarMetrics.sessionRowActionSize)
                    }
                    .buttonStyle(.plain)
                    .unifiedTooltip(UnifiedTooltipContent(title: meta.isPinned
                        ? I18n.t("dashboard.session.action.unpin")
                        : I18n.t("dashboard.session.action.pin")))

                    Button(action: isDeleteConfirming ? onDeleteConfirm : onDeleteIntent) {
                        Image(systemName: isDeleteConfirming ? "trash.fill" : "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(isDeleteConfirming ? .red : .secondary)
                            .frame(width: DashboardSidebarMetrics.sessionRowActionSize, height: DashboardSidebarMetrics.sessionRowActionSize)
                    }
                    .buttonStyle(.plain)
                    .unifiedTooltip(UnifiedTooltipContent(title: isDeleteConfirming
                        ? I18n.t("dashboard.session.action.confirmDelete")
                        : I18n.t("common.action.delete")))
                }
                .opacity(isHovering || isDeleteConfirming ? 1 : 0)
                .disabled(!(isHovering || isDeleteConfirming))
            }
            .frame(width: DashboardSidebarMetrics.sessionRowActionAreaWidth, alignment: .trailing)
        }
        .frame(height: DashboardSidebarMetrics.sessionRowContentHeight)
        .help(isExecuting
              ? I18n.t("dashboard.tooltip.taskRunning", fallback: "Task running")
              : "\(meta.messageCount) · \(Self.fullRelative(meta.updatedAt))")
    }

    /// Compact form for inline sidebar display.
    /// Today    → "now" / "Nm" / "Nh"
    /// Yesterday→ "昨天"
    /// 2-6 days → "N 天前"
    /// Older    → "MM-dd"
    static func shortRelative(_ date: Date) -> String {
        let now = Date()
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) {
            let sec = max(0, Int(now.timeIntervalSince(date)))
            if sec < 60 { return "now" }
            let min = sec / 60
            if min < 60 { return "\(min)m" }
            return "\(min / 60)h"
        }
        if cal.isDateInYesterday(date) {
            return "昨天"
        }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                      to: cal.startOfDay(for: now)).day ?? 0
        if days < 7 {
            return "\(days) 天前"
        }
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        return f.string(from: date)
    }

    /// Verbose form used in the tooltip — keeps the abbreviated relative
    /// formatter for richer context on hover.
    static func fullRelative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    DashboardView(
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
    .frame(width: 960, height: 680)
}
