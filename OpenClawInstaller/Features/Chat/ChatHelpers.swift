//
//  ChatHelpers.swift
//  Chat send pipeline + helpers extracted from DashboardViewModel.
//  P1 refactor: file split only, no behavior change.
//

import Foundation
import AppKit
import os.log

extension DashboardViewModel {

    // MARK: - Chat Helpers

    /// Compose the gateway sessionKey for a given (agent, sessionId) pair.
    ///
    /// Previously this was hardcoded `"agent:<id>:main"` for every session —
    /// so multiple UI "sessions" for the same agent all shared one server
    /// conversation context, leaking memory between them (you'd ask about
    /// X in session A, switch to session B, and the assistant would still
    /// "remember" X). Including the sessionId in the key isolates each UI
    /// session into its own gateway thread.
    func sessionKeyForAgent(_ agentId: String, sessionId: UUID) -> String {
        if let projectId = activeProjectId(forAgent: agentId) {
            return "agent:\(agentId):project:\(projectId):\(sessionId.uuidString)"
        }
        return "agent:\(agentId):\(sessionId.uuidString)"
    }

    func activeProjectId(forAgent agentId: String) -> String? {
        if let sessionId = selectedSessionIdByAgent[agentId],
           let meta = sessionMetadata(for: sessionId) {
            return meta.projectId
        }
        return activeProjectIdByAgent[agentId] ?? nil
    }

    func activeProject(forAgent agentId: String) -> ProjectRecord? {
        guard let projectId = activeProjectId(forAgent: agentId) else { return nil }
        return projectsById[projectId]
    }

    func sessionMetadata(for sessionId: UUID) -> ChatSessionMetadata? {
        if let pending = pendingSessionMetadataByAgent.values.first(where: { $0.id == sessionId }) {
            return pending
        }
        return chatSessionStore.index.first { $0.id == sessionId }
    }

    private struct LocalImageReviewChunkResult {
        let chunkIndex: Int
        let status: String
        let text: String
    }

    private func runLocalImageReviewBatch(
        userText: String,
        attachments: [URL],
        msgId: UUID,
        agentId: String,
        agentEmoji: String?
    ) async {
        let store = ImageReviewBatchStore()

        defer {
            clearTaskTracking(msgId)
        }

        do {
            let batch = try await Task.detached(priority: .utility) {
                try ImageReviewBatchStore().createBatch(from: attachments, messageText: userText)
            }.value

            guard let batch else {
                let error = "No supported image files were found in the uploaded attachments."
                updateMessage(msgId: msgId, content: error, status: .completed, agentId: agentId, agentEmoji: agentEmoji)
                return
            }

            try store.markBatch(batch, status: .running)
            let manifest = try store.loadManifest(for: batch)
            updateMessage(
                msgId: msgId,
                content: localImageReviewProgressMessage(batch: batch, completedChunks: 0),
                status: .loading,
                agentId: agentId,
                agentEmoji: agentEmoji
            )

            var chunkResults: [LocalImageReviewChunkResult] = []
            for chunkIndex in 0..<batch.chunkCount {
                if findMessage(byId: msgId)?.taskStatus == .cancelled {
                    try? store.markBatch(batch, status: .cancelled, completedAt: Date())
                    return
                }

                let entries = manifest.filter { $0.chunkIndex == chunkIndex }
                let prompt = ImageReviewBatchStore.buildChunkReviewPrompt(
                    batch: batch,
                    chunkIndex: chunkIndex,
                    entries: entries,
                    userMessage: userText
                )
                let sessionKey = ImageReviewBatchStore.chunkSessionKey(
                    agentId: agentId,
                    batchId: batch.id,
                    chunkIndex: chunkIndex
                )
                let composerModelOverride = activeComposerModel.trimmingCharacters(in: .whitespacesAndNewlines)
                let chunkResult = await runLocalImageReviewChunk(
                    sessionKey: sessionKey,
                    prompt: prompt,
                    msgId: msgId,
                    modelOverride: composerModelOverride
                )
                let result = LocalImageReviewChunkResult(
                    chunkIndex: chunkIndex,
                    status: chunkResult.status,
                    text: chunkResult.text
                )
                chunkResults.append(result)
                try store.appendChunkResult(
                    batch: batch,
                    chunkIndex: chunkIndex,
                    status: result.status,
                    responseText: result.text
                )

                updateMessage(
                    msgId: msgId,
                    content: localImageReviewProgressMessage(batch: batch, completedChunks: chunkIndex + 1),
                    status: .loading,
                    agentId: agentId,
                    agentEmoji: agentEmoji
                )

                if result.status != "completed" {
                    try store.markBatch(batch, status: .failed, completedAt: Date())
                    updateMessage(
                        msgId: msgId,
                        content: localImageReviewFinalMessage(batch: batch, chunkResults: chunkResults, failed: true),
                        status: .completed,
                        agentId: agentId,
                        agentEmoji: agentEmoji
                    )
                    return
                }
            }

            try writeLocalImageReviewReport(batch: batch, userText: userText, chunkResults: chunkResults)
            try store.markBatch(batch, status: .completed, completedAt: Date())
            _ = try? store.cleanupImageCache()
            updateMessage(
                msgId: msgId,
                content: localImageReviewFinalMessage(batch: batch, chunkResults: chunkResults, failed: false),
                status: .completed,
                agentId: agentId,
                agentEmoji: agentEmoji
            )
        } catch {
            let message = "Local image review batch failed: \(error.localizedDescription)"
            updateMessage(msgId: msgId, content: message, status: .completed, agentId: agentId, agentEmoji: agentEmoji)
        }
    }

