//
//  SessionPersistence.swift
//  Chat session persistence methods extracted from DashboardViewModel.
//  P1 refactor: file split only, no behavior change.
//  (@Published session maps + chatSessionStore stay in the main class.)
//

import Foundation
import AppKit
import os.log

extension DashboardViewModel {

    /// Refresh `sessionsByAgent` from the store's index. Newest-first within
    /// each derived display group. Archived sessions are excluded so the
    /// sidebar list stays clean; the underlying file remains on disk.
    func rebuildSessionsMirror() {
        let persistedSessionIds = Set(chatSessionStore.index.map(\.id))
        pendingSessionMetadataByAgent = pendingSessionMetadataByAgent.filter {
            !persistedSessionIds.contains($0.value.id)
        }

        var grouped: [String: [ChatSessionMetadata]] = [:]
        for meta in chatSessionStore.index where !meta.isArchived {
            grouped[meta.agentId, default: []].append(meta)
        }
        for pending in pendingSessionMetadataByAgent.values where !pending.isArchived {
            grouped[pending.agentId, default: []].append(pending)
        }
        for key in grouped.keys {
            grouped[key] = Self.orderedSessionMetadata(grouped[key] ?? [])
        }
        sessionsByAgent = grouped
        pinnedSessions = Self.orderedSessionMetadata(grouped.values.flatMap { $0 }.filter(\.isPinned))
        rebuildProjectSessionGroups(from: grouped)
    }

