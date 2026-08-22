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

struct SlashCommand: Identifiable {
    let id: String  // e.g. "/help"
    let name: String
    let description: String
    let hasParam: Bool
}

private let slashCommands: [SlashCommand] = [
    // Core
    SlashCommand(id: "/help",       name: "/help",       description: "Show help",               hasParam: false),
    SlashCommand(id: "/status",     name: "/status",     description: "View session status",      hasParam: false),
    SlashCommand(id: "/agent",      name: "/agent",      description: "Switch agent",             hasParam: true),
    SlashCommand(id: "/agents",     name: "/agents",     description: "List agents",              hasParam: false),
    SlashCommand(id: "/session",    name: "/session",    description: "Switch session",           hasParam: true),
    SlashCommand(id: "/sessions",   name: "/sessions",   description: "List sessions",            hasParam: false),
    SlashCommand(id: "/model",      name: "/model",      description: "Switch model",             hasParam: true),
    SlashCommand(id: "/models",     name: "/models",     description: "List models",              hasParam: false),
    // Session control
    SlashCommand(id: "/think",      name: "/think",      description: "Set thinking level",       hasParam: true),
    SlashCommand(id: "/verbose",    name: "/verbose",    description: "Verbose output mode",      hasParam: true),
    SlashCommand(id: "/reasoning",  name: "/reasoning",  description: "Reasoning mode toggle",    hasParam: true),
    SlashCommand(id: "/usage",      name: "/usage",      description: "Usage display mode",       hasParam: true),
    SlashCommand(id: "/elevated",   name: "/elevated",   description: "Elevated permission mode", hasParam: true),
    SlashCommand(id: "/activation", name: "/activation", description: "Activation mode",          hasParam: true),
    SlashCommand(id: "/deliver",    name: "/deliver",    description: "Message delivery toggle",  hasParam: true),
    // Session lifecycle
    SlashCommand(id: "/new",        name: "/new",        description: "Reset session",            hasParam: false),
    SlashCommand(id: "/reset",      name: "/reset",      description: "Reset session",            hasParam: false),
    SlashCommand(id: "/abort",      name: "/abort",      description: "Abort current run",        hasParam: false),
    SlashCommand(id: "/settings",   name: "/settings",   description: "Open settings",            hasParam: false),
    SlashCommand(id: "/exit",       name: "/exit",       description: "Exit app",                 hasParam: false),
    // Skills
    SlashCommand(id: "/skills",     name: "/skills",     description: "Use a skill",              hasParam: true),
    // Collab
    SlashCommand(id: "/collab",     name: "/collab",     description: "Multi-agent collab task",   hasParam: true),
]

struct PendingComposerMessage: Identifiable, Equatable {
    let id: UUID
    var text: String
    var attachments: [URL]

    init(id: UUID = UUID(), text: String, attachments: [URL] = []) {
        self.id = id
        self.text = text
        self.attachments = attachments
    }
}

private enum ChatAutoScrollMode: Equatable {
    case followingBottom
    case userDetached
    case sessionJumping
}

private struct ChatScrollIntentObserver: NSViewRepresentable {
    let onScrollPositionChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrollPositionChange: onScrollPositionChange)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onScrollPositionChange = onScrollPositionChange

        DispatchQueue.main.async {
            guard let scrollView = Self.nearestScrollView(from: nsView) else { return }
            context.coordinator.attach(to: scrollView)
        }
    }

    private static func nearestScrollView(from view: NSView) -> NSScrollView? {
        var current: NSView? = view
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView {
                return scrollView
            }
            if let scrollView = candidate.enclosingScrollView {
                return scrollView
            }
            current = candidate.superview
        }
        return nil
    }

    final class Coordinator {
        var onScrollPositionChange: (Bool) -> Void
        private weak var scrollView: NSScrollView?
        private var observer: NSObjectProtocol?

        init(onScrollPositionChange: @escaping (Bool) -> Void) {
            self.onScrollPositionChange = onScrollPositionChange
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func attach(to scrollView: NSScrollView) {
            guard self.scrollView !== scrollView else {
                reportPosition(in: scrollView)
                return
            }

            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }

            self.scrollView = scrollView
            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let scrollView else { return }
                self?.reportPosition(in: scrollView)
            }

            reportPosition(in: scrollView)
        }

        private func reportPosition(in scrollView: NSScrollView) {
            guard let documentView = scrollView.documentView else {
                onScrollPositionChange(true)
                return
            }

            scrollView.layoutSubtreeIfNeeded()
            documentView.layoutSubtreeIfNeeded()

            let clipView = scrollView.contentView
            let documentHeight = documentView.bounds.height
            let viewportHeight = clipView.bounds.height
            guard documentHeight > viewportHeight + 1 else {
                onScrollPositionChange(true)
                return
            }

            let offsetY = clipView.bounds.origin.y
            let distanceToBottom: CGFloat
            if documentView.isFlipped {
                let maxOffset = max(0, documentHeight - viewportHeight)
                distanceToBottom = maxOffset - offsetY
            } else {
                distanceToBottom = offsetY
            }

            onScrollPositionChange(distanceToBottom <= 24)
        }
    }
}

// MARK: - Chat View