    private func runLocalImageReviewChunk(
        sessionKey: String,
        prompt: String,
        msgId: UUID,
        modelOverride: String
    ) async -> (status: String, text: String) {
        let subscriberId = msgId.uuidString
        let eventStream = gatewayClient.subscribeToEvents(subscriberId: subscriberId)
        taskSessionKeyOverride[msgId] = sessionKey

        defer {
            gatewayClient.unsubscribe(subscriberId: subscriberId)
            activeChatRuns.removeValue(forKey: msgId)
            taskSessionKeyOverride.removeValue(forKey: msgId)
        }

        if !modelOverride.isEmpty {
            let patched = await gatewayClient.patchSessionModel(sessionKey: sessionKey, model: modelOverride)
            if !patched {
                chatLog.warning("phase=session_model_patch_failed session=\(sessionKey, privacy: .public) model=\(modelOverride, privacy: .public) — aborting image review chunk to avoid silent model fallback")
                return ("failed", I18n.t("dashboard.chat.modelSwitchFailedNotSent"))
            }
        }

        guard let runId = await gatewayClient.chatSend(sessionKey: sessionKey, message: prompt, attachments: nil) else {
            return ("failed", "Failed to send local image review chunk.")
        }
        activeChatRuns[msgId] = runId

        var accumulatedText = ""
        for await event in eventStream {
            switch event {
            case .delta(let eventRunId, let eventSessionKey, let text):
                guard eventRunId == runId, eventSessionKey == sessionKey, !text.isEmpty else { continue }
                accumulatedText = text
            case .final_(let eventRunId, let eventSessionKey, let text):
                guard eventRunId == runId, eventSessionKey == sessionKey else { continue }
                var finalText = text.isEmpty ? accumulatedText : text
                if finalText.isEmpty,
                   let historyText = await gatewayClient.fetchLastAssistantMessage(sessionKey: sessionKey) {
                    finalText = historyText
                }
                return ("completed", finalText.isEmpty ? "Chunk completed." : finalText)
            case .aborted(let eventRunId, let eventSessionKey):
                guard eventRunId == runId, eventSessionKey == sessionKey else { continue }
                return ("cancelled", accumulatedText)
            case .error(let eventRunId, let eventSessionKey, let message):
                guard eventRunId == runId, eventSessionKey == sessionKey else { continue }
                return ("failed", message)
            case .activity:
                continue
            }
        }
        return ("failed", accumulatedText.isEmpty ? "Connection interrupted before this chunk completed." : accumulatedText)
    }

    private func localImageReviewProgressMessage(batch: ImageReviewBatchStore.Batch, completedChunks: Int) -> String {
        """
        Local image review batch is running.

        Batch ID: \(batch.id)
        Images: \(batch.imageCount)
        Chunks: \(completedChunks)/\(batch.chunkCount)
        Manifest: \(batch.manifestURL.path)
        Results: \(batch.resultsURL.path)
        """
    }

    private func localImageReviewFinalMessage(
        batch: ImageReviewBatchStore.Batch,
        chunkResults: [LocalImageReviewChunkResult],
        failed: Bool
    ) -> String {
        let status = failed ? "Local image review batch stopped before all chunks completed." : "Local image review batch completed."
        let completed = chunkResults.filter { $0.status == "completed" }.count
        return """
        \(status)

        Batch ID: \(batch.id)
        Images: \(batch.imageCount)
        Completed chunks: \(completed)/\(batch.chunkCount)
        Manifest: \(batch.manifestURL.path)
        Chunk results: \(batch.resultsURL.path)
        Report: \(batch.reportURL.path)
        """
    }

    private func writeLocalImageReviewReport(
        batch: ImageReviewBatchStore.Batch,
        userText: String,
        chunkResults: [LocalImageReviewChunkResult]
    ) throws {
        let sections = chunkResults
            .sorted { $0.chunkIndex < $1.chunkIndex }
            .map { result in
                """
                ## Chunk \(result.chunkIndex + 1)

                Status: \(result.status)

                \(result.text)
                """
            }
            .joined(separator: "\n\n")
        let report = """
        # Local Image Review Batch

        Batch ID: \(batch.id)
        Images: \(batch.imageCount)
        Chunks: \(batch.chunkCount)
        Request: \(userText)

        \(sections)
        """
        try Data(report.utf8).write(to: batch.reportURL, options: .atomic)
    }

    private func updateMessage(
        msgId: UUID,
        content: String,
        status: ChatMessage.TaskStatus,
        agentId: String,
        agentEmoji: String?,
        activityEvents: [ChatActivityEvent]? = nil
    ) {
        let existing = findMessage(byId: msgId)
        let resolvedActivityEvents = activityEvents ?? (existing?.activityEvents ?? [])
        let resolvedCompletedAt = status.isTerminal ? (existing?.completedAt ?? Date()) : nil
        let newMsg = ChatMessage(
            role: .assistant, content: content,
            agentId: agentId, agentEmoji: agentEmoji,
            taskStatus: status, id: msgId,
            timestamp: existing?.timestamp,
            completedAt: resolvedCompletedAt,
            activityEvents: resolvedActivityEvents
        )
        // Route to wherever this msgId currently lives. The task may have
        // started in the (then-visible) active session and migrated to
        // chatMessagesByInactiveSession when the user navigated away —
        // stream events still need to find it.
        if let idx = chatMessagesByAgent[agentId]?.firstIndex(where: { $0.id == msgId }) {
            var messages = chatMessagesByAgent[agentId] ?? []
            var didChange = false
            updateMessageIfChanged(newMsg, in: &messages, at: idx, didChange: &didChange)
            guard didChange else {
                logChat("UPDATE_MSG_SKIPPED (active): agent=\(agentId), contentLen=\(content.count), status=\(status), totalMsgs=\(messages.count)")
                return
            }
            chatMessagesByAgent[agentId] = messages
            logChat("UPDATE_MSG (active): agent=\(agentId), contentLen=\(content.count), status=\(status), totalMsgs=\(messages.count)")
            return
        }
        if let sessionId = taskSessionMap[msgId],
           let idx = chatMessagesByInactiveSession[sessionId]?.firstIndex(where: { $0.id == msgId }) {
            var messages = chatMessagesByInactiveSession[sessionId] ?? []
            var didChange = false
            updateMessageIfChanged(newMsg, in: &messages, at: idx, didChange: &didChange)
            guard didChange else {
                logChat("UPDATE_MSG_SKIPPED (inactive): session=\(sessionId.uuidString.prefix(8)), contentLen=\(content.count), status=\(status), totalMsgs=\(messages.count)")
                return
            }
            chatMessagesByInactiveSession[sessionId] = messages
            logChat("UPDATE_MSG (inactive): session=\(sessionId.uuidString.prefix(8)), contentLen=\(content.count), status=\(status), totalMsgs=\(messages.count)")
            return
        }
        logChat("UPDATE_FAILED: agent=\(agentId), msgId=\(msgId.uuidString.prefix(8)) NOT FOUND in active or inactive!")
    }

