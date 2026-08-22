import SwiftUI
import UniformTypeIdentifiers
import AVKit
import Combine
import Quartz
import AppKit
import WebKit
import os.log

private struct SessionRenamePresentation: Identifiable {
    let id: UUID
}

private struct RightInspectorContentUpdateID: Hashable {
    let selectedTab: DashboardViewModel.DashboardTab
    let selectedAgentId: String
    let terminalOpen: Bool
    let terminalHeight: CGFloat
    let marketplaceInstallRefreshID: Int
    let requestedUserMessageJumpId: UUID?
}

private enum DashboardPresentationMode: Equatable, Hashable {
    case app
    case settings(SettingsPageSection)

    var isSettingsPresented: Bool {
        if case .settings = self { return true }
        return false
    }

    var settingsSection: SettingsPageSection? {
        if case .settings(let section) = self { return section }
        return nil
    }
}

private struct DashboardChromePolicy: Equatable {
    let showsTitlebarAccessory: Bool
    let showsSessionToolbarTitle: Bool
    let allowsAppOverlays: Bool

    init(presentationMode: DashboardPresentationMode, isChatTabActive: Bool) {
        let isAppPresented = !presentationMode.isSettingsPresented
        showsTitlebarAccessory = isAppPresented && isChatTabActive
        showsSessionToolbarTitle = isAppPresented
        allowsAppOverlays = isAppPresented
    }
}

private struct DashboardSessionTitleToolbarChip: View {
    let activeTab: DashboardViewModel.DashboardTab
    @ObservedObject var chatState: ChatRuntimeState
    @ObservedObject var sessionState: SessionNavigationState
    let onTapMessage: (ChatMessage) -> Void

    private var isChatTabActive: Bool {
        activeTab == .chat
    }

    private var currentMessages: [ChatMessage] {
        chatState.chatMessages(for: sessionState.selectedAgentId)
    }

    private var currentSessionMetadata: ChatSessionMetadata? {
        guard let sessionId = sessionState.selectedSessionIdByAgent[sessionState.selectedAgentId] else {
            return nil
        }
        return (sessionState.sessionsByAgent[sessionState.selectedAgentId] ?? []).first { $0.id == sessionId }
    }

    private var currentSessionTitle: String? {
        guard isChatTabActive, !currentMessages.isEmpty else { return nil }
        let title = currentSessionMetadata?.title
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? nil : title
    }

    private var currentSessionUserMessages: [ChatMessage] {
        guard isChatTabActive else { return [] }
        return currentMessages.filter { $0.role == .user }
    }