struct ChatView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var chatState: ChatRuntimeState
    @ObservedObject var taskState: TaskActivityState
    @ObservedObject var sessionState: SessionNavigationState
    @Binding var requestedUserMessageJumpId: UUID?
    @Binding var terminalOpen: Bool
    @Binding var terminalHeight: CGFloat
    var hideAgentPicker: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var inputText = ""
    // The `ChatInputMode` picker (聊天/执行任务/代码模式) used to live here
    // but was hidden in v1.1.46 — see the toolbar row below and the
    // `ChatInputModePicker` definition for the disabled state's reasoning.
    @State private var eventMonitor: Any?
    @State private var queryHistory: [String] = UserDefaults.standard.stringArray(forKey: "chatQueryHistory") ?? []
    @State private var historyIndex: Int = -1
    // Slash command autocomplete
    @State private var slashSelectedIndex: Int = 0
    @FocusState private var isInputFocused: Bool
    @State private var focusMonitor: Any?
    // Skills panel
    @State private var skillsSelectedIndex: Int = 0
    @State private var skillJustSelected: Bool = false
    // @ Agent mention panel
    @State private var agentSelectedIndex: Int = 0
    @State private var agentJustSelected: Bool = false
    // Composer model selector
    @State private var showComposerSelector = false
    // File attachments
    @State private var attachedFiles: [URL] = []
    // Scroll debounce for streaming content
    @State private var scrollDebounceWork: DispatchWorkItem?
    // Smart scroll: follow only while the user is reading the latest messages.
    @State private var chatAutoScrollMode: ChatAutoScrollMode = .followingBottom
    @State private var chatScrollIsAtBottom = true
    @State private var scheduledBottomScrollGeneration = 0
    @State private var scrollEventMonitor: Any?
    // Store ScrollViewProxy so sendMessage() can scroll to bottom
    @State private var chatScrollProxy: ScrollViewProxy?
    @State private var highlightedMessageId: UUID?
    @State private var highlightedMessageFlashOn = false
    // Memoizes the timeline rows; rebuilding them per render amplified the
    // 2026-07-21 layout livelock (see ChatTimelineSnapshotCache).
    @State private var timelineSnapshotCache = ChatTimelineSnapshotCache()
    /// Tail-window paging for history sessions, keyed by session id. Entering
    /// a session renders only the last `historyTailWindow` messages (each
    /// assistant row is an NSTextView that lays out synchronously on insert —
    /// unbounded batches caused the long white screen on switch); "load
    /// earlier" grows the window by `historyTailPageSize`.
    @State private var historyTailLimitBySession: [UUID: Int] = [:]
    private static let historyTailWindow = 30
    private static let historyTailPageSize = 100
    @State private var highlightFlashTask: Task<Void, Never>?
    // Create agent sheet
    @State private var showCreateAgentSheet = false
    @StateObject private var createAgentVM: SubAgentsViewModel
    @State private var pendingComposerMessagesBySession: [UUID: [PendingComposerMessage]] = [:]
    @State private var renderObservationStartBySession: [UUID: ContinuousClock.Instant] = [:]
    private static let layoutMetrics = OutputsSidebarLayoutMetrics()
    private static let emptyChatContentYOffset: CGFloat = -48
    private let composerEditorHeight: CGFloat = 76
    private let composerSuggestionPanelMaxHeight: CGFloat = 184

    init(
        viewModel: DashboardViewModel,
        requestedUserMessageJumpId: Binding<UUID?> = .constant(nil),
        terminalOpen: Binding<Bool> = .constant(false),
        terminalHeight: Binding<CGFloat> = .constant(120),
        hideAgentPicker: Bool = false
    ) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._chatState = ObservedObject(wrappedValue: viewModel.chatState)
        self._taskState = ObservedObject(wrappedValue: viewModel.taskState)
        self._sessionState = ObservedObject(wrappedValue: viewModel.sessionState)
        self._requestedUserMessageJumpId = requestedUserMessageJumpId
        self._terminalOpen = terminalOpen
        self._terminalHeight = terminalHeight
        self.hideAgentPicker = hideAgentPicker
        self._createAgentVM = StateObject(wrappedValue: SubAgentsViewModel(openclawService: viewModel.openclawService))
    }

    /// The currently selected agent (for header bar display).
    private var currentAgent: AgentOption? {
        sessionState.availableAgents.first { $0.id == sessionState.selectedAgentId }
    }

    /// Workspace path for the terminal. Uses the shared resolver so it stays
    /// faithful to openclaw's resolveAgentWorkspaceDir (handles non-default
    /// "main" → workspace-main, explicit per-agent workspace, etc.).
    private var terminalWorkspacePath: String {
        DashboardViewModel.resolveAgentWorkspace(sessionState.selectedAgentId)
    }

    private var currentActiveSessionId: UUID? {
        sessionState.selectedSessionIdByAgent[sessionState.selectedAgentId]
    }

    private var currentMessages: [ChatMessage] {
        chatState.chatMessages(for: sessionState.selectedAgentId)
    }

    private var currentPendingComposerMessages: [PendingComposerMessage] {
        guard let sessionId = currentActiveSessionId else { return [] }
        return pendingComposerMessagesBySession[sessionId] ?? []
    }

    private var existingNavigationSessionIds: Set<UUID> {
        var ids = Set(sessionState.selectedSessionIdByAgent.values)
        ids.formUnion(sessionState.sessionsByAgent.values.flatMap { $0.map(\.id) })
        ids.formUnion(sessionState.pinnedSessions.map(\.id))
        ids.formUnion(sessionState.projectSessionsByAgent.values.flatMap { groups in
            groups.flatMap { $0.sessions.map(\.id) }
        })
        return ids
    }

    private func prunePendingComposerMessagesForExistingSessions() {
        let existingIds = existingNavigationSessionIds
        pendingComposerMessagesBySession = pendingComposerMessagesBySession.filter { existingIds.contains($0.key) }
    }

    private var currentForegroundTaskMessageId: UUID? {
        guard let sessionId = currentActiveSessionId else { return nil }
        return taskState.foregroundTaskId(inSession: sessionId)
    }

    private var shouldShowStopButton: Bool {
        taskState.isSendingMessage
            && inputText.trimmingCharacters(in: .whitespaces).isEmpty
            && attachedFiles.isEmpty
            && currentForegroundTaskMessageId != nil
    }

    private var shouldFollowChatBottom: Bool {
        chatAutoScrollMode == .followingBottom || chatAutoScrollMode == .sessionJumping
    }

    // MARK: - Chat Message List (extracted for compiler performance)

    @ViewBuilder
    private func chatScrollContent(proxy: ScrollViewProxy) -> some View {
        let allMessages = currentMessages
        let activeSessionId = currentActiveSessionId
        let tailLimit = activeSessionId.map { historyTailLimitBySession[$0] ?? Self.historyTailWindow }
        let hiddenEarlierCount = tailLimit.map { max(0, allMessages.count - $0) } ?? 0
        let isLoadingHistory = activeSessionId.map { chatState.loadingSessionIds.contains($0) } ?? false

        let timelineSnapshot = timelineSnapshotCache.snapshot(
            messages: allMessages,
            tailLimit: tailLimit,
            workspaceRootPath: {
                // Same resolution as the workspace inspector: bound project
                // root first, else the current agent's workspace.
                if let sid = activeSessionId,
                   let projectRoot = viewModel.sessionMetadata(for: sid)?.projectRoot,
                   !projectRoot.isEmpty {
                    return projectRoot
                }
                return DashboardViewModel.effectiveAgentWorkspace(viewModel.selectedAgentId)
            }(),
            activeStreamStatesByMessageId: chatState.activeStreamStatesByMessageId,
            runStatesByMessageId: taskState.runsByMessageId.mapValues(\.presentationState),
            highlightedMessageId: highlightedMessageId,
            highlightedMessageFlashOn: highlightedMessageFlashOn
        )
        let scrollView = ChatTimelineSurface(
            snapshot: timelineSnapshot,
            proxy: proxy,
            columnMaxWidth: Self.layoutMetrics.chatColumnMaxWidth,
            hiddenEarlierCount: hiddenEarlierCount,
            isLoadingHistory: isLoadingHistory && allMessages.isEmpty,
            onLoadEarlier: {
                guard let activeSessionId else { return }
                let current = historyTailLimitBySession[activeSessionId] ?? Self.historyTailWindow
                historyTailLimitBySession[activeSessionId] = current + Self.historyTailPageSize
            },
            onConfirmEditResend: { messageId, editedText in
                viewModel.rewindToMessage(id: messageId, replacementText: editedText)
            },
            onCancel: { viewModel.cancelChat($0) },
            onRetryConnection: viewModel.retryChatConnection,
            onOpenFileReference: { path in
                viewModel.previewFileInInspector(path)
            }
        )
        .alert(
            "回滚失败",
            isPresented: Binding(
                get: { viewModel.rewindError != nil },
                set: { if !$0 { viewModel.rewindError = nil } }
            )
        ) {
            Button("好", role: .cancel) { viewModel.rewindError = nil }
        } message: {
            Text(viewModel.rewindError ?? "")
        }
        // NB: do NOT put `.id(activeSessionId)` here. It fixes the
        // blank-on-cold-switch viewport bug by recreating the whole scroll
        // subtree, but that synchronous rebuild of every ChatBubble + its
        // NSViewRepresentable markdown host — especially with the workspace
        // inspector open (extra nested NSHostingControllers) — reignites the
        // SwiftUI<->AppKit layout livelock on session switch / send (froze the
        // app, needed force-kill; 2026-07-24). The blank viewport is instead
        // reset non-destructively by a no-animation jump to the last real row
        // in `scrollToBottomIfAllowed` (see there).

        if #available(macOS 14.0, *) {
            scrollView
                .defaultScrollAnchor(.bottom)
                .onChange(of: currentMessages.count) { _ in
                    logChatMessagesCountChanged()
                    // Only auto-scroll while the user is following the latest message.
                    if shouldFollowChatBottom {
                        // Use animated scroll so LazyVStack can progressively create views
                        // during the scroll animation, avoiding white flash from instant jump
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            scrollToBottomIfAllowed()
                        }
                    }
                }
        } else {
            scrollView
                .onChange(of: currentMessages.count) { _ in
                    logChatMessagesCountChanged()
                    if shouldFollowChatBottom {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            scrollToBottomIfAllowed()
                        }
                    }
                }
                .onAppear {
                    if !currentMessages.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            scrollToBottomIfAllowed()
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            scrollToBottomIfAllowed()
                        }
                    }
                }
        }
    }

    /// Filtered slash commands based on current input
    private var filteredSlashCommands: [SlashCommand] {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return [] }
        // Only match when the input is purely a command prefix (no spaces = no param yet)
        guard !trimmed.dropFirst().contains(" ") else { return [] }
        if trimmed == "/" { return slashCommands }
        return slashCommands.filter { $0.name.hasPrefix(trimmed.lowercased()) }
    }

    private var showSlashPanel: Bool {
        !filteredSlashCommands.isEmpty && !showSkillsPanel && !showAgentPanel
    }

    /// Filtered skills based on input after "/skills "
    private var readyComposerSkills: [SkillInfo] {
        viewModel.skills.filter { $0.status == .ready }
    }

    private var filteredSkills: [SkillInfo] {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces).lowercased()
        // Exact "/skills" or "/skills " prefix
        guard trimmed == "/skills" || trimmed.hasPrefix("/skills ") else { return [] }
        let keyword = trimmed.hasPrefix("/skills ") ? String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces) : ""
        let allSkills = readyComposerSkills
        if keyword.isEmpty { return allSkills }
        return allSkills.filter { skill in
            let catalogItem = catalogItem(for: skill)
            let display = catalogItem.map { I18n.skillDisplay(for: $0) }
            return I18n.localizedSearchFields(
                [
                    skill.name,
                    display?.displayName ?? "",
                    display?.description ?? skill.description
                ],
                originals: [
                    catalogItem?.displayName ?? skill.name,
                    catalogItem?.description ?? skill.description,
                    skill.description,
                    skill.source
                ]
            )
            .joined(separator: " ")
            .lowercased()
            .contains(keyword)
        }
    }

    private var skillCatalogItemsByName: [String: SkillCatalogItem] {
        SkillNameIndex.firstByName(viewModel.skillCatalog) { $0.name }
    }

    private func catalogItem(for skill: SkillInfo) -> SkillCatalogItem? {
        skillCatalogItemsByName[skill.name]
    }

    private func localizedSkillDescription(for skill: SkillInfo) -> String? {
        if let catalogItem = catalogItem(for: skill) {
            return nonBlankString(I18n.skillDisplay(for: catalogItem).description)
        }
        return nonBlankString(skill.description)
    }

    private func nonBlankString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func localizedSkillHelp(for skill: SkillInfo) -> String {
        localizedSkillDescription(for: skill) ?? skill.name
    }

    private var showSkillsPanel: Bool {
        if skillJustSelected { return false }
        let trimmed = inputText.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed == "/skills" || trimmed.hasPrefix("/skills ") else { return false }
        guard !readyComposerSkills.isEmpty else { return false }
        let keyword = trimmed.hasPrefix("/skills ") ? String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces) : ""
        if keyword.contains(" ") { return false }
        return true
    }

    /// Filtered agents based on input after "@"
    private var filteredAgents: [AgentOption] {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("@") else { return [] }
        let keyword = String(trimmed.dropFirst()).lowercased()
        // Only match when typing the agent name (no space yet)
        guard !keyword.contains(" ") else { return [] }
        let allAgents = sessionState.availableAgents
        if keyword.isEmpty { return allAgents }
        return allAgents.filter { $0.name.lowercased().contains(keyword) || $0.id.lowercased().contains(keyword) }
    }

    private var showAgentPanel: Bool {
        if agentJustSelected { return false }
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("@") else { return false }
        guard !sessionState.availableAgents.isEmpty else { return false }
        let keyword = String(trimmed.dropFirst())
        // Only show panel while typing agent name (before space)
        if keyword.contains(" ") { return false }
        return true
    }

    private var showComposerSuggestions: Bool {
        showSlashPanel || showSkillsPanel || showAgentPanel
    }

    private var composerSuggestionSelectedBackground: SwiftUI.Color {
        Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.08)
    }

    private var emptyChatSurface: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            VStack(spacing: 22) {
                Text(String(localized: "What should we build today?", bundle: LanguageManager.shared.localizedBundle))
                    .font(.system(size: 30, weight: .regular))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                composerArea(maxWidth: Self.layoutMetrics.chatColumnMaxWidth, horizontalPadding: 0, bottomPadding: 0)
            }
            .offset(y: Self.emptyChatContentYOffset)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var timelineChatSurface: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ZStack(alignment: .topTrailing) {
                    chatScrollContent(proxy: proxy)
                        .onAppear {
                            chatScrollProxy = proxy
                            if !currentMessages.isEmpty && shouldFollowChatBottom {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    scrollToBottomIfAllowed()
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    scrollToBottomIfAllowed()
                                }
                            }
                        }
                    ChatScrollIntentObserver(onScrollPositionChange: { isAtBottom in
                        handleChatScrollPositionChange(isAtBottom: isAtBottom)
                    })
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                }
            }
            .id("chatScrollView")

            composerArea(maxWidth: Self.layoutMetrics.chatColumnMaxWidth, horizontalPadding: 16, bottomPadding: 16)
        }
    }

    private func handleChatScrollPositionChange(isAtBottom: Bool) {
        guard chatScrollIsAtBottom != isAtBottom else { return }
        chatScrollIsAtBottom = isAtBottom

        if isAtBottom && chatAutoScrollMode == .userDetached {
            chatAutoScrollMode = .followingBottom
        }
    }

    private func composerArea(maxWidth: CGFloat, horizontalPadding: CGFloat, bottomPadding: CGFloat) -> some View {
        VStack(spacing: 8) {
            if !currentPendingComposerMessages.isEmpty {
                PendingComposerQueueView(
                    messages: currentPendingComposerMessages,
                    onSend: sendPendingComposerMessage,
                    onEdit: editPendingComposerMessage,
                    onDelete: deletePendingComposerMessage
                )
            }

            composerInputCard
                .anchorPreference(key: ComposerInputCardBoundsKey.self, value: .bounds) { $0 }
        }
        .frame(maxWidth: maxWidth)
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, bottomPadding)
        .animation(.easeInOut(duration: 0.15), value: showSlashPanel)
        .animation(.easeInOut(duration: 0.15), value: showSkillsPanel)
        .animation(.easeInOut(duration: 0.18), value: showComposerSelector)
    }

    private var composerFloatingPanels: some View {
        composerSuggestionPanels
            .zIndex(4)
            .allowsHitTesting(showSlashPanel || showSkillsPanel || showAgentPanel)
    }

    @ViewBuilder
    private var composerSuggestionPanels: some View {
        if showSlashPanel {
            slashCommandPanel
        }

        if showSkillsPanel {
            skillsPanel
        }

        if showAgentPanel {
            agentMentionPanel
        }
    }

    private var slashCommandPanel: some View {
        VStack(spacing: 0) {
            ScrollViewReader { slashProxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredSlashCommands.enumerated()), id: \.element.id) { index, cmd in
                            HStack(spacing: 8) {
                                Text(cmd.name)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(cmd.description)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(index == slashSelectedIndex ? composerSuggestionSelectedBackground : Color.clear)
                            .cornerRadius(6)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectSlashCommand(filteredSlashCommands[index])
                            }
                            .id(cmd.id)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: slashSelectedIndex) { newIndex in
                    if newIndex >= 0 && newIndex < filteredSlashCommands.count {
                        withAnimation {
                            slashProxy.scrollTo(filteredSlashCommands[newIndex].id, anchor: .center)
                        }
                    }
                }
            }
            .frame(maxHeight: composerSuggestionPanelMaxHeight)
        }
        .autocompletePanelStyle()
    }

    private var skillsPanel: some View {
        VStack(spacing: 0) {
            if filteredSkills.isEmpty {
                HStack {
                    Text(String(localized: "No matching skills", bundle: LanguageManager.shared.localizedBundle))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else {
                ScrollViewReader { skillProxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredSkills.enumerated()), id: \.element.id) { index, skill in
                                let description = localizedSkillDescription(for: skill)

                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                    Text(skill.name)
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if let description {
                                        Text(description)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    if !skill.source.isEmpty {
                                        Text(skill.source)
                                            .font(.system(size: 10))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(index == skillsSelectedIndex ? Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08) : Color.secondary.opacity(0.12))
                                            .cornerRadius(4)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(index == skillsSelectedIndex ? composerSuggestionSelectedBackground : Color.clear)
                                .cornerRadius(6)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectSkill(filteredSkills[index])
                                }
                                .id("skill-\(skill.name)")
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: skillsSelectedIndex) { newIndex in
                        if newIndex >= 0 && newIndex < filteredSkills.count {
                            withAnimation {
                                skillProxy.scrollTo("skill-\(filteredSkills[newIndex].name)", anchor: .center)
                            }
                        }
                    }
                }
                .frame(maxHeight: composerSuggestionPanelMaxHeight)
            }
        }
        .autocompletePanelStyle()
    }

    private var agentMentionPanel: some View {
        VStack(spacing: 0) {
            if filteredAgents.isEmpty {
                HStack {
                    Text(String(localized: "No matching agents", bundle: LanguageManager.shared.localizedBundle))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else {
                ScrollViewReader { agentProxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredAgents.enumerated()), id: \.element.id) { index, agent in
                                HStack(spacing: 8) {
                                    AgentAvatarImage(size: 18)
                                        .frame(width: 24)
                                    Text(agent.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.primary)
                                    if agent.id != agent.name {
                                        Text(agent.id)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if agent.id == sessionState.selectedAgentId {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(index == agentSelectedIndex ? .primary : .secondary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(index == agentSelectedIndex ? composerSuggestionSelectedBackground : Color.clear)
                                .cornerRadius(6)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectAgent(filteredAgents[index])
                                }
                                .id("agent-\(agent.id)")
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: agentSelectedIndex) { newIndex in
                        if newIndex >= 0 && newIndex < filteredAgents.count {
                            withAnimation {
                                agentProxy.scrollTo("agent-\(filteredAgents[newIndex].id)", anchor: .center)
                            }
                        }
                    }
                }
                .frame(maxHeight: composerSuggestionPanelMaxHeight)
            }
        }
        .autocompletePanelStyle()
    }

    private var composerInputCard: some View {
        ChatComposerView(
            viewModel: viewModel,
            inputText: $inputText,
            attachedFiles: $attachedFiles,
            showComposerSelector: $showComposerSelector,
            isInputFocused: $isInputFocused,
            isInputLocked: isInputLocked,
            shouldShowStopButton: shouldShowStopButton,
            currentForegroundTaskMessageId: currentForegroundTaskMessageId,
            canSend: canSend,
            sendButtonFillColor: sendButtonFillColor,
            sendButtonIconColor: sendButtonIconColor,
            composerEditorHeight: composerEditorHeight,
            onOpenFilePicker: openFilePicker,
            onSendMessage: sendMessage,
            onCancelMessage: { viewModel.cancelChat($0) }
        )
    }

    private var terminalPanel: some View {
        VStack(spacing: 0) {
            TerminalDragHandle(height: $terminalHeight)
            TerminalPanelView(
                workspacePath: terminalWorkspacePath,
                onClose: { withAnimation { terminalOpen = false } }
            )
            .frame(height: terminalHeight)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: -2)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func closeComposerSelector() {
        withAnimation(.easeInOut(duration: 0.16)) {
            showComposerSelector = false
        }
    }

    private var composerSelectorDismissLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                closeComposerSelector()
            }
    }

    @ViewBuilder
    private func composerSuggestionOverlay(anchor: Anchor<CGRect>?) -> some View {
        GeometryReader { proxy in
            if let anchor, showComposerSuggestions {
                let inputFrame = proxy[anchor]
                let panelTopOffset = max(12, inputFrame.minY - composerSuggestionPanelMaxHeight - 8)

                ZStack(alignment: .topLeading) {
                    composerFloatingPanels
                        .frame(width: inputFrame.width)
                        .frame(maxHeight: composerSuggestionPanelMaxHeight, alignment: .bottomLeading)
                        .offset(x: inputFrame.minX, y: panelTopOffset)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .zIndex(1)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .allowsHitTesting(showComposerSuggestions)
                .animation(.easeInOut(duration: 0.15), value: showSlashPanel)
                .animation(.easeInOut(duration: 0.15), value: showSkillsPanel)
                .animation(.easeInOut(duration: 0.15), value: showAgentPanel)
            }
        }
    }

    @ViewBuilder
    private func composerSelectorOverlay(anchor: Anchor<CGRect>?) -> some View {
        GeometryReader { proxy in
            if let anchor, showComposerSelector {
                let selectorFrame = proxy[anchor]
                let trailingOffset = max(12, proxy.size.width - selectorFrame.maxX)
                let bottomOffset = max(12, proxy.size.height - selectorFrame.minY + 8)

                ZStack(alignment: .bottomTrailing) {
                    composerSelectorDismissLayer
                        .zIndex(0)

                    ComposerModelPanel(
                        modelGroups: viewModel.availableModelGroups,
                        currentModel: viewModel.activeComposerModel,
                        defaultModel: viewModel.modelOverview.defaultModel,
                        isOpen: $showComposerSelector,
                        onSelectModel: viewModel.selectComposerModel
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.trailing, trailingOffset)
                    .padding(.bottom, bottomOffset)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottomTrailing)))
                    .zIndex(1)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .animation(.easeInOut(duration: 0.18), value: showComposerSelector)
            }
        }
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            if currentMessages.isEmpty {
                emptyChatSurface
            } else {
                timelineChatSurface
            }

            if terminalOpen {
                terminalPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: terminalOpen)
    }

    var body: some View {
        chatContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlayPreferenceValue(ComposerInputCardBoundsKey.self) { anchor in
                composerSuggestionOverlay(anchor: anchor)
            }
            .overlayPreferenceValue(ComposerSelectorButtonBoundsKey.self) { anchor in
                composerSelectorOverlay(anchor: anchor)
            }
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: requestedUserMessageJumpId) { messageId in
            guard let messageId else { return }
            jumpToUserMessage(messageId)
            requestedUserMessageJumpId = nil
        }
        .onAppear {
            viewModel.loadAvailableAgents()
            if viewModel.skills.isEmpty {
                Task { await viewModel.loadSkillMarket() }
            }

            // Monitor scroll wheel events to detect user scrolling
            if let monitor = scrollEventMonitor {
                NSEvent.removeMonitor(monitor)
                scrollEventMonitor = nil
            }
            scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                if event.scrollingDeltaY < 0 {
                    chatAutoScrollMode = .userDetached
                    scheduledBottomScrollGeneration += 1
                }

                return event
            }

            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if handleCopyShortcut(event) {
                    return nil
                }

                guard let responder = event.window?.firstResponder, responder is NSTextView else {
                    return event
                }
                // Don't intercept keys when the code editor's NSTextView is focused
	                if let tv = responder as? NSTextView, tv.identifier?.rawValue == "codeEditorTextView" {
	                    return event
	                }

	                // macOS TextField editing uses a shared NSTextView field editor.
	                // Those field editors belong to the active TextField, not to the
	                // chat composer, so composer shortcuts/focus must ignore them.
	                if let tv = responder as? NSTextView, tv.isFieldEditor {
	                    return event
	                }

	                // Don't intercept keys when a CommitTextField (rename/new file) is focused
	                if let tv = responder as? NSTextView,
	                   tv.identifier?.rawValue == "commitTextField" {
                    return event
                }

                if let tv = responder as? NSTextView,
                   tv.identifier?.rawValue == "inlineMessageEditorTextView" {
                    return event
                }

                // IME composition guard — when the user is mid-pinyin
                // (or any other input-method composition), the text view
                // has "marked text" (the candidates shown above the
                // caret). In that state ALL keys including Return / Tab
                // / Escape belong to the IME — Return commits the raw
                // composed text as English, Tab cycles candidates, etc.
                // Without this guard, hitting Return mid-composition
                // gets intercepted by our sendMessage shortcut, and the
                // half-typed pinyin (e.g. "li'r") is sent literally
                // before the IME has a chance to convert it.
                if let tv = responder as? NSTextView, tv.hasMarkedText() {
                    return event
                }

                // Escape (keyCode 53) — close slash/skills/agent panel
                if event.keyCode == 53 && (showSlashPanel || showSkillsPanel || showAgentPanel) {
                    DispatchQueue.main.async {
                        inputText = ""
                        slashSelectedIndex = 0
                        skillsSelectedIndex = 0
                        agentSelectedIndex = 0
                    }
                    return nil
                }

                // Cmd+V (keyCode 9) — paste image from clipboard
                if event.keyCode == 9 && event.modifierFlags.contains(.command) {
                    let pb = NSPasteboard.general
                    let hasImage = pb.canReadItem(withDataConformingToTypes: [
                        NSPasteboard.PasteboardType.png.rawValue,
                        NSPasteboard.PasteboardType.tiff.rawValue
                    ])
                    // Only intercept if clipboard has image data but no text
                    let hasText = pb.string(forType: .string) != nil
                    if hasImage && !hasText {
                        DispatchQueue.main.async { pasteImageFromClipboard() }
                        return nil
                    }
                }

                // Tab (keyCode 48) — confirm slash/skills/agent selection
                if event.keyCode == 48 {
                    if showAgentPanel {
                        let agents = filteredAgents
                        if agentSelectedIndex >= 0 && agentSelectedIndex < agents.count {
                            DispatchQueue.main.async { selectAgent(agents[agentSelectedIndex]) }
                        }
                        return nil
                    }
                    if showSkillsPanel {
                        let skills = filteredSkills
                        if skillsSelectedIndex >= 0 && skillsSelectedIndex < skills.count {
                            DispatchQueue.main.async { selectSkill(skills[skillsSelectedIndex]) }
                        }
                        return nil
                    }
                    if showSlashPanel {
                        let cmds = filteredSlashCommands
                        if slashSelectedIndex >= 0 && slashSelectedIndex < cmds.count {
                            DispatchQueue.main.async { selectSlashCommand(cmds[slashSelectedIndex]) }
                        }
                        return nil
                    }
                }

                // Return without Shift
                if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
                    // If agent panel is open, confirm selection instead of sending
                    if showAgentPanel {
                        let agents = filteredAgents
                        if !agents.isEmpty && agentSelectedIndex >= 0 && agentSelectedIndex < agents.count {
                            DispatchQueue.main.async { selectAgent(agents[agentSelectedIndex]) }
                        }
                        return nil
                    }
                    // If skills panel is open, confirm selection instead of sending
                    if showSkillsPanel {
                        let skills = filteredSkills
                        if !skills.isEmpty && skillsSelectedIndex >= 0 && skillsSelectedIndex < skills.count {
                            DispatchQueue.main.async { selectSkill(skills[skillsSelectedIndex]) }
                        }
                        return nil
                    }
                    // If slash panel is open, confirm selection instead of sending
                    if showSlashPanel {
                        let cmds = filteredSlashCommands
                        if slashSelectedIndex >= 0 && slashSelectedIndex < cmds.count {
                            DispatchQueue.main.async { selectSlashCommand(cmds[slashSelectedIndex]) }
                        }
                        return nil
                    }
                    DispatchQueue.main.async { sendMessage() }
                    return nil
                }

                // ↑ (keyCode 126)
                if event.keyCode == 126 {
                    // Agent panel navigation takes priority
                    if showAgentPanel {
                        DispatchQueue.main.async {
                            if agentSelectedIndex > 0 {
                                agentSelectedIndex -= 1
                            }
                        }
                        return nil
                    }
                    // Skills panel navigation takes priority
                    if showSkillsPanel {
                        DispatchQueue.main.async {
                            if skillsSelectedIndex > 0 {
                                skillsSelectedIndex -= 1
                            }
                        }
                        return nil
                    }
                    // Slash panel navigation takes priority
                    if showSlashPanel {
                        DispatchQueue.main.async {
                            if slashSelectedIndex > 0 {
                                slashSelectedIndex -= 1
                            }
                        }
                        return nil
                    }
                    // History browsing
                    if (inputText.isEmpty || historyIndex >= 0) && !queryHistory.isEmpty {
                        if historyIndex == -1 {
                            historyIndex = queryHistory.count - 1
                        } else if historyIndex > 0 {
                            historyIndex -= 1
                        }
                        inputText = queryHistory[historyIndex]
                        return nil
                    }
                }

                // ↓ (keyCode 125)
                if event.keyCode == 125 {
                    // Agent panel navigation takes priority
                    if showAgentPanel {
                        DispatchQueue.main.async {
                            let agents = filteredAgents
                            if agentSelectedIndex < agents.count - 1 {
                                agentSelectedIndex += 1
                            }
                        }
                        return nil
                    }
                    // Skills panel navigation takes priority
                    if showSkillsPanel {
                        DispatchQueue.main.async {
                            let skills = filteredSkills
                            if skillsSelectedIndex < skills.count - 1 {
                                skillsSelectedIndex += 1
                            }
                        }
                        return nil
                    }
                    // Slash panel navigation takes priority
                    if showSlashPanel {
                        DispatchQueue.main.async {
                            let cmds = filteredSlashCommands
                            if slashSelectedIndex < cmds.count - 1 {
                                slashSelectedIndex += 1
                            }
                        }
                        return nil
                    }
                    // History browsing
                    if historyIndex >= 0 {
                        if historyIndex < queryHistory.count - 1 {
                            historyIndex += 1
                            inputText = queryHistory[historyIndex]
                        } else {
                            historyIndex = -1
                            inputText = ""
                        }
                        return nil
                    }
                }

                return event
            }

	            // Focus monitor: track whether the TextEditor has focus
	            focusMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { event in
	                DispatchQueue.main.async {
	                    // "Any non-field-editor NSTextView" is NOT the composer: the
	                    // inline history-message editor, the workspace code editor and
	                    // the commit field are NSTextViews too. On every keystroke this
	                    // used to declare the composer focused, so SwiftUI yanked the
	                    // caret out of whatever the user was really typing in. Our own
	                    // text views carry identifiers; the composer's TextEditor has none.
	                    if let responder = NSApp.keyWindow?.firstResponder,
	                       let textView = responder as? NSTextView,
	                       !textView.isFieldEditor,
	                       textView.identifier == nil {
	                        if !isInputFocused { withAnimation(.easeOut(duration: 0.15)) { isInputFocused = true } }
	                    } else {
	                        if isInputFocused { withAnimation(.easeIn(duration: 0.15)) { isInputFocused = false } }
                    }
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
            if let monitor = focusMonitor {
                NSEvent.removeMonitor(monitor)
                focusMonitor = nil
            }
            if let monitor = scrollEventMonitor {
                NSEvent.removeMonitor(monitor)
                scrollEventMonitor = nil
            }
            highlightFlashTask?.cancel()
            highlightFlashTask = nil
        }
        .onChange(of: inputText) { _ in
            // Reset slash/skills/agent selection index when input changes
            slashSelectedIndex = 0
            skillsSelectedIndex = 0
            agentSelectedIndex = 0
            // Reset skill selection flag if input no longer has skill prefix
            if skillJustSelected {
                let trimmed = inputText.trimmingCharacters(in: .whitespaces).lowercased()
                if !trimmed.hasPrefix("/skills ") {
                    skillJustSelected = false
                }
            }
            // Reset agent selection flag if input no longer has @ prefix
            if agentJustSelected {
                let trimmed = inputText.trimmingCharacters(in: .whitespaces)
                if !trimmed.hasPrefix("@") {
                    agentJustSelected = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .gchChatInlineEditingChanged)) { note in
            handleInlineEditingChanged(note)
        }
        .onChange(of: viewModel.composerPrefill) { newValue in
            guard let prefill = newValue else { return }
            inputText = prefill
            attachedFiles = []
            historyIndex = -1
            withAnimation(.easeOut(duration: 0.15)) {
                isInputFocused = true
            }
            viewModel.composerPrefill = nil
        }
        .onChange(of: taskState.isSendingMessage) { isSending in
            if !isSending {
                drainPendingComposerQueueIfPossible()
            }
        }
        .onChange(of: currentActiveSessionId) { _ in
            drainPendingComposerQueueIfPossible()
            beginRenderObservationForCurrentSession()
            guard !viewModel.consumeSuppressNextSessionSwitchBottomScroll() else {
                scheduledBottomScrollGeneration += 1
                chatAutoScrollMode = .followingBottom
                return
            }
            scheduleSessionSwitchScrollToBottom()
        }
        .onChange(of: sessionState.sessionsByAgent) { _, _ in
            prunePendingComposerMessagesForExistingSessions()
        }
        .onChange(of: sessionState.projectSessionsByAgent) { _, _ in
            prunePendingComposerMessagesForExistingSessions()
        }
        .overlay(alignment: .trailing) {
            if viewModel.agentSettingsOpen, let detail = viewModel.selectedAgentDetail {
                AgentSettingsPanel(
                    viewModel: viewModel,
                    agent: detail,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModel.agentSettingsOpen = false
                        }
                    }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .onChange(of: sessionState.selectedAgentId) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                viewModel.agentSettingsOpen = false
                terminalOpen = false
            }
        }
        .sheet(isPresented: $showCreateAgentSheet) {
            CreateAgentSheet(
                viewModel: createAgentVM,
                isPresented: $showCreateAgentSheet,
                onCreatedWithId: { agentId in
                    viewModel.loadAvailableAgents()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        viewModel.selectedAgentId = agentId
                    }
                }
            )
        }
    }

    private var canSend: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespaces).isEmpty
        let hasFiles = !attachedFiles.isEmpty
        return hasText || hasFiles
    }

    private func handleCopyShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "c" else {
            return false
        }

        if NativeSelectableTextSelectionRegistry.copySelectedTextFromFirstResponder(nil) {
            return true
        }

        return WebViewMarkdownSelectionRegistry.copyActiveSelection()
    }

    private var sendButtonFillColor: SwiftUI.Color {
        canSend || shouldShowStopButton
            ? Color.black
            : Color(NSColor.quaternaryLabelColor)
    }

    private var sendButtonIconColor: SwiftUI.Color {
        canSend || shouldShowStopButton
            ? Color(NSColor.windowBackgroundColor)
            : Color(NSColor.tertiaryLabelColor)
    }

    /// Whether the input area (text + attachment) should be locked.
    /// Session-scoped — see comment in `canSend`. Switching to a
    /// different session of the same agent unlocks the input even if
    /// the previous session has a task still streaming in the
    /// inactive-sessions map.
    private var isInputLocked: Bool {
        false
    }

    private func sendMessage() {
        var text = inputText.trimmingCharacters(in: .whitespaces)
        let files = attachedFiles
        guard !text.isEmpty || !files.isEmpty else { return }
        inputText = ""
        attachedFiles = []

        if taskState.isSendingMessage {
            enqueuePendingComposerMessage(text: text, attachments: files)
            return
        }

        // Handle @agent_name prefix: strip it and use the actual message
        if text.hasPrefix("@") {
            let afterAt = String(text.dropFirst())
            if let spaceIdx = afterAt.firstIndex(of: " ") {
                let agentName = String(afterAt[afterAt.startIndex..<spaceIdx])
                let messageContent = String(afterAt[afterAt.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespaces)
                // Verify the agent exists
                if sessionState.availableAgents.contains(where: { $0.name == agentName || $0.id == agentName }) {
                    text = messageContent.isEmpty ? "hi, \(agentName)" : messageContent
                }
            } else {
                // Just "@agentName" with no message
                let agentName = afterAt.trimmingCharacters(in: .whitespaces)
                if sessionState.availableAgents.contains(where: { $0.name == agentName || $0.id == agentName }) {
                    text = "hi, \(agentName)"
                }
            }
        }

        // Update history: deduplicate, append, cap at 20, persist
        if !text.isEmpty {
            if let idx = queryHistory.firstIndex(of: text) {
                queryHistory.remove(at: idx)
            }
            queryHistory.append(text)
            if queryHistory.count > 20 {
                queryHistory.removeFirst()
            }
            UserDefaults.standard.set(queryHistory, forKey: "chatQueryHistory")
        }
        historyIndex = -1

        // Handle local commands
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        if lower == "/exit" {
            NSApp.terminate(nil)
            return
        }

        // Handle /collab command
        if lower.hasPrefix("/collab ") {
            let taskDescription = String(text.dropFirst("/collab ".count)).trimmingCharacters(in: .whitespaces)
            guard !taskDescription.isEmpty else { return }

            // Show user message
            chatState.chatMessagesByAgent["commander", default: []].append(ChatMessage(role: .user, content: text))

            // Show placeholder
            let clarifyingText = String(localized: "Understanding requirements...", bundle: LanguageManager.shared.localizedBundle)
            chatState.chatMessagesByAgent["commander", default: []].append(ChatMessage(role: .assistant, content: clarifyingText, agentId: "commander"))

            let collabVM = viewModel.getOrCreateCollabViewModel()

            // Open collab window
            viewModel.showCollabPanel = true
            viewModel.collabPanelCollapsed = false

            Task {
                await collabVM.startCollab(taskDescription)
                // Note: chat messages are now managed by CollabViewModel phases
                // (clarify questions, decompose plan, final result are appended by VM)
            }
            return
        }

        // Route messages to active collab session based on phase (only when on Commander tab)
        // Skip routing when session is stale (not running + not in an interactive phase)
        if sessionState.selectedAgentId == "commander",
           let collabVM = viewModel.collabViewModel,
           collabVM.session != nil {
            let collabPhase = collabVM.phase
            let isInteractivePhase = (collabPhase == .clarifying || collabPhase == .awaitingApproval)

            if collabVM.isRunning || isInteractivePhase {
                if collabPhase == .clarifying {
                    // User is answering Commander's clarification questions
                    chatState.chatMessagesByAgent["commander", default: []].append(ChatMessage(role: .user, content: text))
                    Task {
                        await collabVM.handleClarifyResponse(text)
                    }
                    return
                }

                if collabPhase == .awaitingApproval {
                    chatState.chatMessagesByAgent["commander", default: []].append(ChatMessage(role: .user, content: text))
                    let confirmWords = ["确认", "ok", "go", "执行", "开始", "yes", "confirm", "start"]
                    if confirmWords.contains(lower) {
                        chatState.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                            role: .assistant,
                            content: String(localized: "Starting task execution...", bundle: LanguageManager.shared.localizedBundle),
                            agentId: "commander"
                        ))
                        Task {
                            await collabVM.confirmAndExecute()
                        }
                    } else {
                        // User wants to continue discussing / adjust requirements
                        Task {
                            await collabVM.handleClarifyResponse(text)
                        }
                    }
                    return
                }

                if collabPhase == .executing || collabPhase == .summarizing || collabPhase == .completed {
                    // Route to existing chat handler during/after execution
                    chatState.chatMessagesByAgent["commander", default: []].append(ChatMessage(role: .user, content: text))
                    Task {
                        if let reply = await collabVM.handleUserMessage(text) {
                            chatState.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                                role: .assistant,
                                content: reply,
                                agentId: "commander"
                            ))
                        }
                    }
                    return
                }
            }
            // Stale session (not running, not interactive) — fall through to start new collab
        }

        // Auto-trigger collab when chatting with Commander (no active collab session)
        // First check intent — simple questions get direct replies without entering collab
        if sessionState.selectedAgentId == "commander" {
            chatState.chatMessagesByAgent["commander", default: []].append(ChatMessage(role: .user, content: text))

            let collabVM = viewModel.getOrCreateCollabViewModel()

            // Show thinking placeholder
            let thinkingId = UUID()
            chatState.chatMessagesByAgent["commander", default: []].append(ChatMessage(role: .assistant, content: "", agentId: "commander", taskStatus: .loading, id: thinkingId))
            taskState.isSendingMessage = true

            Task {
                let directReply = await collabVM.checkIntent(text)

                // Remove thinking placeholder
                await MainActor.run {
                    if let idx = chatState.chatMessagesByAgent["commander"]?.firstIndex(where: { $0.id == thinkingId }) {
                        chatState.chatMessagesByAgent["commander"]?.remove(at: idx)
                    }
                }

                if let reply = directReply {
                    // Commander answered directly — no collab needed
                    await MainActor.run {
                        chatState.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                            role: .assistant,
                            content: reply,
                            agentId: "commander"
                        ))
                        taskState.isSendingMessage = false
                    }
                } else {
                    // Commander says this needs collab — proceed with full flow
                    await MainActor.run {
                        let clarifyingText = String(localized: "Understanding requirements...", bundle: LanguageManager.shared.localizedBundle)
                        chatState.chatMessagesByAgent["commander", default: []].append(ChatMessage(role: .assistant, content: clarifyingText, agentId: "commander"))

                        viewModel.showCollabPanel = true
                        viewModel.collabPanelCollapsed = false
                        taskState.isSendingMessage = false
                    }
                    await collabVM.startCollab(text)
                }
            }
            return
        }

        let isResetCommand = (lower == "/new" || lower == "/reset")

        // Ensure scroll to bottom when user sends a message
        followChatBottomFromUserAction()

        Task {
            await viewModel.sendChatMessage(text, attachments: files)
            if isResetCommand {
                await MainActor.run { viewModel.clearChat() }
            }
        }
    }

    private func enqueuePendingComposerMessage(text: String, attachments: [URL]) {
        guard let sessionId = currentActiveSessionId else { return }
        let pending = PendingComposerMessage(text: text, attachments: attachments)
        pendingComposerMessagesBySession[sessionId, default: []].append(pending)
    }

    private func deletePendingComposerMessage(_ message: PendingComposerMessage) {
        guard let sessionId = currentActiveSessionId else { return }
        pendingComposerMessagesBySession[sessionId, default: []].removeAll { $0.id == message.id }
        if pendingComposerMessagesBySession[sessionId]?.isEmpty == true {
            pendingComposerMessagesBySession.removeValue(forKey: sessionId)
        }
    }

    /// The composer must not hold focus while a history message is being
    /// edited inline, and should get it back when that edit ends.
    private func handleInlineEditingChanged(_ note: Notification) {
        guard let isEditing = note.object as? Bool else { return }
        if isEditing {
            isInputFocused = false
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isInputFocused = true
            }
        }
    }

    private func editPendingComposerMessage(_ message: PendingComposerMessage) {
        deletePendingComposerMessage(message)
        inputText = message.text
        attachedFiles = message.attachments
        historyIndex = -1
        withAnimation(.easeOut(duration: 0.15)) {
            isInputFocused = true
        }
    }

    private func sendPendingComposerMessage(_ message: PendingComposerMessage) {
        if taskState.isSendingMessage {
            promotePendingComposerMessage(message)
            return
        }

        deletePendingComposerMessage(message)
        inputText = message.text
        attachedFiles = message.attachments
        followChatBottomFromUserAction()
        sendMessage()
    }

    private func promotePendingComposerMessage(_ message: PendingComposerMessage) {
        guard let sessionId = currentActiveSessionId,
              var queue = pendingComposerMessagesBySession[sessionId],
              let index = queue.firstIndex(where: { $0.id == message.id }) else {
            return
        }
        let promoted = queue.remove(at: index)
        queue.insert(promoted, at: 0)
        pendingComposerMessagesBySession[sessionId] = queue
    }

    private func drainPendingComposerQueueIfPossible() {
        guard !taskState.isSendingMessage,
              let sessionId = currentActiveSessionId,
              var queue = pendingComposerMessagesBySession[sessionId],
              !queue.isEmpty else {
            return
        }

        let next = queue.removeFirst()
        if queue.isEmpty {
            pendingComposerMessagesBySession.removeValue(forKey: sessionId)
        } else {
            pendingComposerMessagesBySession[sessionId] = queue
        }

        inputText = next.text
        attachedFiles = next.attachments
        followChatBottomFromUserAction()
        sendMessage()
    }

    /// Scroll chat to the latest message with animation.
    private func scheduleSessionSwitchScrollToBottom() {
        chatAutoScrollMode = .sessionJumping
        scheduledBottomScrollGeneration += 1
        let generation = scheduledBottomScrollGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            logScheduledBottomScroll(checkpoint: "0.05")
            scrollToBottomIfAllowed(generation: generation)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            logScheduledBottomScroll(checkpoint: "0.25")
            scrollToBottomIfAllowed(generation: generation)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) {
            logScheduledBottomScroll(checkpoint: "0.70")
            scrollToBottomIfAllowed(generation: generation)
            if scheduledBottomScrollGeneration == generation,
               chatAutoScrollMode == .sessionJumping {
                chatAutoScrollMode = .followingBottom
            }
        }
    }

    private func scrollToBottomIfAllowed(generation: Int? = nil) {
        if let generation, scheduledBottomScrollGeneration != generation { return }
        guard chatAutoScrollMode != .userDetached else { return }
        guard let proxy = chatScrollProxy else { return }
        // On a session jump the content was swapped in place; an ANIMATED
        // scroll to the empty "chatBottom" marker doesn't reliably drag the
        // viewport off its stale offset (that was the blank-on-cold-switch
        // bug). Jump instantly to the LAST REAL message row instead — a
        // concrete row with `.bottom` anchor and no animation forces the
        // viewport to land, without recreating the subtree.
        if chatAutoScrollMode == .sessionJumping, let lastId = currentMessages.last?.id {
            proxy.scrollTo(lastId, anchor: .bottom)
            return
        }
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo("chatBottom", anchor: .bottom)
        }
    }

    private func followChatBottomFromUserAction() {
        chatAutoScrollMode = .followingBottom
        scheduledBottomScrollGeneration += 1
        scrollToBottomIfAllowed()
    }

    private func beginRenderObservationForCurrentSession() {
        guard let sessionId = currentActiveSessionId else { return }
        renderObservationStartBySession[sessionId] = ContinuousClock.now
        chatRenderPerfLog.info("phase=session_changed session=\(sessionId.uuidString, privacy: .public) message_count=\(currentMessages.count, privacy: .public)")
    }

    private func logChatMessagesCountChanged() {
        guard let sessionId = currentActiveSessionId else { return }
        if renderObservationStartBySession[sessionId] == nil {
            renderObservationStartBySession[sessionId] = ContinuousClock.now
        }
        let elapsedText = renderElapsedMillisecondsText(for: sessionId)
        chatRenderPerfLog.info("phase=messages_count_changed session=\(sessionId.uuidString, privacy: .public) message_count=\(currentMessages.count, privacy: .public) elapsed_ms=\(elapsedText, privacy: .public)")
    }

    private func logScheduledBottomScroll(checkpoint: String) {
        guard let sessionId = currentActiveSessionId else { return }
        let elapsedText = renderElapsedMillisecondsText(for: sessionId)
        chatRenderPerfLog.info("phase=scheduled_bottom_scroll checkpoint=\(checkpoint, privacy: .public) session=\(sessionId.uuidString, privacy: .public) message_count=\(currentMessages.count, privacy: .public) elapsed_ms=\(elapsedText, privacy: .public)")
    }

    private func renderElapsedMillisecondsText(for sessionId: UUID) -> String {
        guard let start = renderObservationStartBySession[sessionId] else { return "n/a" }
        return dashboardElapsedMillisecondsText(since: start)
    }

    private func jumpToUserMessage(_ messageId: UUID) {
        guard currentMessages.contains(where: { $0.id == messageId && $0.role == .user }) else { return }
        chatAutoScrollMode = .userDetached
        scheduledBottomScrollGeneration += 1
        withAnimation(.easeInOut(duration: 0.24)) {
            chatScrollProxy?.scrollTo(messageId, anchor: .center)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            triggerUserMessageHighlight(messageId)
        }
    }

    private func triggerUserMessageHighlight(_ messageId: UUID) {
        highlightFlashTask?.cancel()
        highlightedMessageId = messageId
        highlightedMessageFlashOn = false

        highlightFlashTask = Task { @MainActor in
            for step in 0..<6 {
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.13)) {
                    highlightedMessageFlashOn = step % 2 == 0
                }
                try? await Task.sleep(nanoseconds: 170_000_000)
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                highlightedMessageFlashOn = false
            }
            if highlightedMessageId == messageId {
                highlightedMessageId = nil
            }
            highlightFlashTask = nil
        }
    }

    private func selectSlashCommand(_ cmd: SlashCommand) {
        slashSelectedIndex = 0
        if cmd.hasParam {
            // Fill command with trailing space, let user type the parameter
            inputText = cmd.name + " "
        } else {
            // No param — send immediately
            inputText = cmd.name
            sendMessage()
        }
    }

    private func selectSkill(_ skill: SkillInfo) {
        guard skill.status == .ready else { return }
        skillsSelectedIndex = 0
        skillJustSelected = true
        inputText = "/skills \(skill.name) "
    }

    private func selectAgent(_ agent: AgentOption) {
        agentSelectedIndex = 0
        agentJustSelected = true
        sessionState.selectedAgentId = agent.id
        inputText = "@\(agent.name) "
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .image, .pdf, .plainText,
            .audio, .movie,
            // Office
            UTType(filenameExtension: "doc")!,
            UTType(filenameExtension: "docx")!,
            UTType(filenameExtension: "xls")!,
            UTType(filenameExtension: "xlsx")!,
            UTType(filenameExtension: "ppt")!,
            UTType(filenameExtension: "pptx")!,
            // Data & Markup
            UTType(filenameExtension: "csv")!,
            UTType(filenameExtension: "json")!,
            UTType(filenameExtension: "md")!,
            UTType(filenameExtension: "xml")!,
            UTType(filenameExtension: "yaml")!,
            UTType(filenameExtension: "yml")!,
            UTType(filenameExtension: "toml")!,
            UTType(filenameExtension: "ini")!,
            UTType(filenameExtension: "env")!,
            UTType(filenameExtension: "conf")!,
            UTType(filenameExtension: "properties")!,
            // Source code
            UTType(filenameExtension: "py")!,
            UTType(filenameExtension: "js")!,
            UTType(filenameExtension: "ts")!,
            UTType(filenameExtension: "swift")!,
            UTType(filenameExtension: "java")!,
            UTType(filenameExtension: "go")!,
            UTType(filenameExtension: "rs")!,
            UTType(filenameExtension: "c")!,
            UTType(filenameExtension: "cpp")!,
            UTType(filenameExtension: "h")!,
            UTType(filenameExtension: "rb")!,
            UTType(filenameExtension: "php")!,
            UTType(filenameExtension: "sh")!,
            UTType(filenameExtension: "sql")!,
            UTType(filenameExtension: "r")!,
            // Web
            UTType(filenameExtension: "html")!,
            UTType(filenameExtension: "htm")!,
            UTType(filenameExtension: "css")!,
            UTType(filenameExtension: "scss")!,
            UTType(filenameExtension: "vue")!,
            UTType(filenameExtension: "jsx")!,
            UTType(filenameExtension: "tsx")!,
            // Log & Notebook
            UTType(filenameExtension: "log")!,
            UTType(filenameExtension: "ipynb")!,
            // Mind map
            UTType(filenameExtension: "xmind")!,
        ]
        if panel.runModal() == .OK {
            for url in panel.urls {
                if !attachedFiles.contains(url) {
                    attachedFiles.append(url)
                }
            }
        }
    }

    private func pasteImageFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let imageData = pasteboard.data(forType: .png)
                ?? pasteboard.data(forType: .tiff) else { return }

        let uploadsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw/uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: uploadsDir, withIntermediateDirectories: true)

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let fileName = "paste_\(timestamp).png"
        let fileURL = uploadsDir.appendingPathComponent(fileName)

        // Convert to PNG if needed
        if let image = NSImage(data: imageData),
           let tiffData = image.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: fileURL)
        } else {
            try? imageData.write(to: fileURL)
        }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            if !attachedFiles.contains(fileURL) {
                attachedFiles.append(fileURL)
            }
        }
    }
}

private extension View {
    func autocompletePanelStyle() -> some View {
        self
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 12, y: -4)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
