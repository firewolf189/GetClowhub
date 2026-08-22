import SwiftUI
import SwiftTerm
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

// MARK: - Agent Settings Panel

struct AgentSettingsPanel: View {
    @ObservedObject var viewModel: DashboardViewModel
    let agent: SubAgentInfo
    let onClose: () -> Void

    @State private var selectedModel: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                AgentAvatarImage(size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.headline)
                    Text(agent.id)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color(NSColor.windowBackgroundColor))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Info section
                        VStack(alignment: .leading, spacing: 6) {
                            // Model picker
                            HStack(spacing: 6) {
                                Image(systemName: "cpu")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(I18n.t("dashboard.model.label")):")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
	                                Picker("", selection: $selectedModel) {
	                                    Text(I18n.t("dashboard.model.defaultInherit")).tag("")
	                                    ForEach(viewModel.availableModelsForSettings) { model in
	                                        Text(model.name).tag(model.runtimeId)
	                                    }
	                                }
                                .labelsHidden()
                                .controlSize(.small)
                                .frame(maxWidth: 260)
                                .onChange(of: selectedModel) { newValue in
                                    if newValue != agent.model {
                                        viewModel.updateAgentModel(model: newValue)
                                    }
                                }
                            }

                            // Workspace path (clickable → open in Finder)
                            if !agent.workspace.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(agent.workspace.replacingOccurrences(
                                        of: FileManager.default.homeDirectoryForCurrentUser.path,
                                        with: "~"
                                    ))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    NSWorkspace.shared.open(URL(fileURLWithPath: agent.workspace))
                                }
                                .onHover { inside in
                                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                }
                            }

                            // Binding details
                            if !agent.bindingDetails.isEmpty {
                                ForEach(agent.bindingDetails, id: \.self) { binding in
                                    HStack(spacing: 6) {
                                        Image(systemName: "link")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(binding)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        Divider()

                        // Persona editors (collapsed by default)
                        VStack(alignment: .leading, spacing: 12) {
                            MarkdownFileEditor(
                                title: "IDENTITY.md",
                                icon: "person.crop.circle",
                                content: viewModel.settingsBinding(for: .identity),
                                isDirty: viewModel.selectedAgentDetail?.identityDirty ?? false,
                                onSave: {
                                    viewModel.saveAgentPersonaFile(file: .identity)
                                },
                                initiallyExpanded: false
                            )

                            MarkdownFileEditor(
                                title: "SOUL.md",
                                icon: "heart.fill",
                                content: viewModel.settingsBinding(for: .soul),
                                isDirty: viewModel.selectedAgentDetail?.soulDirty ?? false,
                                onSave: {
                                    viewModel.saveAgentPersonaFile(file: .soul)
                                },
                                initiallyExpanded: false
                            )

                            MarkdownFileEditor(
                                title: "MEMORY.md",
                                icon: "brain.head.profile",
                                content: viewModel.settingsBinding(for: .memory),
                                isDirty: viewModel.selectedAgentDetail?.memoryDirty ?? false,
                                onSave: {
                                    viewModel.saveAgentPersonaFile(file: .memory)
                                },
                                initiallyExpanded: false
                            )

                            // Additional .md files — only shown when present in workspace
                            if viewModel.hasPersonaFile("USER.md") {
                                MarkdownFileEditor(
                                    title: "USER.md",
                                    icon: "person.fill",
                                    content: viewModel.settingsBindingByName("USER.md"),
                                    isDirty: viewModel.isFileDirtyByName("USER.md"),
                                    onSave: { viewModel.savePersonaFileByName("USER.md") },
                                    initiallyExpanded: false
                                )
                            }

                            if viewModel.hasPersonaFile("AGENTS.md") {
                                MarkdownFileEditor(
                                    title: "AGENTS.md",
                                    icon: "person.3.fill",
                                    content: viewModel.settingsBindingByName("AGENTS.md"),
                                    isDirty: viewModel.isFileDirtyByName("AGENTS.md"),
                                    onSave: { viewModel.savePersonaFileByName("AGENTS.md") },
                                    initiallyExpanded: false
                                )
                            }

                            if viewModel.hasPersonaFile("BOOTSTRAP.md") {
                                MarkdownFileEditor(
                                    title: "BOOTSTRAP.md",
                                    icon: "power",
                                    content: viewModel.settingsBindingByName("BOOTSTRAP.md"),
                                    isDirty: viewModel.isFileDirtyByName("BOOTSTRAP.md"),
                                    onSave: { viewModel.savePersonaFileByName("BOOTSTRAP.md") },
                                    initiallyExpanded: false
                                )
                            }

                            if viewModel.hasPersonaFile("HEARTBEAT.md") {
                                MarkdownFileEditor(
                                    title: "HEARTBEAT.md",
                                    icon: "heart.text.clipboard",
                                    content: viewModel.settingsBindingByName("HEARTBEAT.md"),
                                    isDirty: viewModel.isFileDirtyByName("HEARTBEAT.md"),
                                    onSave: { viewModel.savePersonaFileByName("HEARTBEAT.md") },
                                    initiallyExpanded: false
                                )
                            }

                            if viewModel.hasPersonaFile("TOOLS.md") {
                                MarkdownFileEditor(
                                    title: "TOOLS.md",
                                    icon: "wrench.and.screwdriver",
                                    content: viewModel.settingsBindingByName("TOOLS.md"),
                                    isDirty: viewModel.isFileDirtyByName("TOOLS.md"),
                                    onSave: { viewModel.savePersonaFileByName("TOOLS.md") },
                                    initiallyExpanded: false
                                )
                            }
                        }
                        .padding(16)
                    }
                }
        }
        .frame(width: 380)
        // Contrast against the chat area's windowBackgroundColor so the
        // drawer reads as a clearly separate panel — without this, the
        // drawer and chat were the same surface and felt borderless.
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .leading) {
            // Crisp 1px divider on the leading edge so the boundary is
            // unambiguous even when shadow is muted in light mode.
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 6, x: -2, y: 0)
        .onAppear {
            selectedModel = agent.model
        }
    }
}