    private func updateMessageIfChanged(
        _ newMsg: ChatMessage,
        in messages: inout [ChatMessage],
        at idx: Int,
        didChange: inout Bool
    ) {
        guard messages[idx] != newMsg else { return }
        messages[idx] = newMsg
        didChange = true
    }

    private func mergeActivityEvent(_ event: GatewayActivityEvent, into events: inout [ChatActivityEvent]) {
        let kind = ChatActivityEvent.Kind(gatewayKind: event.kind)
        if let idx = events.firstIndex(where: { $0.kind == kind }) {
            let existing = events[idx]
            events[idx] = ChatActivityEvent(
                kind: existing.kind,
                count: existing.count + 1,
                details: event.detail.map { existing.details + [$0] } ?? existing.details,
                ordinal: idx
            )
        } else {
            events.append(ChatActivityEvent(
                kind: kind,
                count: 1,
                details: event.detail.map { [$0] } ?? [],
                ordinal: events.count
            ))
        }
    }

    private func appendProgressActivityText(_ text: String, into events: inout [ChatActivityEvent]) {
        let normalized = Self.normalizedWorkingProgressText(text)
        guard !normalized.isEmpty else { return }
        if events.last?.kind == .progressUpdate, events.last?.detail == normalized {
            return
        }
        events.append(ChatActivityEvent(
            kind: .progressUpdate,
            count: 1,
            details: [normalized],
            ordinal: events.count
        ))
    }

    private func activityEventsForDisplay(
        committedEvents: [ChatActivityEvent],
        accumulatedText: String,
        committedWorkingText: String
    ) -> [ChatActivityEvent] {
        var displayEvents = committedEvents
        appendProgressActivityText(
            Self.uncommittedWorkingProgressText(
                accumulatedText: accumulatedText,
                committedWorkingText: committedWorkingText
            ),
            into: &displayEvents
        )
        return displayEvents
    }

    /// Treat text that appears before the next structured activity as working
    /// transcript. This preserves the model's own progress wording without
    /// parsing language or asking the model for a second summary.
    private static func uncommittedWorkingProgressText(
        accumulatedText: String,
        committedWorkingText: String
    ) -> String {
        guard !accumulatedText.isEmpty else { return "" }
        guard !committedWorkingText.isEmpty else {
            return normalizedWorkingProgressText(accumulatedText)
        }
        if accumulatedText.hasPrefix(committedWorkingText) {
            return normalizedWorkingProgressText(String(accumulatedText.dropFirst(committedWorkingText.count)))
        }
        let commonPrefix = accumulatedText.commonPrefix(with: committedWorkingText)
        guard !commonPrefix.isEmpty else {
            return normalizedWorkingProgressText(accumulatedText)
        }
        return normalizedWorkingProgressText(String(accumulatedText.dropFirst(commonPrefix.count)))
    }