    var body: some View {
        if let title = currentSessionTitle {
            SessionTitleUserMessagesPopover(
                title: title,
                messages: currentSessionUserMessages,
                onTapMessage: onTapMessage
            )
        }
    }
}

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject private var taskState: TaskActivityState
    @ObservedObject private var sessionState: SessionNavigationState
    @StateObject private var createAgentVM: SubAgentsViewModel
    @State private var recommendedSkillBootstrapper: RecommendedSkillBootstrapper
    @State private var recommendedPluginBootstrapper: RecommendedPluginBootstrapper
    #if REQUIRE_LOGIN
    @EnvironmentObject var authManager: AuthManager
    #endif
    @EnvironmentObject var languageManager: LanguageManager
    @AppStorage("appAppearance") private var appAppearance: String = "system"
    @AppStorage("appAccent") private var appAccent: String = "green"
    @Environment(\.colorScheme) private var colorScheme
    @State private var isGlobalSessionSearchPresented = false
    @State private var globalSessionSearchText: String = ""
    @State private var isCreateAgentOverlayPresented = false
    @State private var workspaceSidebarExpanded = false
    @State private var isWorkspaceSidebarOpening = false
    @State private var isWorkspaceSidebarClosing = false
    @State private var workspaceSidebarExpandRequestID = 0
    @State private var workspaceSidebarCollapseRequestID = 0
    @State private var pendingWorkspaceSidebarCloseReset = false
    @State private var workspaceBrowserWidth: CGFloat = 280
    @State private var workspaceDetailWidth: CGFloat = 0
    @State private var presentationMode: DashboardPresentationMode = .app
    @State private var marketplaceInstallRefreshID = 0
    @State private var sessionRenamePresentation: SessionRenamePresentation?
    @State private var sessionRenameDraft: String = ""
    @State private var requestedUserMessageJumpId: UUID?
    @State private var terminalOpen = false
    @State private var terminalHeight: CGFloat = 120
    @FocusState private var isGlobalSessionSearchFocused: Bool
    @FocusState private var isSessionRenameFocused: Bool

    private let workspaceSidebarMinWidth: CGFloat = 240
    private let workspaceSidebarMaxWidth: CGFloat = 420
    private let marketplaceDetailAnimation = Animation.spring(response: 0.26, dampingFraction: 0.86)
    private static let workspaceLayoutMetrics = OutputsSidebarLayoutMetrics()

    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
        self._taskState = ObservedObject(wrappedValue: viewModel.taskState)
        self._sessionState = ObservedObject(wrappedValue: viewModel.sessionState)
        _createAgentVM = StateObject(wrappedValue: SubAgentsViewModel(openclawService: viewModel.openclawService))
        _recommendedSkillBootstrapper = State(wrappedValue: RecommendedSkillBootstrapper(openclawService: viewModel.openclawService))
        _recommendedPluginBootstrapper = State(wrappedValue: RecommendedPluginBootstrapper(openclawService: viewModel.openclawService))
    }

    var body: some View {
        presentationRoot
        .onChange(of: viewModel.inspectorFileOpenRequest?.id) { _ in
            guard let request = viewModel.inspectorFileOpenRequest else { return }
            let path = request.path
            // Decide the close behavior HERE: only the owner knows whether the
            // inspector was already open before this click revealed it. Read the
            // flags BEFORE revealing — afterwards they are mid-animation, so the
            // close behaviour would depend on timing.
            let collapseOnClose = !isWorkspaceSidebarExpanded
            if !isWorkspaceSidebarExpanded {
                revealWorkspaceSidebar()
            }
            viewModel.inspectorFileOpenRequest = nil
            // Hand the file over IMMEDIATELY, not after the reveal animation.
            // Waiting meant the inspector slid open still showing the file list
            // and only swapped to the document ~0.45s later — the list visibly
            // flashed first. The pane sizes its content to the FINAL width right
            // away (only the outer sidebar animates), so switching now costs no
            // reflow. `pending` covers the first-ever open, where the pane is not
            // mounted yet and would miss the notification.
            let previewRequest = GCHFilePreviewRequest(path: path, collapseOnClose: collapseOnClose)
            GCHPendingFilePreview.request = previewRequest
            NotificationCenter.default.post(
                name: .gchOpenWorkspaceFilePreview,
                object: previewRequest
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(colorSchemeForAppearance)
        .tint(AppAccentPalette.storedValue(appAccent).color)
        .background(TitlebarSeparatorSuppressor())
        .background(
            RightInspectorTitlebarAccessoryInstaller(
                isVisible: chromePolicy.showsTitlebarAccessory,
                width: rightTitlebarAccessoryWidth
            ) {
                RightInspectorTitlebarAccessory(
                    isTerminalOpen: terminalOpen,
                    isExpanded: isWorkspaceSidebarExpanded,
                    toggleTerminal: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            terminalOpen.toggle()
                        }
                    },
                    toggle: toggleWorkspaceSidebar,
                    close: { hideWorkspaceSidebar(resetEditor: true) }
                )
            }
        )
        .toolbar {
            // macOS 26 draws a Liquid Glass capsule behind toolbar items,
            // which stacks with the chip's own pill background as two
            // offset light/dark rounded rects — hide the shared capsule
            // there and keep the self-drawn pill as the single chrome.
            if #available(macOS 26.0, *) {
                ToolbarItem(placement: .navigation) {
                    if chromePolicy.showsSessionToolbarTitle {
                        sessionTitleToolbarChip
                    } else {
                        EmptyView()
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .navigation) {
                    if chromePolicy.showsSessionToolbarTitle {
                        sessionTitleToolbarChip
                    } else {
                        EmptyView()
                    }
                }
            }
        }
        .alert(I18n.t("dashboard.alert.error"), isPresented: $viewModel.showError) {
            Button(I18n.t("common.action.ok"), role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .overlay(alignment: .top) {
            if viewModel.showSuccess {
                SuccessToast(message: viewModel.successMessage)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if chromePolicy.allowsAppOverlays, isGlobalSessionSearchPresented {
                globalSessionSearchOverlay
            }
        }
        .overlay {
            if chromePolicy.allowsAppOverlays, isCreateAgentOverlayPresented {
                createAgentOverlay
            }
        }
        .overlay {
            if chromePolicy.allowsAppOverlays, sessionRenamePresentation != nil {
                sessionRenameOverlay
            }
        }
        .overlay {
            if chromePolicy.allowsAppOverlays,
               let agent = viewModel.selectedMarketplaceAgent,
               shouldShowMarketplaceDetailOverlay {
                marketplaceDetailOverlay(for: agent)
            }
        }
        .animation(.easeInOut, value: viewModel.showSuccess)
        .animation(.easeInOut(duration: 0.16), value: isGlobalSessionSearchPresented)
        .animation(.easeInOut(duration: 0.16), value: isCreateAgentOverlayPresented)
        .animation(.easeInOut(duration: 0.16), value: sessionRenamePresentation?.id)
        .animation(.easeInOut(duration: 0.16), value: presentationMode)
        .animation(marketplaceDetailAnimation, value: viewModel.selectedMarketplaceAgent?.id)
        .onAppear {
            viewModel.openclawService.startMonitoring()
            Task {
                await viewModel.openclawService.fetchVersion()
                await recommendedSkillBootstrapper.bootstrapRecommendedSkillsIfNeeded()
                await recommendedPluginBootstrapper.bootstrapRecommendedPluginsIfNeeded()
                await preloadSettingsShortcutData()
            }
        }
        .onChange(of: viewModel.openclawService.status) { _, _ in
            Task {
                await recommendedSkillBootstrapper.bootstrapRecommendedSkillsIfNeeded()
                await recommendedPluginBootstrapper.bootstrapRecommendedPluginsIfNeeded()
            }
        }
        .onDisappear {
            viewModel.openclawService.stopMonitoring()
        }
        .sheet(isPresented: $viewModel.showDiagnostics) {
            DiagnosticsSheet(report: viewModel.diagnosticReport, isPresented: $viewModel.showDiagnostics)
        }
    }

    @ViewBuilder
    private var presentationRoot: some View {
        if presentationMode.isSettingsPresented {
            SettingsShellView(
                viewModel: viewModel,
                selectedSection: settingsSectionBinding,
                onBackToApp: closeSettingsPage
            )
            .transition(.opacity)
        } else {
            appWorkspace
                .transition(.opacity)
        }
    }

    private var appWorkspace: some View {
        NavigationSplitView {
            SidebarView(
                state: sidebarState,
                actions: sidebarActions,
                createAgentVM: createAgentVM,
            )
        } detail: {
            RightInspectorSplitView(
                isSidebarExpanded: isWorkspaceSidebarExpanded,
                sidebarWidth: max(workspaceColumnIdealWidth, Self.workspaceLayoutMetrics.browserWidth),
                minSidebarWidth: workspaceSidebarMinWidth,
                maxSidebarWidth: workspaceColumnMaxWidth,
                contentUpdateID: rightInspectorContentUpdateID,
                expandRequestID: workspaceSidebarExpandRequestID,
                collapseRequestID: workspaceSidebarCollapseRequestID,
                onSidebarExpandFinished: completeWorkspaceSidebarOpen,
                onSidebarCollapseFinished: completeWorkspaceSidebarClose
            ) {
                DetailContentView(
                    viewModel: viewModel,
                    workspaceSidebarController: workspaceSidebarController,
                    requestedUserMessageJumpId: $requestedUserMessageJumpId,
                    terminalOpen: $terminalOpen,
                    terminalHeight: $terminalHeight,
                    marketplaceInstallRefreshID: marketplaceInstallRefreshID,
                    onOpenMarketplaceDetail: presentMarketplaceDetail
                )
            } sidebar: {
                workspaceSidebarPane(width: max(workspaceColumnIdealWidth, Self.workspaceLayoutMetrics.browserWidth))
            }
        }
    }

    private var sidebarState: DashboardSidebarState {
        #if REQUIRE_LOGIN
        let billingSnapshot = SettingsShortcutBillingSnapshot.current(
            from: viewModel.membershipManager,
            cacheIdentity: authManager.userId ?? authManager.userEmail
        )
        #else
        let billingSnapshot = SettingsShortcutBillingSnapshot.unavailable
        #endif

        return DashboardSidebarState(
            selectedTab: viewModel.selectedTab,
            selectedAgentId: sessionState.selectedAgentId,
            selectedSessionIdByAgent: sessionState.selectedSessionIdByAgent,
            availableAgents: sessionState.availableAgents,
            projectSessionsByAgent: sessionState.projectSessionsByAgent,
            generalSessionsByAgent: sessionState.generalSessionsByAgent,
            pinnedSessions: sessionState.pinnedSessions,
            inflightSessionIds: taskState.inflightSessionIds,
            unreadSessionIds: sessionState.unreadSessionIds,
            sessionListFilter: sessionState.sessionListFilter,
            serviceStatus: viewModel.openclawService.status,
            serviceFailureReason: viewModel.openclawService.status == .running
                ? nil
                : viewModel.openclawService.lastError,
            serviceVersion: viewModel.openclawService.version,
            settingsShortcut: SettingsShortcutState(
                budgetSnapshots: viewModel.budgetSnapshots,
                billingSnapshot: billingSnapshot
            )
        )
    }

    private var sidebarActions: DashboardSidebarActions {
        DashboardSidebarActions(
            selectAgentChat: { agentId in
                viewModel.selectedAgentId = agentId
                viewModel.selectedTab = .chat
                if let visibleSession = viewModel.sessionState.selectedSessionIdByAgent[agentId] {
                    viewModel.sessionState.unreadSessionIds.remove(visibleSession)
                }
            },
            createNewSession: {
                viewModel.createNewSession()
                viewModel.selectedTab = .chat
            },
            openGlobalSessionSearch: openGlobalSessionSearch,
            selectTab: { tab in
                viewModel.selectedTab = tab
            },
            createSessionForAgent: { agentId in
                viewModel.createNewSession(forAgent: agentId)
                viewModel.selectedTab = .chat
            },
            createSessionForProject: { agentId, projectId in
                viewModel.createNewSession(forAgent: agentId, projectId: projectId)
                viewModel.selectedTab = .chat
            },
            switchSessionInAgent: { sessionId, agentId in
                viewModel.switchSession(to: sessionId, inAgent: agentId)
                viewModel.selectedTab = .chat
            },
            switchSessionGlobally: { sessionId in
                viewModel.switchSessionGlobally(to: sessionId)
                viewModel.selectedTab = .chat
            },
            togglePinSession: viewModel.togglePinSession,
            deleteSession: viewModel.deleteSession,
            archiveSession: viewModel.archiveSession,
            unarchiveSession: viewModel.unarchiveSession,
            setSessionListFilter: viewModel.setSessionListFilter,
            exportSession: viewModel.exportSession,
            toggleProjectCollapse: { agentId, projectId in
                viewModel.toggleProjectCollapse(agentId: agentId, projectId: projectId)
            },
            revealProjectInFinder: viewModel.revealProjectInFinder,
            removeProject: { projectId, agentId in
                viewModel.removeProject(projectId, fromAgent: agentId)
            },
            openProject: viewModel.openProject,
            requestCreateAgent: presentCreateAgentOverlay,
            requestRenameSession: beginSessionRename,
            openSettingsSection: openSettingsSection,
            removeAgent: removeAgentFromSidebar,
            loadSettingsShortcutData: preloadSettingsShortcutData
        )
    }

    private var activeTab: DashboardViewModel.DashboardTab {
        viewModel.selectedTab == .outputs ? .chat : viewModel.selectedTab
    }

    private var isChatTabActive: Bool {
        activeTab == .chat
    }

    private var currentSessionMetadata: ChatSessionMetadata? {
        guard let sessionId = sessionState.selectedSessionIdByAgent[sessionState.selectedAgentId] else {
            return nil
        }
        return (sessionState.sessionsByAgent[sessionState.selectedAgentId] ?? []).first { $0.id == sessionId }
    }

    @ViewBuilder
    private var sessionTitleToolbarChip: some View {
        DashboardSessionTitleToolbarChip(
            activeTab: activeTab,
            chatState: viewModel.chatState,
            sessionState: sessionState,
            onTapMessage: jumpToUserMessage
        )
    }

    private var hasWorkspaceDetailPanel: Bool {
        workspaceDetailWidth > 0
    }

    private func jumpToUserMessage(_ message: ChatMessage) {
        requestedUserMessageJumpId = message.id
    }

    private var isWorkspaceSidebarExpanded: Bool {
        isChatTabActive && (workspaceSidebarExpanded || hasWorkspaceDetailPanel)
    }

    private var shouldRetainWorkspaceSidebarContent: Bool {
        isChatTabActive && (workspaceSidebarExpanded || hasWorkspaceDetailPanel || isWorkspaceSidebarOpening || isWorkspaceSidebarClosing)
    }

    private var workspaceColumnIdealWidth: CGFloat {
        guard shouldRetainWorkspaceSidebarContent else { return 0 }
        return workspaceBrowserWidth + workspaceDetailWidth
    }

    private var workspaceColumnMaxWidth: CGFloat {
        workspaceSidebarMaxWidth + Self.workspaceLayoutMetrics.editorWidth
    }

    private var rightTitlebarAccessoryWidth: CGFloat {
        guard isChatTabActive else { return 0 }
        return 78
    }

    private var chromePolicy: DashboardChromePolicy {
        DashboardChromePolicy(
            presentationMode: presentationMode,
            isChatTabActive: isChatTabActive
        )
    }

    private var settingsSectionBinding: Binding<SettingsPageSection> {
        Binding(
            get: {
                presentationMode.settingsSection ?? .profile
            },
            set: { section in
                presentationMode = .settings(section)
            }
        )
    }

    private var rightInspectorContentUpdateID: AnyHashable {
        AnyHashable(RightInspectorContentUpdateID(
            selectedTab: viewModel.selectedTab,
            selectedAgentId: sessionState.selectedAgentId,
            terminalOpen: terminalOpen,
            terminalHeight: terminalHeight,
            marketplaceInstallRefreshID: marketplaceInstallRefreshID,
            requestedUserMessageJumpId: requestedUserMessageJumpId
        ))
    }

    private var activeWorkspaceRoot: WorkspaceSidebarRoot {
        if let projectId = currentSessionMetadata?.projectId,
           let project = viewModel.projectsById[projectId] {
            return WorkspaceSidebarRoot(
                displayName: project.displayName,
                path: project.rootPath,
                isProjectBound: true
            )
        }

        if let projectRoot = currentSessionMetadata?.projectRoot,
           !projectRoot.isEmpty {
            let displayName = currentSessionMetadata?.projectDisplayName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return WorkspaceSidebarRoot(
                displayName: displayName?.isEmpty == false ? displayName! : URL(fileURLWithPath: projectRoot).lastPathComponent,
                path: projectRoot,
                isProjectBound: true
            )
        }

        // Use the EFFECTIVE workspace (descends into <workspace>/main on
        // openclaw 2026.7.x) so the tree shows where deliverables actually land.
        let workspacePath = DashboardViewModel.effectiveAgentWorkspace(sessionState.selectedAgentId)
        return WorkspaceSidebarRoot(
            displayName: "Agent Workspace",
            path: workspacePath,
            isProjectBound: false
        )
    }

    private var selectedWorkspacePath: String {
        activeWorkspaceRoot.path
    }

    private var currentAgentWorkspacePath: String {
        DashboardViewModel.resolveAgentWorkspace(sessionState.selectedAgentId)
    }

    private var workspaceSidebarController: WorkspaceSidebarController {
        WorkspaceSidebarController(
            isExpanded: Binding(
                get: { isWorkspaceSidebarExpanded },
                set: { expanded in
                    if expanded {
                        revealWorkspaceSidebar()
                    } else {
                        hideWorkspaceSidebar(resetEditor: true)
                    }
                }
            ),
            hasEditor: hasWorkspaceDetailPanel,
            toggle: { toggleWorkspaceSidebar() }
        )
    }

    private func workspaceSidebarPane(width: CGFloat) -> some View {
        WorkspaceInspectorPane(
            root: activeWorkspaceRoot,
            browserWidth: min(workspaceBrowserWidth, width),
            editorWidth: Self.workspaceLayoutMetrics.editorWidth,
            onDetailWidthChanged: { detailWidth in
                workspaceDetailWidth = detailWidth
            },
            openFolder: openSelectedWorkspaceFolder,
            onCloseInspector: { hideWorkspaceSidebar(resetEditor: true) }
        )
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func toggleWorkspaceSidebar() {
        if isWorkspaceSidebarExpanded {
            hideWorkspaceSidebar(resetEditor: true)
        } else {
            revealWorkspaceSidebar()
        }
    }

    private func revealWorkspaceSidebar() {
        guard isChatTabActive else { return }
        guard !workspaceSidebarExpanded, !isWorkspaceSidebarOpening else { return }

        isWorkspaceSidebarClosing = false
        isWorkspaceSidebarOpening = true
        pendingWorkspaceSidebarCloseReset = false
        workspaceSidebarExpandRequestID += 1
    }

    private func hideWorkspaceSidebar(resetEditor: Bool) {
        guard shouldRetainWorkspaceSidebarContent else {
            if resetEditor {
                clearWorkspaceSidebarTransientState()
            }
            isWorkspaceSidebarOpening = false
            isWorkspaceSidebarClosing = false
            pendingWorkspaceSidebarCloseReset = false
            return
        }

        pendingWorkspaceSidebarCloseReset = pendingWorkspaceSidebarCloseReset || resetEditor
        if !isWorkspaceSidebarClosing {
            isWorkspaceSidebarOpening = false
            isWorkspaceSidebarClosing = true
            workspaceSidebarCollapseRequestID += 1
        }
    }

    private func completeWorkspaceSidebarOpen() {
        guard isWorkspaceSidebarOpening else { return }

        workspaceSidebarExpanded = true
        isWorkspaceSidebarOpening = false
        isWorkspaceSidebarClosing = false
        pendingWorkspaceSidebarCloseReset = false
    }

    private func completeWorkspaceSidebarClose() {
        guard isWorkspaceSidebarClosing else { return }

        let shouldReset = pendingWorkspaceSidebarCloseReset
        workspaceSidebarExpanded = false
        if shouldReset {
            clearWorkspaceSidebarTransientState()
        }
        pendingWorkspaceSidebarCloseReset = false
        isWorkspaceSidebarOpening = false
        isWorkspaceSidebarClosing = false
    }

    private func clearWorkspaceSidebarTransientState() {
        workspaceDetailWidth = 0
    }

    private func openSelectedWorkspaceFolder() {
        let workspaceURL = URL(fileURLWithPath: currentAgentWorkspacePath)
        try? FileManager.default.createDirectory(
            at: workspaceURL,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(workspaceURL)
    }

    private var isDark: Bool {
        AppAppearanceMode.storedValue(appAppearance).resolvesDark(using: colorScheme)
    }

    private var colorSchemeForAppearance: ColorScheme? {
        AppAppearanceMode.storedValue(appAppearance).preferredColorScheme
    }

    private func openGlobalSessionSearch() {
        globalSessionSearchText = ""
        isGlobalSessionSearchPresented = true
        DispatchQueue.main.async {
            isGlobalSessionSearchFocused = true
        }
    }

    private func presentCreateAgentOverlay() {
        isCreateAgentOverlayPresented = true
    }

    private func dismissCreateAgentOverlay() {
        isCreateAgentOverlayPresented = false
    }

    private func handleCreatedAgent(_ agentId: String) {
        viewModel.loadAvailableAgents()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                viewModel.selectedAgentId = agentId
                viewModel.selectedTab = .chat
            }
        }
    }

    private func removeAgentFromSidebar(_ agentId: String) {
        Task {
            let deleted = await createAgentVM.deleteAgent(agentId: agentId)
            await MainActor.run {
                if deleted {
                    viewModel.loadAvailableAgents()
                    viewModel.removeDeletedAgentState(agentId: agentId)
                } else {
                    viewModel.errorMessage = createAgentVM.lastActionError ?? "Failed to remove agent \(agentId)"
                    viewModel.showError = true
                }
            }
        }
    }

    private var globalSearchResults: [ChatSessionMetadata] {
        Array(viewModel.chatSessionStore
            .searchSessions(query: globalSessionSearchText)
            .prefix(12))
    }

    private var createAgentOverlay: some View {
        GeometryReader { proxy in
            let panelWidth = min(460, max(360, proxy.size.width - 64))

            ZStack {
                Color.black.opacity(isDark ? 0.24 : 0.12)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissCreateAgentOverlay()
                    }

                CreateAgentSheet(
                    viewModel: createAgentVM,
                    isPresented: Binding(
                        get: { isCreateAgentOverlayPresented },
                        set: { newValue in
                            if newValue {
                                isCreateAgentOverlayPresented = true
                            } else {
                                dismissCreateAgentOverlay()
                            }
                        }
                    ),
                    onCreatedWithId: { agentId in
                        handleCreatedAgent(agentId)
                    }
                )
                .frame(width: panelWidth)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(isDark ? 0.10 : 0.06), lineWidth: 1)
                )
                .shadow(color: .black.opacity(isDark ? 0.34 : 0.16), radius: 32, x: 0, y: 20)
                .onTapGesture {}
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
    }

    private func beginSessionRename(_ meta: ChatSessionMetadata) {
        viewModel.switchSessionGlobally(to: meta.id)
        viewModel.selectedTab = .chat
        sessionRenameDraft = meta.title
        sessionRenamePresentation = SessionRenamePresentation(id: meta.id)
        DispatchQueue.main.async {
            isSessionRenameFocused = true
        }
    }

    private func saveSessionRename() {
        guard let presentation = sessionRenamePresentation else { return }
        viewModel.renameSession(presentation.id, to: sessionRenameDraft)
        dismissSessionRename()
    }

    private func dismissSessionRename() {
        sessionRenamePresentation = nil
        sessionRenameDraft = ""
        isSessionRenameFocused = false
    }

    private var sessionRenameOverlay: some View {
        GeometryReader { proxy in
            let panelWidth = min(420, max(320, proxy.size.width - 64))
            let canSave = !sessionRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let snowSurface = Color(red: 0.965, green: 0.973, blue: 0.955)
            let snowFieldSurface = Color(red: 0.925, green: 0.936, blue: 0.912)
            let snowText = Color(red: 0.10, green: 0.12, blue: 0.10)
            let snowSecondaryText = Color(red: 0.42, green: 0.44, blue: 0.40)

            DashboardModalOverlay(
                isDismissDisabled: false,
                scrimOpacity: isDark ? 0.28 : 0.16,
                verticalOffset: -44,
                onDismiss: dismissSessionRename
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(String(localized: "Rename chat", bundle: languageManager.localizedBundle))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(snowText)

                        Spacer()

                        Button {
                            dismissSessionRename()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(snowSecondaryText)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help(I18n.t("catalog.action.close"))
                    }

                    Text(String(localized: "Keep it short and recognizable", bundle: languageManager.localizedBundle))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(snowSecondaryText)

                    TextField(String(localized: "Chat name", bundle: languageManager.localizedBundle), text: $sessionRenameDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(snowText)
                        .focused($isSessionRenameFocused)
                        .onSubmit {
                            if canSave {
                                saveSessionRename()
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(snowFieldSurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.black.opacity(0.10), lineWidth: 1)
                        )

                    HStack(spacing: 10) {
                        Spacer()

                        Button(String(localized: "Cancel", bundle: languageManager.localizedBundle), role: .cancel) {
                            dismissSessionRename()
                        }
                        .keyboardShortcut(.cancelAction)

                        Button(String(localized: "Save", bundle: languageManager.localizedBundle)) {
                            saveSessionRename()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave)
                    }
                    .padding(.top, 2)
                }
                .padding(20)
                .frame(width: panelWidth, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            isDark
                                ? snowSurface.opacity(0.94)
                                : snowSurface
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(isDark ? 0.16 : 0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(isDark ? 0.36 : 0.18), radius: 34, x: 0, y: 22)
                .onTapGesture {}
                .onExitCommand {
                    dismissSessionRename()
                }
            }
        }
    }

    private func openSettingsSection(_ section: SettingsPageSection) {
        presentationMode = .settings(section)
    }

    private func closeSettingsPage() {
        presentationMode = .app
    }

    private func preloadSettingsShortcutData() async {
        if viewModel.budgetSnapshots.isEmpty {
            await viewModel.loadBudgets()
        }
        #if REQUIRE_LOGIN
        if viewModel.membershipManager?.keysBilling.isEmpty != false {
            await viewModel.loadKeysBilling()
        }
        SettingsShortcutBillingSnapshot.persistCurrentRemoteValue(
            from: viewModel.membershipManager,
            cacheIdentity: authManager.userId ?? authManager.userEmail
        )
        #endif
    }

    private var shouldShowMarketplaceDetailOverlay: Bool {
        viewModel.selectedTab == .market
    }

    private func presentMarketplaceDetail(_ agent: MarketplaceAgent) {
        guard !viewModel.isRecruitingMarketplaceAgent else { return }
        withAnimation(marketplaceDetailAnimation) {
            viewModel.selectedMarketplaceAgent = agent
        }
    }

    private func dismissMarketplaceDetail() {
        guard !viewModel.isRecruitingMarketplaceAgent else { return }
        withAnimation(marketplaceDetailAnimation) {
            viewModel.selectedMarketplaceAgent = nil
        }
    }

    private func marketplaceDetailOverlay(for agent: MarketplaceAgent) -> some View {
        DashboardModalOverlay(
            isDismissDisabled: viewModel.isRecruitingMarketplaceAgent,
            onDismiss: dismissMarketplaceDetail
        ) {
            MarketplaceDetailView(
                agent: agent,
                openclawService: viewModel.openclawService,
                onInstalled: { _ in
                    viewModel.loadAvailableAgents()
                    marketplaceInstallRefreshID += 1
                },
                onClose: dismissMarketplaceDetail,
                onDismissDisabledChange: { disabled in
                    viewModel.isRecruitingMarketplaceAgent = disabled
                }
            )
            .id(agent.id)
        }
    }

    private var globalSessionSearchOverlay: some View {
        GeometryReader { proxy in
            let panelWidth = min(700, max(320, proxy.size.width - 64))

            ZStack {
                Color.black.opacity(isDark ? 0.28 : 0.16)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isGlobalSessionSearchPresented = false
                        isGlobalSessionSearchFocused = false
                    }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)
                        TextField(String(localized: "Search chats", bundle: languageManager.localizedBundle), text: $globalSessionSearchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 20, weight: .regular))
                            .tint(Color(NSColor.labelColor))
                            .focused($isGlobalSessionSearchFocused)
                        if !globalSessionSearchText.isEmpty {
                            Button {
                                globalSessionSearchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("common.action.clear", fallback: "Clear")))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)

                    Text(globalSessionSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? String(localized: "Recent chats", bundle: languageManager.localizedBundle)
                         : String(localized: "Search results", bundle: languageManager.localizedBundle))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)

                    if globalSearchResults.isEmpty {
                        Text(String(localized: "No matches", bundle: languageManager.localizedBundle))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 18)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(Array(globalSearchResults.enumerated()), id: \.element.id) { index, meta in
                                    globalSessionSearchRow(meta: meta, shortcutIndex: index + 1)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.bottom, 12)
                        }
                        .frame(maxHeight: 420)
                    }
                }
                .frame(width: panelWidth, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.primary.opacity(isDark ? 0.10 : 0.06), lineWidth: 1)
                )
                .shadow(color: .black.opacity(isDark ? 0.36 : 0.18), radius: 38, x: 0, y: 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
    }

    private func globalSessionSearchRow(meta: ChatSessionMetadata, shortcutIndex: Int) -> some View {
        Button {
            viewModel.switchSessionGlobally(to: meta.id)
            viewModel.selectedTab = .chat
            isGlobalSessionSearchPresented = false
            isGlobalSessionSearchFocused = false
        } label: {
            HStack(spacing: 12) {
                Text(meta.title.isEmpty ? String(localized: "New chat", bundle: languageManager.localizedBundle) : meta.title)
                    .font(.system(size: 15, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(.primary)

                Spacer(minLength: 12)

                Text(agentName(for: meta.agentId))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text("⌘\(shortcutIndex)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.75))
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.42))
            )
        }
        .buttonStyle(.plain)
    }

    private func agentName(for agentId: String) -> String {
        viewModel.availableAgents.first(where: { $0.id == agentId })?.name ?? agentId
    }
}