    private static func orderedSessionMetadata(_ sessions: [ChatSessionMetadata]) -> [ChatSessionMetadata] {
        sessions.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func rebuildProjectSessionGroups(from grouped: [String: [ChatSessionMetadata]]) {
        var projectGroups: [String: [ProjectSessionGroup]] = [:]
        var generalGroups: [String: [ChatSessionMetadata]] = [:]

        for (agentId, sessions) in grouped {
            let unpinnedSessions = Self.orderedSessionMetadata(sessions.filter { !$0.isPinned })
            let general = unpinnedSessions.filter { $0.projectId == nil }
            if !general.isEmpty {
                generalGroups[agentId] = general
            }

            let projectSessions = Dictionary(grouping: unpinnedSessions.filter { $0.projectId != nil }) {
                $0.projectId ?? ""
            }
            var groups: [ProjectSessionGroup] = []
            for (projectId, metas) in projectSessions where !projectId.isEmpty {
                guard let project = projectsById[projectId] else { continue }
                let binding = projectBindingsByAgent[agentId]?.first { $0.projectId == projectId }
                    ?? AgentProjectBinding(agentId: agentId, projectId: projectId)
                groups.append(ProjectSessionGroup(project: project, binding: binding, sessions: metas))
            }

            for binding in projectBindingsByAgent[agentId] ?? [] where groups.allSatisfy({ $0.project.id != binding.projectId }) {
                guard let project = projectsById[binding.projectId] else { continue }
                groups.append(ProjectSessionGroup(project: project, binding: binding, sessions: []))
            }

            groups.sort { lhs, rhs in
                if lhs.binding.sortOrder != rhs.binding.sortOrder {
                    return lhs.binding.sortOrder < rhs.binding.sortOrder
                }
                return lhs.project.sortKey < rhs.project.sortKey
            }
            if !groups.isEmpty {
                projectGroups[agentId] = groups
            }
        }

        projectSessionsByAgent = projectGroups
        generalSessionsByAgent = generalGroups
    }

    /// Remove in-memory UI state that belonged to an agent after the CLI has
    /// deleted it from config/workspace. This keeps the sidebar and chat view
    /// from holding onto sessions or task placeholders for an agent that is no
    /// longer selectable.
    func removeDeletedAgentState(agentId: String) {
        let mirroredSessionIds = sessionsByAgent[agentId]?.map(\.id) ?? []
        let storeSessionIds = chatSessionStore.index
            .filter { $0.agentId == agentId }
            .map(\.id)
        let sessionIds = Set(mirroredSessionIds + storeSessionIds)

        for sessionId in sessionIds {
            cancelTasks(inSession: sessionId)
            chatMessagesByInactiveSession.removeValue(forKey: sessionId)
            loadingSessionIds.remove(sessionId)
        }

        chatMessagesByAgent.removeValue(forKey: agentId)
        selectedSessionIdByAgent.removeValue(forKey: agentId)
        pendingSessionMetadataByAgent.removeValue(forKey: agentId)
        sessionsByAgent.removeValue(forKey: agentId)

        if selectedAgentId == agentId {
            selectedAgentId = "main"
            selectedTab = .chat
        }

        chatSessionStore.loadIndex()
        rebuildSessionsMirror()
        sessionsByAgent.removeValue(forKey: agentId)
        recomputeIsSendingMessage()
    }

    /// Strip transient in-flight placeholders with no content. These are
    /// only meaningful while a chat reply is actively streaming — if one
    /// survives onto disk (e.g. the user force-quit the app, or the
    /// `cancel` path's status-flip got coalesced into a "no-op" persist
    /// by a stale equality check), reopening the session would otherwise
    /// resurrect the spinner ("Thinking…" for `.loading`, "Running in
    /// background…" for `.background`) and look like the assistant is
    /// working on a message that no longer exists.
    ///
    /// Covers both statuses; before, only `.loading + empty` was stripped,
    /// so a `.background + empty` placeholder (left behind when a
    /// session was deleted / switched away from with bg in flight, and
    /// the in-memory stash later got lost) would persist forever and
    /// render as "Running in background…" with no actual task behind it.
    static func stripStaleLoadingPlaceholders(_ messages: [ChatMessage]) -> [ChatMessage] {
        return messages.filter {
            !(($0.taskStatus == .loading || $0.taskStatus == .background)
              && $0.content.isEmpty)
        }
    }

    func loadProjectRegistry() {
        guard let snapshot = projectWorkspaceService.loadRegistry() else { return }
        projectsById = Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0) })
        projectBindingsByAgent = Dictionary(grouping: snapshot.bindings, by: \.agentId)
    }

    private func saveProjectRegistry() {
        do {
            try projectWorkspaceService.saveRegistry(
                projects: Array(projectsById.values),
                bindingsByAgent: projectBindingsByAgent
            )
        } catch {
            logChat("PROJECT_REGISTRY_SAVE_FAILED: \(error.localizedDescription)")
        }
    }

    func openProject(forAgent agentId: String) {
        let agentName = agentDisplayName(for: agentId)
        let panel = ProjectWorkspacePicker.makePanel(agentName: agentName)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.attachProject(url, toAgent: agentId)
            }
        }
    }

    private func attachProject(_ url: URL, toAgent agentId: String) {
        let attachment = projectWorkspaceService.attachProject(
            url: url,
            toAgent: agentId,
            projectsById: projectsById,
            bindingsByAgent: projectBindingsByAgent
        )
        projectsById = attachment.projectsById
        projectBindingsByAgent = attachment.bindingsByAgent

        saveProjectRegistry()
        rebuildSessionsMirror()
        createNewSession(forAgent: agentId, projectId: attachment.project.id)

        Task { [projectWorkspaceService] in
            await projectWorkspaceService.bootstrapProject(attachment.project)
        }

        showSuccessMessage("\(agentDisplayName(for: agentId)) is now working in \(attachment.project.displayName)")
    }

    private func agentDisplayName(for agentId: String) -> String {
        availableAgents.first(where: { $0.id == agentId })?.name ?? agentId
    }

    func toggleProjectCollapse(agentId: String, projectId: String) {
        projectBindingsByAgent = projectWorkspaceService.toggleCollapse(
            agentId: agentId,
            projectId: projectId,
            bindingsByAgent: projectBindingsByAgent
        )
        saveProjectRegistry()
        rebuildSessionsMirror()
    }

    func revealProjectInFinder(_ projectId: String) {
        guard let project = projectsById[projectId] else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.rootPath)])
    }

    func removeProject(_ projectId: String, fromAgent agentId: String) {
        projectBindingsByAgent = projectWorkspaceService.removeProject(
            projectId,
            fromAgent: agentId,
            bindingsByAgent: projectBindingsByAgent
        )
        if activeProjectIdByAgent[agentId] == projectId {
            activeProjectIdByAgent.removeValue(forKey: agentId)
        }
        saveProjectRegistry()
        rebuildSessionsMirror()
    }

    /// Load `agentId`'s active session messages into `chatMessagesByAgent`
    /// if they haven't been parsed yet. Called from the `selectedAgentId`
    /// sink so switching to an agent that was deferred at startup parses
    /// its session on first access. Cache hit returns instantly; cache
    /// miss kicks off an async load (with `loadingSessionIds` flipped to
    /// flag the view) so the main thread isn't blocked on a big decode.
    func ensureMessagesLoaded(forAgent agentId: String) {
        guard chatMessagesByAgent[agentId] == nil,
              let sid = selectedSessionIdByAgent[agentId] else {
            return
        }
        if let cached = chatSessionStore.cachedSession(id: sid) {
            chatMessagesByAgent[agentId] = Self.stripStaleLoadingPlaceholders(cached.messages)
            return
        }
        // Cold path — async decode.
        loadingSessionIds.insert(sid)
        Task { [weak self] in
            guard let self = self else { return }
            let target = await self.chatSessionStore.loadSessionAsync(id: sid)
            await MainActor.run {
                // Bail if the user has switched agent again in the
                // meantime — we don't want to clobber their current view.
                guard self.selectedAgentId == agentId,
                      self.selectedSessionIdByAgent[agentId] == sid else {
                    self.loadingSessionIds.remove(sid)
                    return
                }
                if let target = target {
                    self.chatMessagesByAgent[agentId] = Self.stripStaleLoadingPlaceholders(target.messages)
                }
                self.loadingSessionIds.remove(sid)
            }
        }
    }

    /// On launch, restore active sessions for each agent.
    ///
    /// Two-phase load:
    /// - **Eager** (synchronous, on main thread): load the currently-selected
    ///   agent's most-recent session. This is the one the user sees first
    ///   when the chat tab opens, so blocking the main thread for this one
    ///   parse is acceptable — anything else and the UI flashes empty.
    /// - **Lazy** (in a Task): note the session-id for every other agent so
    ///   the sidebar can show them and `selectedSessionIdByAgent` is
    ///   populated, but DON'T load their message bodies yet. Those parse
    ///   on demand when the user switches to that agent (cheap thanks to
    ///   the ChatSessionStore cache hitting once they've loaded once).
    ///
    /// Previously this iterated every agent synchronously and parsed each
    /// agent's full most-recent session, so users with several agents felt
    /// startup as 5+ blocking JSON decodes on the main thread before the
    /// chat view rendered anything.
    func restoreActiveSessionsFromStore() {
        let currentAgent = selectedAgentId
        for (agentId, metas) in sessionsByAgent {
            guard let mostRecent = metas.first else { continue }
            selectedSessionIdByAgent[agentId] = mostRecent.id
            // Only synchronously parse messages for the visible agent.
            if agentId == currentAgent,
               let session = chatSessionStore.loadSession(id: mostRecent.id) {
                chatMessagesByAgent[agentId] = Self.stripStaleLoadingPlaceholders(session.messages)
            }
            // Non-visible agents: leave chatMessagesByAgent[agentId] unset.
            // It'll be populated lazily by switchSession the first time the
            // user clicks into that agent — at which point the parse cost
            // is paid once, then cached.
        }
    }

    /// Mirror every agent's in-memory messages back to its active session on
    /// disk. Called from a debounced sink, so token-by-token streaming
    /// produces one write per ~500ms idle window. Lazily creates a session
    /// the first time an agent gets a message.
    func persistChangedSessions(from dict: [String: [ChatMessage]]) {
        for (agentId, messages) in dict where !messages.isEmpty {
            let sessionId = ensureActiveSessionId(forAgent: agentId, seedMessages: messages)
            let project = activeProject(forAgent: agentId)
            // Start from the on-disk copy when one exists (preserves
            // pin/archive state) or mint a fresh in-memory shell otherwise.
            let loaded = chatSessionStore.loadSession(id: sessionId)
            var session = loaded ?? ChatSession(
                id: sessionId,
                agentId: agentId,
                messages: messages,
                projectId: project?.id,
                projectRoot: project?.rootPath,
                projectDisplayName: project?.displayName
            )

            // Strip stale .loading + empty placeholders before comparing
            // to disk. We never want to persist a placeholder — and the
            // disk side might already have one from a previous app launch
            // that crashed before the placeholder got updated.
            let memMessages = Self.stripStaleLoadingPlaceholders(messages)
            let diskMessages = loaded.map { Self.stripStaleLoadingPlaceholders($0.messages) } ?? []

            // Skip the write only when disk already holds the same trailing
            // state. The check is gated on `loaded != nil` because a
            // freshly-minted pending session (from createNewSession) loads
            // to nil — the fallback constructor pre-populates `messages`,
            // which would make the equality check trivially pass and the
            // first message would never persist.
            //
            // Compare task status + content length in addition to id, so
            // that an in-place status flip (.loading → .cancelled, or a
            // streaming delta appending text) is not coalesced into a
            // no-op write — that was the source of the "session always
            // looks like it's thinking" bug (the spinner placeholder got
            // saved at .loading, then the cancel update was skipped, and
            // disk kept the .loading state forever).
            if let loaded = loaded,
               diskMessages.count == memMessages.count,
               diskMessages.last?.id == memMessages.last?.id,
               diskMessages.last?.taskStatus == memMessages.last?.taskStatus,
               diskMessages.last?.content.count == memMessages.last?.content.count,
               Self.messagesHaveSameActivityEvents(diskMessages.last, memMessages.last),
               !loaded.title.isEmpty {
                continue
            }

            session.messages = memMessages
            session.updatedAt = Date()
            if let project {
                session.projectId = project.id
                session.projectRoot = project.rootPath
                session.projectDisplayName = project.displayName
            }
            // Auto-derive title once, only while still on the placeholder.
            if session.title == ChatSession.defaultTitle {
                session.title = ChatSession.deriveTitle(from: memMessages)
            }
            chatSessionStore.saveSessionDebounced(session)
        }
        // Even if no messages changed, the index may have new metadata
        // (titles, message counts) — rebuild the published mirror.
        rebuildSessionsMirror()
    }

    static func messagesHaveSameActivityEvents(_ lhs: ChatMessage?, _ rhs: ChatMessage?) -> Bool {
        (lhs?.activityEvents ?? []) == (rhs?.activityEvents ?? [])
    }

    static func elapsedMillisecondsText(since start: ContinuousClock.Instant) -> String {
        let duration = start.duration(to: ContinuousClock.now)
        let components = duration.components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.1f", milliseconds)
    }
}