    private static func visibleAssistantText(from text: String, committedWorkingText: String) -> String {
        guard !committedWorkingText.isEmpty, text.hasPrefix(committedWorkingText) else {
            return text
        }
        return String(text.dropFirst(committedWorkingText.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedWorkingProgressText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func appendBackgroundNotification(agentId: String, agentEmoji: String?, completed: Bool, msgId: UUID) {
        let agentName = availableAgents.first(where: { $0.id == agentId })?.name ?? agentId
        if completed {
            let notifyContent = String(format: String(localized: "✅ Background task from **%@** completed", bundle: LanguageManager.shared.localizedBundle), agentName)
            let notifyMsg = ChatMessage(role: .assistant, content: notifyContent, agentId: agentId, agentEmoji: agentEmoji, scrollTargetId: msgId)
            chatMessagesByAgent[agentId, default: []].append(notifyMsg)
        } else {
            let notifyContent = String(format: String(localized: "⚠️ Background task from **%@** timed out", bundle: LanguageManager.shared.localizedBundle), agentName)
            let notifyMsg = ChatMessage(role: .assistant, content: notifyContent, agentId: agentId, agentEmoji: agentEmoji)
            chatMessagesByAgent[agentId, default: []].append(notifyMsg)
        }
    }

    func sendChatMessage(_ text: String, attachments: [URL] = []) async {
        // Route to commander only when the user is on the commander tab
        if let collabVM = collabViewModel, collabVM.isRunning,
           selectedAgentId == "commander",
           !text.hasPrefix("/") {
            let currentAgent = selectedAgentId
            let userMessage = ChatMessage(role: .user, content: text)
            chatMessagesByAgent[currentAgent, default: []].append(userMessage)
            isSendingMessage = true
            let reply = await collabVM.handleUserMessage(text)
            let noReply = String(localized: "No response from AI.", bundle: LanguageManager.shared.localizedBundle)
            chatMessagesByAgent[currentAgent, default: []].append(ChatMessage(role: .assistant, content: reply ?? noReply, agentId: "commander"))
            isSendingMessage = false
            return
        }

        let userMessage = ChatMessage(role: .user, content: text, attachments: attachments)
        let currentAgentId = selectedAgentId
        chatMessagesByAgent[currentAgentId, default: []].append(userMessage)
        logChat("USER_MSG: agent=\(currentAgentId), totalMsgs=\(chatMessagesByAgent[currentAgentId]?.count ?? 0)")

        let currentAgentEmoji: String? = nil
        // Bind the run to the agent's currently-active session. `ensureActiveSessionId`
        // mints one lazily if the agent has never had a session before, so this is
        // always non-nil after the call.
        let currentSessionId = ensureActiveSessionId(forAgent: currentAgentId,
                                                     seedMessages: chatMessagesByAgent[currentAgentId] ?? [])
        let sessionKey = sessionKeyForAgent(currentAgentId, sessionId: currentSessionId)
        let currentProject = activeProject(forAgent: currentAgentId)

        // Insert a placeholder assistant message for streaming updates
        let msgId = UUID()
        let placeholderMsg = ChatMessage(role: .assistant, content: "", agentId: currentAgentId, agentEmoji: currentAgentEmoji, taskStatus: .loading, id: msgId)
        chatMessagesByAgent[currentAgentId, default: []].append(placeholderMsg)
        logChat("PLACEHOLDER: agent=\(currentAgentId), msgId=\(msgId.uuidString.prefix(8)), totalMsgs=\(chatMessagesByAgent[currentAgentId]?.count ?? 0)")

        // Track as foreground task — bound to BOTH agent and session so we can
        // (a) route the cancel/abort to the right gateway sessionKey and
        // (b) decide which UI session owns this spinner.
        foregroundTaskIds.insert(msgId)
        taskAgentMap[msgId] = currentAgentId
        taskSessionMap[msgId] = currentSessionId
        taskSessionKeyOverride[msgId] = sessionKey
        recomputeIsSendingMessage()

        // Check gateway connection. Prefer the gateway's own rejection reason
        // (e.g. NOT_PAIRED / DEVICE_IDENTITY_REQUIRED, token mismatch) so the user
        // can act on it; only fall back to the generic message when we never got
        // a server response (TCP failed / handshake never reached the auth step).
        guard gatewayClient.isConnected else {
            let generic = String(localized: "Gateway is not connected. Please check the service status.", bundle: LanguageManager.shared.localizedBundle)
            let errorMsg: String
            if let lastErr = gatewayClient.lastConnectError {
                let detail = lastErr.detailCode.map { " (\($0))" } ?? ""
                errorMsg = "\(generic)\n[\(lastErr.code)\(detail)] \(lastErr.message)"
            } else {
                errorMsg = generic
            }
            updateMessage(msgId: msgId, content: errorMsg, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
            clearTaskTracking(msgId)
            return
        }

        if ImageReviewBatchStore.isImageReviewBatchCandidate(
            urls: attachments,
            messageText: text,
            selectedAgentId: currentAgentId
        ) {
            await runLocalImageReviewBatch(
                userText: text,
                attachments: attachments,
                msgId: msgId,
                agentId: currentAgentId,
                agentEmoji: currentAgentEmoji
            )
            return
        }

        let processed = attachmentProcessor.process(attachments)
        let baseMessage = text
            + ProjectSessionContextBuilder.message(for: currentProject)
            + processed.manifestText
        let composerModelOverride = activeComposerModel.trimmingCharacters(in: .whitespacesAndNewlines)

        // Subscribe to events BEFORE sending to avoid race condition
        let subscriberId = msgId.uuidString
        let eventStream = gatewayClient.subscribeToEvents(subscriberId: subscriberId)

        // Apply the composer model as a session-level override. If an explicit
        // composer model cannot be applied, stop the turn instead of silently
        // running on the session's current/fallback model.
        if !composerModelOverride.isEmpty, appliedSessionModels[sessionKey] != composerModelOverride {
            let patched = await gatewayClient.patchSessionModel(sessionKey: sessionKey, model: composerModelOverride)
            if patched {
                appliedSessionModels[sessionKey] = composerModelOverride
            } else {
                appliedSessionModels.removeValue(forKey: sessionKey)
                chatLog.warning("phase=session_model_patch_failed session=\(sessionKey, privacy: .public) model=\(composerModelOverride, privacy: .public) — aborting send to avoid silent model fallback")
                let modelSwitchFailureMessage = I18n.t("dashboard.chat.modelSwitchFailedNotSent")
                showErrorMessage(modelSwitchFailureMessage)
                updateMessage(
                    msgId: msgId,
                    content: modelSwitchFailureMessage,
                    status: .completed,
                    agentId: currentAgentId,
                    agentEmoji: currentAgentEmoji
                )
                clearTaskTracking(msgId)
                gatewayClient.unsubscribe(subscriberId: subscriberId)
                return
            }
        }

        // Send the message
        let chatSendStart = ContinuousClock.now
        chatLog.info("phase=chat_send_start agent=\(currentAgentId, privacy: .public) session=\(currentSessionId.uuidString, privacy: .public) sessionKey=\(sessionKey, privacy: .public) model_override=\(composerModelOverride.isEmpty ? "default" : composerModelOverride, privacy: .public) message_len=\(baseMessage.count, privacy: .public) attachment_count=\(attachments.count, privacy: .public) inline_attachment_count=\(processed.inlineAttachments.count, privacy: .public)")
        let runId = await gatewayClient.chatSend(
            sessionKey: sessionKey,
            message: baseMessage,
            attachments: processed.inlineAttachments.isEmpty ? nil : processed.inlineAttachments
        )

        guard let runId = runId else {
            chatLog.warning("phase=chat_send_failed agent=\(currentAgentId, privacy: .public) session=\(currentSessionId.uuidString, privacy: .public) elapsed_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public)")
            let errorMsg = String(localized: "Failed to send message. Please try again.", bundle: LanguageManager.shared.localizedBundle)
            updateMessage(msgId: msgId, content: errorMsg, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
            gatewayClient.unsubscribe(subscriberId: subscriberId)
            clearTaskTracking(msgId)
            return
        }

        let chatSendAckAt = ContinuousClock.now
        chatLog.info("phase=chat_send_ack runId=\(runId, privacy: .public) agent=\(currentAgentId, privacy: .public) session=\(currentSessionId.uuidString, privacy: .public) elapsed_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public)")

        if !attachments.isEmpty {
            showSuccessMessage("Attachments sent as a selective manifest. Large files and folders will not be read wholesale.")
        }

        activeChatRuns[msgId] = runId
        chatLog.info("chat.send ok: runId=\(runId), subscriberId=\(subscriberId), bgTasks=\(self.backgroundTaskIds.count)")

        // Persist the run so we can recover via chat.history if the
        // app dies before the stream completes (force-quit, crash, OOM).
        // Removed in the defer block below on normal stream exit, so
        // typical runs never leave a stale entry.
        registerInFlightRun(
            runId: runId,
            sessionKey: sessionKey,
            msgId: msgId,
            sessionId: currentSessionId,
            agentId: currentAgentId,
            agentEmoji: currentAgentEmoji
        )

        // Abandonment safety net: only triggers when NO inbound traffic at all for the
        // entire `inactivityLimit` window. Modeled after Claude's API/SSE behavior — we
        // never want to declare a task failed purely because deltas came infrequently
        // (deep-thinking + long tools can be naturally silent for many minutes). The
        // 30s client heartbeat already proves WS liveness independently; this timer is
        // pure defense-in-depth for genuinely abandoned runs.
        //
        // Claude-style "prefer resume over fail": before marking `.timedOut`, attempt
        // a `chat.history` fetch first. If the gateway has more content than our
        // placeholder, the run actually completed gateway-side and we just missed the
        // final event (possible after long lid-closed sleep, dropped reconnect race,
        // etc.). Recover cleanly to `.completed` instead of falsely marking failed.
        let inactivityLimit: TimeInterval = inactivityTimeoutSeconds  // user-tunable, default 60 min
        let timeoutTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // check every 10s
                guard let self = self, !Task.isCancelled else { return }
                // Use the gateway-level timestamp: any inbound message resets it; nothing for
                // `inactivityLimit` means we're not getting anything (including ack/delta) from gateway.
                let elapsed = Date().timeIntervalSince(self.gatewayClient.lastMessageReceivedAt)
                if elapsed >= inactivityLimit {
                    if self.activeChatRuns[msgId] != nil {
                        // Step 1: try history recovery before declaring failure.
                        // 10s budget (matches GatewayClient.fetchLastAssistantMessage's own timeout).
                        let recovered = await self.gatewayClient.fetchLastAssistantMessage(sessionKey: sessionKey)
                        self.gatewayClient.unsubscribe(subscriberId: subscriberId)

                        await MainActor.run {
                            // Snapshot current placeholder length so we only adopt history
                            // if it strictly extends what we already have. Otherwise (history
                            // empty / shorter / unchanged) fall to the timedOut path.
                            let currentLen = self.findMessage(byId: msgId)?.content.count ?? 0
                            if let text = recovered, text.count > currentLen, !text.isEmpty {
                                chatLog.info("inactivity recovery succeeded: \(text.count) chars from history (placeholder had \(currentLen))")
                                self.updateMessage(msgId: msgId, content: text, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
                            } else {
                                chatLog.warning("inactivity timeout: no usable history, marking timedOut (elapsed=\(Int(elapsed))s)")
                                let timeoutMsg = String(localized: "The task timed out and has been terminated. You can try again or switch to another agent.", bundle: LanguageManager.shared.localizedBundle)
                                if let msg = self.findMessage(byId: msgId) {
                                    let content = msg.content.isEmpty
                                        ? timeoutMsg
                                        : msg.content + "\n\n---\n> ⚠️ " + timeoutMsg
                                    self.updateMessage(msgId: msgId, content: content, status: .timedOut, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
                                }
                            }
                            self.clearTaskTracking(msgId)
                        }
                    }
                    return
                }
            }
        }

        // Guarantee cleanup: no matter how the stream loop exits, reset state
        defer {
            timeoutTask.cancel()
            gatewayClient.unsubscribe(subscriberId: subscriberId)
            // Cleanup must happen on MainActor since these are @Published properties
            Task { @MainActor in
                self.clearTaskTracking(msgId)
                self.unregisterInFlightRun(msgId: msgId)
            }
        }

        // Stream events
        var accumulatedText = ""
        var committedWorkingText = ""
        var accumulatedActivityEvents: [ChatActivityEvent] = []
        var seenActivityEventKeys = Set<String>()
        var receivedTerminalEvent = false
        var emptyFinalCount = 0
        // Throttle message updates to prevent CPU 100% during fast streaming
        var lastUpdateTime = Date()
        let updateThrottleInterval: TimeInterval = 0.1  // Update at most every 100ms
        var didLogFirstEvent = false
        var didLogFirstDelta = false
        var didLogFirstActivity = false

        func logFirstGatewayEventIfNeeded(kind: String, eventRunId: String, eventSessionKey: String?) {
            guard !didLogFirstEvent else { return }
            didLogFirstEvent = true
            chatLog.info("phase=chat_first_event kind=\(kind, privacy: .public) runId=\(eventRunId, privacy: .public) sessionKey=\(eventSessionKey ?? "nil", privacy: .public) elapsed_from_send_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public) elapsed_after_ack_ms=\(Self.elapsedMillisecondsText(since: chatSendAckAt), privacy: .public)")
        }

        streamLoop: for await event in eventStream {

            switch event {
            case .activity(let eventRunId, _, let event):
                guard eventRunId == runId else { continue }
                logFirstGatewayEventIfNeeded(kind: "activity", eventRunId: eventRunId, eventSessionKey: nil)
                if !didLogFirstActivity {
                    didLogFirstActivity = true
                    chatLog.info("phase=chat_first_activity runId=\(eventRunId, privacy: .public) kind=\(event.kind.rawValue, privacy: .public) elapsed_from_send_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public) elapsed_after_ack_ms=\(Self.elapsedMillisecondsText(since: chatSendAckAt), privacy: .public)")
                }
                guard seenActivityEventKeys.insert(event.dedupeKey).inserted else { continue }
                let progressText = Self.uncommittedWorkingProgressText(
                    accumulatedText: accumulatedText,
                    committedWorkingText: committedWorkingText
                )
                if !progressText.isEmpty {
                    appendProgressActivityText(progressText, into: &accumulatedActivityEvents)
                    committedWorkingText = accumulatedText
                }
                mergeActivityEvent(event, into: &accumulatedActivityEvents)
                if let current = findMessage(byId: msgId),
                   current.taskStatus != .cancelled {
                    updateMessage(msgId: msgId, content: "", status: current.taskStatus, agentId: currentAgentId, agentEmoji: currentAgentEmoji, activityEvents: accumulatedActivityEvents)
                }

            case .delta(let eventRunId, let eventSessionKey, let text):
                guard eventRunId == runId else { continue }
                logFirstGatewayEventIfNeeded(kind: "delta", eventRunId: eventRunId, eventSessionKey: eventSessionKey)
                // Skip empty deltas (e.g. tool_use blocks with no text content)
                guard !text.isEmpty else {
                    chatLog.debug("chat delta: EMPTY text skipped, runId=\(eventRunId)")
                    continue
                }
                if !didLogFirstDelta {
                    didLogFirstDelta = true
                    chatLog.info("phase=chat_first_delta runId=\(eventRunId, privacy: .public) sessionKey=\(eventSessionKey, privacy: .public) text_len=\(text.count, privacy: .public) elapsed_from_send_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public) elapsed_after_ack_ms=\(Self.elapsedMillisecondsText(since: chatSendAckAt), privacy: .public)")
                }
                chatLog.debug("chat delta: runId=\(eventRunId), textLen=\(text.count)")
                // Gateway sends full accumulated text in each delta, so use replacement
                accumulatedText = text
                // A real delta arrived — reset the premature-final counter
                emptyFinalCount = 0

                // Only update UI if enough time has passed (throttle to prevent CPU 100%)
                let now = Date()
                if now.timeIntervalSince(lastUpdateTime) >= updateThrottleInterval {
                    lastUpdateTime = now
                    // Only update if not already in a terminal state. The
                    // placeholder may live in chatMessagesByAgent[agentId]
                    // (session still visible) or in chatMessagesByInactiveSession
                    // (user navigated to a different session mid-stream) —
                    // findMessage handles both.
                    if let current = findMessage(byId: msgId),
                       current.taskStatus != .cancelled {
                        let displayEvents = activityEventsForDisplay(
                            committedEvents: accumulatedActivityEvents,
                            accumulatedText: accumulatedText,
                            committedWorkingText: committedWorkingText
                        )
                        updateMessage(msgId: msgId, content: "", status: current.taskStatus, agentId: currentAgentId, agentEmoji: currentAgentEmoji, activityEvents: displayEvents)
                    }
                }

            case .final_(let eventRunId, let eventSessionKey, let text):
                guard eventRunId == runId else { continue }
                logFirstGatewayEventIfNeeded(kind: "final", eventRunId: eventRunId, eventSessionKey: eventSessionKey)
                chatLog.info("phase=chat_final runId=\(eventRunId, privacy: .public) sessionKey=\(eventSessionKey, privacy: .public) text_len=\(text.count, privacy: .public) accumulated_len=\(accumulatedText.count, privacy: .public) saw_delta=\(didLogFirstDelta, privacy: .public) elapsed_from_send_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public) elapsed_after_ack_ms=\(Self.elapsedMillisecondsText(since: chatSendAckAt), privacy: .public)")
                chatLog.info("chat final: runId=\(eventRunId), textLen=\(text.count), accumulatedLen=\(accumulatedText.count)")
                var finalText = Self.visibleAssistantText(
                    from: text.isEmpty ? accumulatedText : text,
                    committedWorkingText: committedWorkingText
                )
                // Fallback: when gateway final has no content (e.g. tool-heavy responses where
                // stripInlineDirectiveTagsForDisplay filtered all text), fetch from chat history
                if finalText.isEmpty {
                    chatLog.info("chat final empty — fetching chat.history as fallback")
                    if let historyText = await gatewayClient.fetchLastAssistantMessage(sessionKey: eventSessionKey) {
                        chatLog.info("chat.history fallback: got \(historyText.count) chars")
                        finalText = Self.visibleAssistantText(
                            from: historyText,
                            committedWorkingText: committedWorkingText
                        )
                    }
                }
                // If still no content, the gateway may have sent a premature final
                // while the task is still running (e.g. intermediate sub-run ended).
                // Skip the first empty final, but accept on the second — to avoid
                // background tasks getting stuck in "running" state forever.
                if finalText.isEmpty {
                    emptyFinalCount += 1
                    if emptyFinalCount < 2 {
                        chatLog.warning("chat final has no content — ignoring premature final #\(emptyFinalCount), continuing to wait")
                        continue
                    }
                    chatLog.warning("chat final has no content — accepting after \(emptyFinalCount) empty finals")
                    let doneMsg = String(localized: "Task completed.", bundle: LanguageManager.shared.localizedBundle)
                    finalText = doneMsg
                }
                receivedTerminalEvent = true
                let wasBackground = backgroundTaskIds.contains(msgId)
                updateMessage(msgId: msgId, content: finalText, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji, activityEvents: accumulatedActivityEvents)
                if wasBackground {
                    // Only emit the "background task completed" inline card when the
                    // user is still looking at the SAME session the task ran in.
                    // Otherwise we'd append it into whatever session is currently
                    // active for this agent — and `persistChangedSessions` would
                    // later save that orphan line into the wrong session's JSON
                    // (the v1.1.49 / v1.1.50 cross-session "answer in another
                    // conversation" bug). The real reply was already routed to
                    // the right place via `updateMessage` above, so navigating
                    // back to the original session shows the completed turn
                    // naturally — no notification needed there either.
                    if selectedSessionIdByAgent[currentAgentId] == taskSessionMap[msgId] {
                        appendBackgroundNotification(agentId: currentAgentId, agentEmoji: currentAgentEmoji, completed: true, msgId: msgId)
                    }
                }
                break streamLoop

            case .aborted(let eventRunId, _):
                guard eventRunId == runId else { continue }
                logFirstGatewayEventIfNeeded(kind: "aborted", eventRunId: eventRunId, eventSessionKey: nil)
                chatLog.info("phase=chat_aborted runId=\(eventRunId, privacy: .public) elapsed_from_send_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public) elapsed_after_ack_ms=\(Self.elapsedMillisecondsText(since: chatSendAckAt), privacy: .public)")
                receivedTerminalEvent = true
                if let current = findMessage(byId: msgId),
                   current.taskStatus != .cancelled {
                    updateMessage(msgId: msgId, content: "", status: .cancelled, agentId: currentAgentId, agentEmoji: currentAgentEmoji, activityEvents: accumulatedActivityEvents)
                }
                break streamLoop

            case .error(let eventRunId, _, let message):
                guard eventRunId == runId else { continue }
                logFirstGatewayEventIfNeeded(kind: "error", eventRunId: eventRunId, eventSessionKey: nil)
                chatLog.warning("phase=chat_error runId=\(eventRunId, privacy: .public) message_len=\(message.count, privacy: .public) elapsed_from_send_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public) elapsed_after_ack_ms=\(Self.elapsedMillisecondsText(since: chatSendAckAt), privacy: .public)")
                receivedTerminalEvent = true
                let errorContent = "⚠️ " + message
                // Ensure UI update happens on MainActor
                await MainActor.run {
                    self.updateMessage(msgId: msgId, content: errorContent, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji, activityEvents: accumulatedActivityEvents)
                }
                chatLog.warning("chat error: runId=\(runId), message=\(message)")
                break streamLoop
            }
        }

        // Stream ended without a terminal event — typically WebSocket dropped
        // (sleep / network blip / gateway restart) and `scheduleReconnect()`
        // finished our event continuations. Don't immediately declare the
        // task dead: in many cases the run actually COMPLETED on the gateway
        // during the disconnect window (LLM provider doesn't know about our
        // client disconnect), and we can recover the final reply via
        // `chat.history`.
        //
        // Strategy:
        //   1. Give WS up to 15s to reconnect (usual reconnect window is
        //      1-3s, longer on system wake from sleep)
        //   2. Once back online, ask gateway for the last assistant
        //      message in this session via `chat.history`
        //   3. If history has more content than we streamed → use it,
        //      mark `.completed` cleanly with no "interrupted" notice
        //   4. If history has nothing or is shorter → fall through to
        //      the legacy "Connection was interrupted" path
        if !receivedTerminalEvent {
            chatLog.warning("chat stream ended WITHOUT terminal event: runId=\(runId), accumulatedLen=\(accumulatedText.count) — attempting chat.history recovery")

            // Wait briefly for the WS to come back. Poll every 0.5s
            // rather than blocking on a single 30s sleep so we recover
            // as soon as the gateway is reachable.
            //
            // 30s window: must strictly exceed our reconnect backoff
            // ceiling (1+2+4+8 = 15s for the 4th attempt) plus the
            // connect.challenge round-trip + auth (~1-3s). 15s exactly
            // matched the backoff tail and lost the race on the 4th
            // retry; 30s gives the handshake comfortable headroom and
            // matches Anthropic SSE's typical reconnect tolerance.
            var recovered: String? = nil
            let recoveryDeadline = Date().addingTimeInterval(30)
            while Date() < recoveryDeadline {
                if gatewayClient.isConnected {
                    recovered = await gatewayClient.fetchLastAssistantMessage(sessionKey: sessionKey)
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            if let current = findMessage(byId: msgId),
               current.taskStatus != .completed && current.taskStatus != .cancelled && current.taskStatus != .timedOut {
                // Prefer history if it returned strictly more content than
                // what we managed to capture via streaming. The history
                // endpoint returns the FULL final assistant turn if the
                // run completed gateway-side, so this transparently
                // covers the "system slept while LLM finished" case.
                if let recoveredText = recovered, recoveredText.count > accumulatedText.count {
                    chatLog.info("chat.history recovered \(recoveredText.count) chars (streamed only \(accumulatedText.count))")
                    let recoveredVisibleText = Self.visibleAssistantText(
                        from: recoveredText,
                        committedWorkingText: committedWorkingText
                    )
                    updateMessage(msgId: msgId, content: recoveredVisibleText, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji, activityEvents: accumulatedActivityEvents)
                } else {
                    chatLog.warning("chat.history recovery failed or shorter than stream — marking interrupted")
                    let disconnectNote = String(localized: "Connection was interrupted. The response may be incomplete.", bundle: LanguageManager.shared.localizedBundle)
                    updateMessage(msgId: msgId, content: disconnectNote, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji, activityEvents: accumulatedActivityEvents)
                }
            }
        }
    }

    /// Move a foreground task to background, unlocking the input
    func moveTaskToBackground(_ msgId: UUID) {
        guard foregroundTaskIds.contains(msgId) else { return }
        foregroundTaskIds.remove(msgId)
        backgroundTaskIds.insert(msgId)
        recomputeIsSendingMessage()

        let bgLabel = String(localized: "⏳ Task running in background...", bundle: LanguageManager.shared.localizedBundle)

        // First look in the active per-agent map (the common case — auto-bg
        // fires from ThinkingIndicator which only renders for visible
        // placeholders).
        for agentId in chatMessagesByAgent.keys {
            if let idx = chatMessagesByAgent[agentId]?.firstIndex(where: { $0.id == msgId }) {
                let msg = chatMessagesByAgent[agentId]![idx]
                let content = msg.content.isEmpty ? bgLabel : msg.content
                var messages = chatMessagesByAgent[agentId]!
                let updated = msg.withTaskStatus(.background, content: content)
                messages[idx] = updated
                chatMessagesByAgent[agentId] = messages
                return
            }
        }

        // Fall back to the inactive stash. Reachable when the auto-bg
        // timer fires within the ~1s window between the user switching
        // sessions and `.onDisappear` cancelling the timer — without
        // this branch the placeholder keeps showing "Thinking…" forever
        // when the user navigates back, even though the task is
        // already tracked as background internally.
        if let sessionId = taskSessionMap[msgId],
           let idx = chatMessagesByInactiveSession[sessionId]?.firstIndex(where: { $0.id == msgId }) {
            let msg = chatMessagesByInactiveSession[sessionId]![idx]
            let content = msg.content.isEmpty ? bgLabel : msg.content
            var messages = chatMessagesByInactiveSession[sessionId]!
            let updated = msg.withTaskStatus(.background, content: content)
            messages[idx] = updated
            chatMessagesByInactiveSession[sessionId] = messages
        }
    }

    /// Cancel an in-progress chat task.
    /// Sends chat.abort via WebSocket and terminates the event stream.
    func cancelChat(_ msgId: UUID) {
        // 1. Look up runId and send abort via gateway WebSocket.
        //    Build sessionKey from the TASK's bound (agent, session), not
        //    the currently-active one — callers like cancelTasks(inSession:)
        //    pass msgIds from sessions that may no longer be selected.
        let runId = activeChatRuns[msgId]
        if let sessionKey = taskSessionKeyOverride[msgId] {
            Task {
                _ = await gatewayClient.abortChat(sessionKey: sessionKey, runId: runId)
            }
        } else {
            chatLog.warning("cancelChat: no session bound to msgId \(msgId.uuidString.prefix(8)) — abort skipped")
        }

        // 2. Terminate the event stream for this message
        gatewayClient.unsubscribe(subscriberId: msgId.uuidString)
        activeChatRuns.removeValue(forKey: msgId)

        // 3. Update message status to cancelled — message may live in
        // chatMessagesByAgent (visible session) or chatMessagesByInactiveSession
        // (background-streaming session). updateMessage handles both.
        if let msg = findMessage(byId: msgId) {
            updateMessage(msgId: msgId, content: msg.content,
                          status: .cancelled,
                          agentId: msg.agentId ?? taskAgentMap[msgId] ?? selectedAgentId,
                          agentEmoji: msg.agentEmoji)
        }

        // 4. Cleanup tracking
        clearTaskTracking(msgId)
    }

    /// Filter out system prompt lines from openclaw agent output
    nonisolated static func filterAgentOutput(_ output: String?) -> String? {
        guard let output = output else { return nil }
        // Strip ANSI escape codes first
        let ansiPattern = "\u{1B}\\[[0-9;]*[a-zA-Z]"
        let cleaned = output.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)
        let filtered = cleaned
            .components(separatedBy: "\n")
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return true }
                if trimmed.hasPrefix("[agent-scope]") { return false }
                if trimmed.hasPrefix("[plugins]") { return false }
                if trimmed.hasPrefix("[agent/embedded]") { return false }
                if trimmed.hasPrefix("Gateway agent failed") { return false }
                if trimmed.hasPrefix("Gateway target:") { return false }
                if trimmed.hasPrefix("Source: local") { return false }
                if trimmed.hasPrefix("Bind: loopback") { return false }
                if trimmed.hasPrefix("Config:") && trimmed.contains("openclaw.json") { return false }
                if trimmed.hasPrefix("Config warnings:") { return false }
                if trimmed.hasPrefix("Config overwrite:") { return false }
                if trimmed.hasPrefix("- plugins.") { return false }
                if trimmed.hasPrefix("- ") && trimmed.contains("plugin") && trimmed.contains("detected") { return false }
                if trimmed.contains("plugins.allow is empty") { return false }
                if trimmed.contains("Multiple agents marked default") { return false }
                return true
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return filtered.isEmpty ? nil : filtered
    }

    func clearChat() {
        chatMessages.removeAll()
        // Reset the backend session for the current (agent, session) so the
        // next message starts with a clean gateway context. Falls back to
        // doing nothing if we somehow don't have an active session — better
        // than wiping the wrong session.
        guard let sid = selectedSessionIdByAgent[selectedAgentId] else { return }
        resetAgentSession(agentId: selectedAgentId, sessionId: sid)
    }

    /// Reset the backend session files for a specific (agent, session) so
    /// the next message starts fresh — without nuking other UI sessions
    /// the user has for the same agent.
    private func resetAgentSession(agentId: String, sessionId: UUID) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let sessionsDir = "\(homeDir)/.openclaw/agents/\(agentId)/sessions"
        let sessionsJsonPath = "\(sessionsDir)/sessions.json"
        let fm = FileManager.default

        // Look up the gateway session-id mapped to *this* UI session's
        // sessionKey, not the legacy "agent:X:main" catch-all. Match the key
        // CASE-INSENSITIVELY: the client builds sessionKey with Swift's
        // UPPERCASE `UUID.uuidString`, but the gateway stores it LOWERCASE — an
        // exact match silently missed, so this reset was a no-op on the gateway
        // side (it only cleared the local mirror, never the gateway context).
        let sessionKey = sessionKeyForAgent(agentId, sessionId: sessionId).lowercased()
        guard let data = fm.contents(atPath: sessionsJsonPath),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actualKey = root.keys.first(where: { $0.lowercased() == sessionKey }),
              let entry = root[actualKey] as? [String: Any],
              let gwSessionId = entry["sessionId"] as? String else {
            NSLog("[Chat] resetAgentSession: no active session found for %@", agentId)
            return
        }

        // Rename the .jsonl file to .jsonl.reset.<timestamp>
        let jsonlPath = "\(sessionsDir)/\(gwSessionId).jsonl"
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupPath = "\(jsonlPath).reset.\(timestamp)"
        if fm.fileExists(atPath: jsonlPath) {
            try? fm.moveItem(atPath: jsonlPath, toPath: backupPath)
            NSLog("[Chat] resetAgentSession: renamed %@ -> %@", jsonlPath, backupPath)
        }

        // Remove the session entry from sessions.json so backend creates a new one
        root.removeValue(forKey: actualKey)
        if let updatedData = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? updatedData.write(to: URL(fileURLWithPath: sessionsJsonPath))
            NSLog("[Chat] resetAgentSession: removed session key %@ from sessions.json", actualKey)
        }
    }
}