private struct TitlebarSeparatorSuppressor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            Self.configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            Self.configure(window: nsView.window)
        }
    }

    private static func configure(window: NSWindow?) {
        window?.titlebarSeparatorStyle = .none
    }
}

// MARK: - Sidebar


struct WorkspaceSidebarController {
    var isExpanded: Binding<Bool>
    var hasEditor: Bool
    var toggle: () -> Void
}

struct WorkspaceSidebarControllerKey: EnvironmentKey {
    static let defaultValue = WorkspaceSidebarController(
        isExpanded: .constant(false),
        hasEditor: false,
        toggle: {}
    )
}

extension EnvironmentValues {
    var workspaceSidebarController: WorkspaceSidebarController {
        get { self[WorkspaceSidebarControllerKey.self] }
        set { self[WorkspaceSidebarControllerKey.self] = newValue }
    }
}

private struct DetailContentView: View {
    @ObservedObject var viewModel: DashboardViewModel
    let workspaceSidebarController: WorkspaceSidebarController
    @Binding var requestedUserMessageJumpId: UUID?
    @Binding var terminalOpen: Bool
    @Binding var terminalHeight: CGFloat
    let marketplaceInstallRefreshID: Int
    let onOpenMarketplaceDetail: (MarketplaceAgent) -> Void
    @State private var fallbackSettingsSection: SettingsPageSection = .profile
    @State private var collabPanelWidth: CGFloat = 320
    @State private var dragStartWidth: CGFloat = 320