// MARK: - Workspace File Panel

private struct OutputsTabView: View {
    let agentId: String
    @State private var refreshId = UUID()

    private var workspacePath: String {
        let base = NSString("~/.openclaw").expandingTildeInPath
        if agentId == "main" {
            return (base as NSString).appendingPathComponent("workspace")
        }
        return (base as NSString).appendingPathComponent("workspace-\(agentId)")
    }

    private var outputItems: [URL] {
        let root = URL(fileURLWithPath: workspacePath, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let excludedNames: Set<String> = [
            "IDENTITY.md", "SOUL.md", "MEMORY.md", "USER.md",
            "AGENTS.md", "BOOTSTRAP.md", "HEARTBEAT.md", "TOOLS.md"
        ]

        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            let name = url.lastPathComponent
            if excludedNames.contains(name) { return nil }
            if name.hasPrefix(".") { return nil }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true { return nil }
            return url
        }
        .sorted { lhs, rhs in
            let lDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lDate > rDate
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(I18n.t("dashboard.outputs.title"))
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
                Button {
                    refreshId = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("common.action.refresh", fallback: "Refresh")))
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: workspacePath))
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .buttonStyle(.plain)
                .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("dashboard.tooltip.openOutputsFolder")))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Divider()

            if outputItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(I18n.t("dashboard.outputs.empty"))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(outputItems, id: \.path) { url in
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: iconName(for: url))
                                .foregroundColor(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                    .foregroundColor(.primary)
                                Text(relativePath(for: url))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .id(refreshId)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func relativePath(for url: URL) -> String {
        url.path.replacingOccurrences(of: workspacePath + "/", with: "")
    }

    private func iconName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic": return "photo"
        case "mp4", "mov", "webm": return "film"
        case "md", "txt", "json", "csv", "xml", "yaml", "yml": return "doc.text"
        default: return "doc"
        }
    }
}


// MARK: - Terminal Panel

struct TerminalPanelView: View {
    let workspacePath: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(I18n.t("dashboard.terminal.title"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            SwiftTermView(workspacePath: workspacePath)
        }
        .background(Color(NSColor.textBackgroundColor))
    }
}

private struct SwiftTermView: NSViewRepresentable {
    let workspacePath: String

    func makeNSView(context: Context) -> SwiftTerm.LocalProcessTerminalView {
        let tv = SwiftTerm.LocalProcessTerminalView(frame: .zero)
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let cwd: String
        if !workspacePath.isEmpty, FileManager.default.fileExists(atPath: workspacePath) {
            cwd = workspacePath
        } else {
            cwd = FileManager.default.homeDirectoryForCurrentUser.path
        }
        tv.startProcess(executable: shell, args: [], environment: nil, execName: nil, currentDirectory: cwd)
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        return tv
    }

    func updateNSView(_ nsView: SwiftTerm.LocalProcessTerminalView, context: Context) {}
}

struct TerminalDragHandle: View {
    @Binding var height: CGFloat
    @State private var dragStart: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 4)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStart == nil { dragStart = height }
                        let newHeight = (dragStart ?? height) - value.translation.height
                        height = min(max(newHeight, 80), 500)
                    }
                    .onEnded { _ in dragStart = nil }
            )
    }
}

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