    private let collabPanelMinWidth: CGFloat = 220
    private let collabPanelMaxWidth: CGFloat = 500
    private let collabCollapsedWidth: CGFloat = 24

    private var activeTab: DashboardViewModel.DashboardTab {
        viewModel.selectedTab == .outputs ? .chat : viewModel.selectedTab
    }

    var body: some View {
        HStack(spacing: 0) {
            // Collab panel (left column)
            if viewModel.showCollabPanel {
                if viewModel.collabPanelCollapsed {
                    // Collapsed strip
                    collabCollapsedStrip
                } else {
                    // Panel + drag handle
                    collabPanelContent
                        .frame(width: collabPanelWidth)
                    collabDragHandle
                }
            }

            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: viewModel.selectedTab) { newTab in
            // Only reload agents when entering chat tab, but preserve current agent selection
            if newTab == .chat {
                // Re-entering chat makes the selected session visible again —
                // its unread dot (if any) is now seen.
                if let visibleSession = viewModel.sessionState.selectedSessionIdByAgent[viewModel.selectedAgentId] {
                    viewModel.sessionState.unreadSessionIds.remove(visibleSession)
                }
                let currentAgent = viewModel.selectedAgentId
                let msgCount = viewModel.chatMessages.count
                print("[TAB_CHANGE] Switching to Chat: currentAgent=\(currentAgent), msgCount=\(msgCount)")
                viewModel.loadAvailableAgents()
                // Restore the previously selected agent if it still exists
                if viewModel.availableAgents.contains(where: { $0.id == currentAgent }) {
                    viewModel.selectedAgentId = currentAgent
                    print("[TAB_CHANGE] Restored agent: \(currentAgent), newMsgCount=\(viewModel.chatMessages.count)")
                }
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ZStack {
            // ChatView stays alive — hidden when not active to preserve WKWebView instances.
            // sidebarMode is being phased out; selectedTab == .chat is the canonical signal now.
            let showChat = activeTab == .chat
            ChatView(
                viewModel: viewModel,
                requestedUserMessageJumpId: $requestedUserMessageJumpId,
                terminalOpen: $terminalOpen,
                terminalHeight: $terminalHeight,
                hideAgentPicker: false
            )
                .environment(\.workspaceSidebarController, workspaceSidebarController)
                .opacity(showChat ? 1 : 0)
                .allowsHitTesting(showChat)

            if !showChat {
                Group {
                    switch activeTab {
                    case .chat:
                        EmptyView()
                    case .status:
                        StatusTabView(viewModel: viewModel)
                    case .budget:
                        BudgetTabView(viewModel: viewModel)
                    case .billing:
                        #if REQUIRE_LOGIN
                        if let mm = viewModel.membershipManager {
                            BillingTabView(viewModel: viewModel, membershipManager: mm)
                        } else {
                            Text(I18n.t("billing.loginRequired"))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        #else
                        Text(I18n.t("billing.unavailable"))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        #endif
                    case .persona:
                        PersonaTabView()
                    case .subAgents:
                        SubAgentsTabView(openclawService: viewModel.openclawService)
                    case .market:
                        MarketplaceView(
                            selectedAgent: viewModel.selectedMarketplaceAgent,
                            installRefreshID: marketplaceInstallRefreshID,
                            onSelectAgent: onOpenMarketplaceDetail
                        )
                    case .tasksLogs:
                        TasksLogsTabView(viewModel: viewModel)
                    case .config:
                        SettingsShellView(
                            viewModel: viewModel,
                            selectedSection: $fallbackSettingsSection,
                            onBackToApp: {
                                viewModel.selectedTab = .chat
                            }
                        )
                    case .skills:
                        SkillsTabView(
                            openclawService: viewModel.openclawService,
                            notifySuccess: viewModel.showSuccessMessage,
                            notifyError: viewModel.showErrorMessage
                        )
                    case .models:
                        ModelsTabView(viewModel: viewModel)
                    case .outputs:
                        EmptyView()
                    case .channels:
                        ChannelsTabView(viewModel: viewModel)
                    case .plugins:
                        PluginsTabView(
                            openclawService: viewModel.openclawService,
                            notifySuccess: viewModel.showSuccessMessage,
                            notifyError: viewModel.showErrorMessage
                        )
                    case .cron:
                        CronTabView(viewModel: viewModel)
                    case .logs:
                        LogsTabView(viewModel: viewModel)
                    }
                }
            }
        }
    }

    // MARK: - Collab Panel

    private var collabDragHandle: some View {
        CollabDragHandleView()
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let newWidth = dragStartWidth + value.translation.width
                        collabPanelWidth = min(max(newWidth, collabPanelMinWidth), collabPanelMaxWidth)
                    }
                    .onEnded { _ in
                        dragStartWidth = collabPanelWidth
                    }
            )
    }

    private var collabPanelContent: some View {
        VStack(spacing: 0) {
            if let collabVM = viewModel.collabViewModel {
                CollabWindowView(
                    viewModel: collabVM,
                    onCollapse: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.collabPanelCollapsed = true
                        }
                    },
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.showCollabPanel = false
                        }
                    }
                )
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(String(localized: "No collaboration tasks", bundle: LanguageManager.shared.localizedBundle))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var collabCollapsedStrip: some View {
        VStack {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.collabPanelCollapsed = false
                }
            }) {
                VStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 12))
                    // Show progress count if available
                    if let collabVM = viewModel.collabViewModel, collabVM.totalCount > 0 {
                        Text("\(collabVM.completedCount)/\(collabVM.totalCount)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                }
                .foregroundColor(.secondary)
                .frame(width: collabCollapsedWidth)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 1),
            alignment: .trailing
        )
    }
}

// MARK: - Collab Drag Handle (NSView-based cursor)

/// Uses NSView's resetCursorRects for stable resize cursor without onHover feedback loops.
private struct CollabDragHandleView: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeCursorView {
        let view = ResizeCursorView()
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }
    func updateNSView(_ nsView: ResizeCursorView, context: Context) {}

    class ResizeCursorView: NSView {
        override var intrinsicContentSize: NSSize {
            NSSize(width: 5, height: NSView.noIntrinsicMetric)
        }
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }
        override func draw(_ dirtyRect: NSRect) {
            // Background
            NSColor.gray.withAlphaComponent(0.08).setFill()
            dirtyRect.fill()
            // Center divider line
            let lineX = (bounds.width - 1) / 2
            let lineRect = NSRect(x: lineX, y: 0, width: 1, height: bounds.height)
            NSColor.separatorColor.setFill()
            lineRect.fill()
        }
    }
}

// MARK: - Slash Command Model

// MARK: - Success Toast

struct SuccessToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 20))

            Text(message)
                .font(.body)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        )
    }
}

// MARK: - Diagnostics Sheet

struct DiagnosticsSheet: View {
    let report: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(I18n.t("dashboard.diagnostics.title"))
                    .font(.headline)

                Spacer()

                Button(I18n.t("catalog.action.close")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            // Report content
            ScrollView {
                Text(report)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - Brand Text

struct BrandTextView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            Text("GetClaw")
                .foregroundColor(colorScheme == .dark ? .white : .black)
            Text("Hub")
                .foregroundColor(.red)
        }
        .font(.title2)
        .fontWeight(.bold)
    }
}

// MARK: - Input Mode Picker (above the chat input area)

/// Three-mode segmented picker matching the redesign: 聊天 / 执行任务 /
/// 代码模式.
///
/// **Currently hidden** (v1.1.46+). The three modes were never wired into
/// `sendMessage()` — they only changed the picker highlight. Shipping a UI
/// control that pretends to switch behavior but doesn't was misleading, so
/// the picker is removed from the input toolbar. The enum + view stay in
/// the codebase as a placeholder for the eventual wiring: each mode should
/// inject a prompt prefix and/or change the agent invocation flags before
/// `sendMessage()` runs.
enum ChatInputMode: String, CaseIterable {
    case chat
    case task
    case code

    var localizedLabel: String {
        switch self {
        case .chat: return I18n.t("dashboard.composer.mode.chat")
        case .task: return I18n.t("dashboard.composer.mode.task")
        case .code: return I18n.t("dashboard.composer.mode.code")
        }
    }

    var icon: String {
        switch self {
        case .chat: return "message"
        case .task: return "terminal.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct ChatInputModePicker: View {
    @Binding var mode: ChatInputMode

    var body: some View {
        HStack(spacing: 6) {
            Text(I18n.t("dashboard.composer.mode.label"))
                .font(.caption)
                .foregroundColor(.secondary)
            ForEach(ChatInputMode.allCases, id: \.self) { m in
                Button {
                    mode = m
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: m.icon)
                            .font(.system(size: 10))
                        Text(m.localizedLabel)
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(mode == m ? Color.accentColor.opacity(0.15) : Color.clear)
                    )
                    .foregroundColor(mode == m ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}

// MARK: - Automation Tab

/// Shows scheduled automation jobs. Gateway logs are intentionally not shown
/// in this primary workflow.
struct TasksLogsTabView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        CronTabView(viewModel: viewModel)
    }
}

