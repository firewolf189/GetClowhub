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
        // The gateway canonicalizes session keys to lowercase and stamps that
        // canonical form on every chat event. UUID().uuidString is uppercase, so
        // an uppercase key here would fail the case-sensitive sessionKey guards
        // on the receive path (hub routing + consumer loops) and every reply
        // would be silently dropped. Speak the gateway's canonical form.
        if let projectId = activeProjectId(forAgent: agentId) {
            return "agent:\(agentId):project:\(projectId):\(sessionId.uuidString)".lowercased()
        }
        return "agent:\(agentId):\(sessionId.uuidString)".lowercased()
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

    /// Revalidates run ownership after an awaited pre-send operation. A late
    /// model-patch result must not overwrite cancellation or a newer child run.
    private func canContinueChatRunAfterPreflight(
        messageId: UUID,
        sessionKey: String,
        idempotencyKey: String
    ) -> Bool {
        guard let run = taskState.run(for: messageId),
              !run.phase.isTerminal,
              run.gatewayBinding.sessionKey == sessionKey,
              run.gatewayBinding.idempotencyKey == idempotencyKey else {
            return false
        }
        guard !run.cancellationRequested else {
            if case .preparing = run.phase {
                finishCancelledChatRun(messageId)
            }
            return false
        }
        return true
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

        do {
            let batch = try await Task.detached(priority: .utility) {
                try ImageReviewBatchStore().createBatch(from: attachments, messageText: userText)
            }.value

            guard taskState.run(for: msgId) != nil else { return }

            guard let batch else {
                let error = "No supported image files were found in the uploaded attachments."
                finishChatRun(messageId: msgId, outcome: .failed(message: error))
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
                if taskState.run(for: msgId)?.cancellationRequested == true {
                    try? store.markBatch(batch, status: .cancelled, completedAt: Date())
                    finishChatRun(messageId: msgId, outcome: .cancelled)
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

                if result.status == "cancelled" {
                    try store.markBatch(batch, status: .cancelled, completedAt: Date())
                    finishChatRun(messageId: msgId, outcome: .cancelled)
                    return
                }

                if result.status != "completed" {
                    try store.markBatch(batch, status: .failed, completedAt: Date())
                    finishChatRun(
                        messageId: msgId,
                        outcome: .failed(
                            message: localImageReviewFinalMessage(
                                batch: batch,
                                chunkResults: chunkResults,
                                failed: true
                            )
                        )
                    )
                    return
                }

                updateMessage(
                    msgId: msgId,
                    content: localImageReviewProgressMessage(batch: batch, completedChunks: chunkIndex + 1),
                    status: .loading,
                    agentId: agentId,
                    agentEmoji: agentEmoji
                )
            }

            try writeLocalImageReviewReport(batch: batch, userText: userText, chunkResults: chunkResults)
            try store.markBatch(batch, status: .completed, completedAt: Date())
            _ = try? store.cleanupImageCache()
            finishChatRun(
                messageId: msgId,
                outcome: .completed(
                    text: localImageReviewFinalMessage(
                        batch: batch,
                        chunkResults: chunkResults,
                        failed: false
                    )
                )
            )
        } catch {
            let message = "Local image review batch failed: \(error.localizedDescription)"
            finishChatRun(messageId: msgId, outcome: .failed(message: message))
        }
    }

    private func runLocalImageReviewChunk(
        sessionKey: String,
        prompt: String,
        msgId: UUID,
        modelOverride: String
    ) async -> (status: String, text: String) {
        let subscriberId = msgId.uuidString
        let idempotencyKey = UUID().uuidString
        let eventStream = gatewayClient.subscribeToEvents(
            subscriberId: subscriberId,
            runId: idempotencyKey,
            sessionKey: sessionKey
        )
        taskState.prepareGatewayRun(
            messageId: msgId,
            sessionKey: sessionKey,
            idempotencyKey: idempotencyKey
        )

        defer {
            gatewayClient.unsubscribe(subscriberId: subscriberId)
        }

        if !modelOverride.isEmpty {
            let patched = await gatewayClient.patchSessionModel(sessionKey: sessionKey, model: modelOverride)
            guard canContinueChatRunAfterPreflight(
                messageId: msgId,
                sessionKey: sessionKey,
                idempotencyKey: idempotencyKey
            ) else {
                return ("cancelled", "")
            }
            if !patched {
                chatLog.warning("phase=session_model_patch_failed session=\(sessionKey, privacy: .public) model=\(modelOverride, privacy: .public) — aborting image review chunk to avoid silent model fallback")
                return ("failed", I18n.t("dashboard.chat.modelSwitchFailedNotSent"))
            }
        }

        guard let runBeforeSend = taskState.run(for: msgId) else {
            return ("cancelled", "")
        }
        if runBeforeSend.cancellationRequested {
            return ("cancelled", "")
        }

        taskState.applyRunEvent(messageId: msgId, event: .sendStarted)
        let sendResult = await gatewayClient.chatSend(
            sessionKey: sessionKey,
            message: prompt,
            idempotencyKey: idempotencyKey,
            attachments: nil
        )
        var runId = idempotencyKey
        var submissionAttemptCount = 1
        switch sendResult {
        case .acknowledged(let acknowledgedRunId):
            runId = acknowledgedRunId
            gatewayClient.bindEventSubscription(
                subscriberId: subscriberId,
                runId: acknowledgedRunId,
                sessionKey: sessionKey
            )
            taskState.bindGatewayRun(messageId: msgId, runId: acknowledgedRunId)
        case .deliveryUnconfirmed(let expectedRunId):
            runId = expectedRunId
            taskState.applyRunEvent(messageId: msgId, event: .sendDeliveryUnconfirmed)
        case .rejected(let message):
            if taskState.run(for: msgId)?.cancellationRequested == true {
                return ("cancelled", "")
            }
            let fallback = "Failed to send local image review chunk."
            return ("failed", message.flatMap { $0.isEmpty ? nil : $0 } ?? fallback)
        }

        if taskState.run(for: msgId)?.cancellationRequested == true {
            let result = await gatewayClient.abortChat(sessionKey: sessionKey, runId: runId)
            if result.isConfirmed { return ("cancelled", "") }
        }

        func recordImageRunEventDelivery(_ eventRunId: String) {
            guard eventRunId == runId,
                  let activeRun = taskState.run(for: msgId),
                  !activeRun.phase.isTerminal,
                  activeRun.runId == nil else { return }
            gatewayClient.bindEventSubscription(
                subscriberId: subscriberId,
                runId: eventRunId,
                sessionKey: sessionKey
            )
            taskState.bindGatewayRun(messageId: msgId, runId: eventRunId)
        }

        var accumulatedText = ""
        for await event in eventStream {
            // Adopt the gateway-assigned run id from the first session-matched event
            // when the ack did not bind one (the gateway never reuses our idempotency
            // key as the run id). recordImageRunEventDelivery performs the real bind.
            if taskState.run(for: msgId)?.runId == nil,
               let eventSessionKey = event.sessionKey, eventSessionKey == sessionKey,
               let eventRunId = event.runId, eventRunId != runId {
                runId = eventRunId
            }
            switch event {
            case .delta(let eventRunId, let eventSessionKey, let text):
                guard eventRunId == runId, eventSessionKey == sessionKey, !text.isEmpty else { continue }
                recordImageRunEventDelivery(eventRunId)
                accumulatedText = text
            case .final_(let eventRunId, let eventSessionKey, let text):
                guard eventRunId == runId, eventSessionKey == sessionKey else { continue }
                recordImageRunEventDelivery(eventRunId)
                guard let activeRun = taskState.run(for: msgId),
                      !activeRun.phase.isTerminal else { continue }
                let finalText = text.isEmpty ? accumulatedText : text
                if !finalText.isEmpty {
                    return ("completed", finalText)
                }
                gatewayClient.unsubscribe(subscriberId: subscriberId)
                return await reconcileLocalImageReviewChunk(
                    messageId: msgId,
                    runId: runId,
                    sessionKey: sessionKey,
                    accumulatedText: accumulatedText
                )
            case .aborted(let eventRunId, let eventSessionKey):
                guard eventRunId == runId, eventSessionKey == sessionKey else { continue }
                recordImageRunEventDelivery(eventRunId)
                guard let activeRun = taskState.run(for: msgId),
                      !activeRun.phase.isTerminal else { continue }
                return ("cancelled", accumulatedText)
            case .error(let eventRunId, let eventSessionKey, let message):
                guard eventRunId == runId, eventSessionKey == sessionKey else { continue }
                recordImageRunEventDelivery(eventRunId)
                guard let activeRun = taskState.run(for: msgId),
                      !activeRun.phase.isTerminal else { continue }
                return ("failed", message)
            case .activity(let eventRunId, let eventSessionKey, _):
                guard eventRunId == runId,
                      eventSessionKey == nil || eventSessionKey == sessionKey else { continue }
                recordImageRunEventDelivery(eventRunId)
            case .transport(.reconnecting(let attempt, let maxAttempts)):
                taskState.applyRunEvent(
                    messageId: msgId,
                    event: .transportReconnecting(attempt: attempt, maxAttempts: maxAttempts)
                )
            case .transport(.connected):
                taskState.applyRunEvent(messageId: msgId, event: .transportReconnected)
                if let activeRun = taskState.run(for: msgId),
                   !activeRun.phase.isTerminal,
                   activeRun.runId == nil,
                   !activeRun.cancellationRequested,
                   submissionAttemptCount < ChatRunDeliveryPolicy.maximumSubmissionAttempts {
                    submissionAttemptCount += 1
                    let retryResult = await gatewayClient.chatSend(
                        sessionKey: sessionKey,
                        message: prompt,
                        idempotencyKey: idempotencyKey,
                        attachments: nil
                    )
                    guard let currentRun = taskState.run(for: msgId),
                          !currentRun.phase.isTerminal,
                          currentRun.gatewayBinding.idempotencyKey == idempotencyKey,
                          currentRun.gatewayBinding.sessionKey == sessionKey else {
                        return ("cancelled", accumulatedText)
                    }
                    switch retryResult {
                    case .acknowledged(let acknowledgedRunId):
                        runId = acknowledgedRunId
                        gatewayClient.bindEventSubscription(
                            subscriberId: subscriberId,
                            runId: acknowledgedRunId,
                            sessionKey: sessionKey
                        )
                        taskState.bindGatewayRun(messageId: msgId, runId: acknowledgedRunId)
                    case .deliveryUnconfirmed:
                        if submissionAttemptCount < ChatRunDeliveryPolicy.maximumSubmissionAttempts {
                            continue
                        }
                    case .rejected:
                        break
                    }
                }
                gatewayClient.unsubscribe(subscriberId: subscriberId)
                return await reconcileLocalImageReviewChunk(
                    messageId: msgId,
                    runId: runId,
                    sessionKey: sessionKey,
                    accumulatedText: accumulatedText
                )
            case .transport(.recoveryExhausted(let attempts)):
                taskState.applyRunEvent(messageId: msgId, event: .recoveryExhausted(attempts: attempts))
                gatewayClient.unsubscribe(subscriberId: subscriberId)
                return await reconcileLocalImageReviewChunk(
                    messageId: msgId,
                    runId: runId,
                    sessionKey: sessionKey,
                    accumulatedText: accumulatedText
                )
            case .transport(.connecting):
                taskState.applyRunEvent(messageId: msgId, event: .retryRequested)
            case .transport(.disconnected):
                taskState.applyRunEvent(messageId: msgId, event: .recoveryExhausted(attempts: 0))
                gatewayClient.unsubscribe(subscriberId: subscriberId)
                return await reconcileLocalImageReviewChunk(
                    messageId: msgId,
                    runId: runId,
                    sessionKey: sessionKey,
                    accumulatedText: accumulatedText
                )
            }
        }

        if Task.isCancelled || taskState.run(for: msgId) == nil
            || findMessage(byId: msgId)?.taskStatus == .cancelled {
            return ("cancelled", accumulatedText)
        }
        gatewayClient.unsubscribe(subscriberId: subscriberId)
        return await reconcileLocalImageReviewChunk(
            messageId: msgId,
            runId: runId,
            sessionKey: sessionKey,
            accumulatedText: accumulatedText
        )
    }

    /// Image-review chunks share the same authoritative run resolver as normal
    /// chat, but return terminal results to the batch instead of completing the
    /// parent message. Once live delivery is interrupted, the event subscription
    /// is removed so an unbounded stream cannot accumulate unrelated events while
    /// the child waits for reconciliation or a manual retry.
    private func reconcileLocalImageReviewChunk(
        messageId: UUID,
        runId: String,
        sessionKey: String,
        accumulatedText: String
    ) async -> (status: String, text: String) {
        while !Task.isCancelled {
            guard let run = taskState.run(for: messageId),
                  !run.phase.isTerminal,
                  run.expectedRunId == runId,
                  run.gatewayBinding.sessionKey == sessionKey else {
                return ("cancelled", accumulatedText)
            }

            if gatewayClient.isConnected {
                taskState.applyRunEvent(messageId: messageId, event: .transportReconnected)
            }

            switch await reconcileChatRunOutcome(messageId: messageId) {
            case .terminal(.completed(let text)):
                return ("completed", text)
            case .terminal(.failed(let message)), .terminal(.timedOut(let message)):
                return ("failed", message)
            case .terminal(.cancelled):
                return ("cancelled", accumulatedText)
            case .superseded:
                if Task.isCancelled || taskState.run(for: messageId) == nil {
                    return ("cancelled", accumulatedText)
                }
                return ("failed", "Local image review run identity changed during recovery.")
            case .suspended:
                guard await waitForLocalImageReviewRetry(
                    messageId: messageId,
                    runId: runId,
                    sessionKey: sessionKey
                ) else {
                    return ("cancelled", accumulatedText)
                }
            }
        }
        return ("cancelled", accumulatedText)
    }

    private func waitForLocalImageReviewRetry(
        messageId: UUID,
        runId: String,
        sessionKey: String
    ) async -> Bool {
        while !Task.isCancelled {
            guard let run = taskState.run(for: messageId),
                  !run.phase.isTerminal,
                  run.expectedRunId == runId,
                  run.gatewayBinding.sessionKey == sessionKey else {
                return false
            }
            if run.cancellationRequested {
                return true
            }
            if gatewayClient.isConnected {
                return true
            }
            switch run.phase {
            case .connectionLost, .recoveryUnavailable:
                do {
                    try await Task.sleep(nanoseconds: 500_000_000)
                } catch {
                    return false
                }
            default:
                return true
            }
        }
        return false
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

    func updateMessage(
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
        if let sessionId = taskState.run(for: msgId)?.identity.sessionId,
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

    func appendBackgroundNotification(agentId: String, agentEmoji: String?, completed: Bool, msgId: UUID) {
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

    /// Heuristic: did the gateway reject a `chat.send` because the model does
    /// not support the requested reasoning effort? Used to degrade to `.auto`
    /// and resend rather than surfacing a hard failure.
    static func isThinkingRejection(_ message: String?) -> Bool {
        guard let message = message?.lowercased() else { return false }
        let needles = ["thinking", "reasoning", "effort", "thought", "not support"]
        return needles.contains { message.contains($0) }
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
        let isLocalImageReviewBatch = ImageReviewBatchStore.isImageReviewBatchCandidate(
            urls: attachments,
            messageText: text,
            selectedAgentId: currentAgentId
        )
        // Insert a placeholder assistant message for streaming updates
        let msgId = UUID()
        let placeholderMsg = ChatMessage(role: .assistant, content: "", agentId: currentAgentId, agentEmoji: currentAgentEmoji, taskStatus: .loading, id: msgId)
        chatMessagesByAgent[currentAgentId, default: []].append(placeholderMsg)
        logChat("PLACEHOLDER: agent=\(currentAgentId), msgId=\(msgId.uuidString.prefix(8)), totalMsgs=\(chatMessagesByAgent[currentAgentId]?.count ?? 0)")

        let gatewayBinding = ChatGatewayRunBinding(
            sessionKey: sessionKey,
            startedAt: placeholderMsg.timestamp ?? Date()
        )
        taskState.registerRun(ChatRunState(
            identity: ChatRunIdentity(
                messageId: msgId,
                agentId: currentAgentId,
                sessionId: currentSessionId
            ),
            gatewayBinding: gatewayBinding,
            startedAt: placeholderMsg.timestamp ?? Date(),
            executionKind: isLocalImageReviewBatch ? .localImageReviewBatch : .conversation
        ))
        scheduleAutomaticBackground(for: msgId)
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
            taskState.applyRunEvent(messageId: msgId, event: .failed)
            clearTaskTracking(msgId)
            return
        }

        if isLocalImageReviewBatch {
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
        let eventStream = gatewayClient.subscribeToEvents(
            subscriberId: subscriberId,
            runId: gatewayBinding.idempotencyKey,
            sessionKey: sessionKey
        )

        // Apply the composer model as a session-level override. If an explicit
        // composer model cannot be applied, stop the turn instead of silently
        // running on the session's current/fallback model.
        if !composerModelOverride.isEmpty, appliedSessionModels[sessionKey] != composerModelOverride {
            let patched = await gatewayClient.patchSessionModel(sessionKey: sessionKey, model: composerModelOverride)
            guard canContinueChatRunAfterPreflight(
                messageId: msgId,
                sessionKey: sessionKey,
                idempotencyKey: gatewayBinding.idempotencyKey
            ) else {
                gatewayClient.unsubscribe(subscriberId: subscriberId)
                return
            }
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
                taskState.applyRunEvent(messageId: msgId, event: .failed)
                clearTaskTracking(msgId)
                gatewayClient.unsubscribe(subscriberId: subscriberId)
                return
            }
        }

        guard let runBeforeSend = taskState.run(for: msgId) else {
            gatewayClient.unsubscribe(subscriberId: subscriberId)
            return
        }
        if runBeforeSend.cancellationRequested {
            finishCancelledChatRun(msgId)
            return
        }

        // Send the message
        taskState.applyRunEvent(messageId: msgId, event: .sendStarted)
        let chatSendStart = ContinuousClock.now
        chatLog.info("phase=chat_send_start agent=\(currentAgentId, privacy: .public) session=\(currentSessionId.uuidString, privacy: .public) sessionKey=\(sessionKey, privacy: .public) model_override=\(composerModelOverride.isEmpty ? "default" : composerModelOverride, privacy: .public) message_len=\(baseMessage.count, privacy: .public) attachment_count=\(attachments.count, privacy: .public) inline_attachment_count=\(processed.inlineAttachments.count, privacy: .public)")
        let inlineAttachments = processed.inlineAttachments.isEmpty ? nil : processed.inlineAttachments
        let composerEffort = activeComposerEffort
        var sendResult = await gatewayClient.chatSend(
            sessionKey: sessionKey,
            message: baseMessage,
            idempotencyKey: gatewayBinding.idempotencyKey,
            attachments: inlineAttachments,
            thinking: composerEffort.wireValue
        )
        // If the model refused the explicit reasoning tier, retry once with no
        // thinking so the turn still sends. The gateway is the real source of
        // truth; the per-family tier list is only an optimistic guess.
        if composerEffort != .auto,
           case .rejected(let thinkingRejection) = sendResult,
           Self.isThinkingRejection(thinkingRejection) {
            chatLog.warning("phase=chat_thinking_unsupported model=\(composerModelOverride.isEmpty ? "default" : composerModelOverride, privacy: .public) effort=\(composerEffort.rawValue, privacy: .public) — retrying without thinking")
            sendResult = await gatewayClient.chatSend(
                sessionKey: sessionKey,
                message: baseMessage,
                idempotencyKey: gatewayBinding.idempotencyKey,
                attachments: inlineAttachments,
                thinking: nil
            )
        }

        var runId = gatewayBinding.idempotencyKey
        var submissionAttemptCount = 1
        switch sendResult {
        case .acknowledged(let acknowledgedRunId):
            runId = acknowledgedRunId
            gatewayClient.bindEventSubscription(
                subscriberId: subscriberId,
                runId: acknowledgedRunId,
                sessionKey: sessionKey
            )
            taskState.bindGatewayRun(messageId: msgId, runId: acknowledgedRunId)
        case .deliveryUnconfirmed(let expectedRunId):
            runId = expectedRunId
            taskState.applyRunEvent(messageId: msgId, event: .sendDeliveryUnconfirmed)
            chatLog.warning("phase=chat_send_delivery_unconfirmed expectedRunId=\(expectedRunId, privacy: .public) session=\(currentSessionId.uuidString, privacy: .public)")
        case .rejected(let rejection):
            if taskState.run(for: msgId)?.cancellationRequested == true {
                finishCancelledChatRun(msgId)
                return
            }
            chatLog.warning("phase=chat_send_failed agent=\(currentAgentId, privacy: .public) session=\(currentSessionId.uuidString, privacy: .public) elapsed_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public)")
            let fallback = String(localized: "Failed to send message. Please try again.", bundle: LanguageManager.shared.localizedBundle)
            let errorMsg = rejection.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
            updateMessage(msgId: msgId, content: errorMsg, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
            taskState.applyRunEvent(messageId: msgId, event: .failed)
            gatewayClient.unsubscribe(subscriberId: subscriberId)
            clearTaskTracking(msgId)
            return
        }


        if taskState.run(for: msgId)?.cancellationRequested == true {
            let cancellationResult = await gatewayClient.abortChat(
                sessionKey: sessionKey,
                runId: runId
            )
            if cancellationResult.isConfirmed {
                finishCancelledChatRun(msgId)
                return
            }
        }

        let chatSendAckAt = ContinuousClock.now
        chatLog.info("phase=chat_send_ack runId=\(runId, privacy: .public) agent=\(currentAgentId, privacy: .public) session=\(currentSessionId.uuidString, privacy: .public) elapsed_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public)")

        if !attachments.isEmpty {
            showSuccessMessage("Attachments sent as a selective manifest. Large files and folders will not be read wholesale.")
        }

        chatLog.info("chat.send ok: runId=\(runId), subscriberId=\(subscriberId), bgTasks=\(self.backgroundTaskIds.count)")

        // Persist the backend identity before consuming events. Launch recovery
        // asks agent.wait for this exact run and uses timestamped chat.history
        // only to recover its terminal body. The record is removed centrally by
        // finishChatRun after a confirmed terminal outcome.
        if let registeredRun = taskState.run(for: msgId) {
            registerInFlightRun(registeredRun, agentEmoji: currentAgentEmoji)
        }

        func recordRunEventDelivery(_ eventRunId: String) {
            guard eventRunId == runId,
                  let activeRun = taskState.run(for: msgId),
                  !activeRun.phase.isTerminal,
                  activeRun.runId == nil else { return }
            gatewayClient.bindEventSubscription(
                subscriberId: subscriberId,
                runId: eventRunId,
                sessionKey: sessionKey
            )
            taskState.bindGatewayRun(messageId: msgId, runId: eventRunId)
            if let acknowledgedRun = taskState.run(for: msgId) {
                registerInFlightRun(acknowledgedRun, agentEmoji: currentAgentEmoji)
            }
        }

        defer {
            gatewayClient.unsubscribe(subscriberId: subscriberId)
        }

        // Stream events
        var accumulatedText = ""
        var committedWorkingText = ""
        var accumulatedActivityEvents: [ChatActivityEvent] = []
        var seenActivityEventKeys = Set<String>()
        // Throttle message updates to prevent CPU 100% during fast streaming
        var lastUpdateTime = Date.distantPast
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
            // The gateway assigns its own run id (never our idempotency key). If the
            // chat.send ack did not already bind one, adopt it from the first event
            // that belongs to this run's session so the per-case run-id guards below
            // match. Until then the hub routes this run by session. The authoritative
            // bind into taskState/hub still happens in recordRunEventDelivery.
            if taskState.run(for: msgId)?.runId == nil,
               let eventSessionKey = event.sessionKey, eventSessionKey == sessionKey,
               let eventRunId = event.runId, eventRunId != runId {
                runId = eventRunId
            }

            switch event {
            case .activity(let eventRunId, let eventSessionKey, let event):
                guard eventRunId == runId,
                      eventSessionKey == nil || eventSessionKey == sessionKey else { continue }
                recordRunEventDelivery(eventRunId)
                logFirstGatewayEventIfNeeded(kind: "activity", eventRunId: eventRunId, eventSessionKey: eventSessionKey)
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
                    updateActiveStreamState(
                        msgId: msgId,
                        visibleDraftText: Self.visibleAssistantText(
                            from: accumulatedText,
                            committedWorkingText: committedWorkingText
                        ),
                        activityEvents: accumulatedActivityEvents
                    )
                }

            case .delta(let eventRunId, let eventSessionKey, let text):
                guard eventRunId == runId, eventSessionKey == sessionKey else { continue }
                recordRunEventDelivery(eventRunId)
                logFirstGatewayEventIfNeeded(kind: "delta", eventRunId: eventRunId, eventSessionKey: eventSessionKey)
                // Skip empty deltas (e.g. tool_use blocks with no text content)
                guard !text.isEmpty else {
                    chatLog.debug("chat delta: EMPTY text skipped, runId=\(eventRunId)")
                    continue
                }
                taskState.applyRunEvent(messageId: msgId, event: .receivedDelta)
                if !didLogFirstDelta {
                    didLogFirstDelta = true
                    chatLog.info("phase=chat_first_delta runId=\(eventRunId, privacy: .public) sessionKey=\(eventSessionKey, privacy: .public) text_len=\(text.count, privacy: .public) elapsed_from_send_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public) elapsed_after_ack_ms=\(Self.elapsedMillisecondsText(since: chatSendAckAt), privacy: .public)")
                }
                chatLog.debug("chat delta: runId=\(eventRunId), textLen=\(text.count)")
                // Gateway sends full accumulated text in each delta, so use replacement
                accumulatedText = text
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
                        updateActiveStreamState(
                            msgId: msgId,
                            visibleDraftText: Self.visibleAssistantText(
                                from: accumulatedText,
                                committedWorkingText: committedWorkingText
                            ),
                            activityEvents: displayEvents
                        )
                    }
                }

            case .final_(let eventRunId, let eventSessionKey, let text):
                guard eventRunId == runId, eventSessionKey == sessionKey else { continue }
                recordRunEventDelivery(eventRunId)
                guard let activeRun = taskState.run(for: msgId),
                      !activeRun.phase.isTerminal else { continue }
                logFirstGatewayEventIfNeeded(kind: "final", eventRunId: eventRunId, eventSessionKey: eventSessionKey)
                chatLog.info("phase=chat_final runId=\(eventRunId, privacy: .public) sessionKey=\(eventSessionKey, privacy: .public) text_len=\(text.count, privacy: .public) accumulated_len=\(accumulatedText.count, privacy: .public) saw_delta=\(didLogFirstDelta, privacy: .public) elapsed_from_send_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public) elapsed_after_ack_ms=\(Self.elapsedMillisecondsText(since: chatSendAckAt), privacy: .public)")
                chatLog.info("chat final: runId=\(eventRunId), textLen=\(text.count), accumulatedLen=\(accumulatedText.count)")
                let finalText = Self.visibleAssistantText(
                    from: text.isEmpty ? accumulatedText : text,
                    committedWorkingText: committedWorkingText
                )
                // A final event owns the run, but an empty body is not enough to
                // identify persisted content. Reconcile by runId and timestamped
                // history rather than borrowing the session's latest reply.
                if finalText.isEmpty {
                    chatLog.warning("phase=chat_final_empty_reconcile runId=\(eventRunId, privacy: .public)")
                    taskState.applyRunEvent(messageId: msgId, event: .transportReconnected)
                    scheduleChatRunReconciliation(messageId: msgId)
                    continue
                }
                finishChatRun(
                    messageId: msgId,
                    outcome: .completed(text: finalText),
                    activityEvents: accumulatedActivityEvents
                )
                break streamLoop

            case .aborted(let eventRunId, let eventSessionKey):
                guard eventRunId == runId, eventSessionKey == sessionKey else { continue }
                recordRunEventDelivery(eventRunId)
                guard let activeRun = taskState.run(for: msgId),
                      !activeRun.phase.isTerminal else { continue }
                logFirstGatewayEventIfNeeded(kind: "aborted", eventRunId: eventRunId, eventSessionKey: eventSessionKey)
                chatLog.info("phase=chat_aborted runId=\(eventRunId, privacy: .public) elapsed_from_send_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public) elapsed_after_ack_ms=\(Self.elapsedMillisecondsText(since: chatSendAckAt), privacy: .public)")
                finishCancelledChatRun(msgId)
                break streamLoop

            case .error(let eventRunId, let eventSessionKey, let message):
                guard eventRunId == runId, eventSessionKey == sessionKey else { continue }
                recordRunEventDelivery(eventRunId)
                guard let activeRun = taskState.run(for: msgId),
                      !activeRun.phase.isTerminal else { continue }
                logFirstGatewayEventIfNeeded(kind: "error", eventRunId: eventRunId, eventSessionKey: eventSessionKey)
                chatLog.warning("phase=chat_error runId=\(eventRunId, privacy: .public) message_len=\(message.count, privacy: .public) elapsed_from_send_ms=\(Self.elapsedMillisecondsText(since: chatSendStart), privacy: .public) elapsed_after_ack_ms=\(Self.elapsedMillisecondsText(since: chatSendAckAt), privacy: .public)")
                finishChatRun(
                    messageId: msgId,
                    outcome: .failed(message: message),
                    activityEvents: accumulatedActivityEvents
                )
                chatLog.warning("chat error: runId=\(runId), message=\(message)")
                break streamLoop

            case .transport(.reconnecting(let attempt, let maxAttempts)):
                taskState.applyRunEvent(
                    messageId: msgId,
                    event: .transportReconnecting(attempt: attempt, maxAttempts: maxAttempts)
                )
            case .transport(.connected):
                if let activeRun = taskState.run(for: msgId),
                   !activeRun.phase.isTerminal,
                   activeRun.runId == nil,
                   !activeRun.cancellationRequested,
                   submissionAttemptCount < ChatRunDeliveryPolicy.maximumSubmissionAttempts {
                    submissionAttemptCount += 1
                    let retryResult = await gatewayClient.chatSend(
                        sessionKey: sessionKey,
                        message: baseMessage,
                        idempotencyKey: gatewayBinding.idempotencyKey,
                        attachments: processed.inlineAttachments.isEmpty ? nil : processed.inlineAttachments
                    )
                    guard let currentRun = taskState.run(for: msgId),
                          !currentRun.phase.isTerminal,
                          currentRun.gatewayBinding.idempotencyKey == gatewayBinding.idempotencyKey,
                          currentRun.gatewayBinding.sessionKey == sessionKey else {
                        break streamLoop
                    }
                    if case .acknowledged(let acknowledgedRunId) = retryResult {
                        runId = acknowledgedRunId
                        gatewayClient.bindEventSubscription(
                            subscriberId: subscriberId,
                            runId: acknowledgedRunId,
                            sessionKey: sessionKey
                        )
                        taskState.bindGatewayRun(messageId: msgId, runId: acknowledgedRunId)
                        if let acknowledgedRun = taskState.run(for: msgId) {
                            registerInFlightRun(acknowledgedRun, agentEmoji: currentAgentEmoji)
                        }
                    }
                }
                taskState.applyRunEvent(messageId: msgId, event: .transportReconnected)
                scheduleChatRunReconciliation(messageId: msgId)
            case .transport(.recoveryExhausted(let attempts)):
                taskState.applyRunEvent(messageId: msgId, event: .recoveryExhausted(attempts: attempts))
            case .transport(.connecting):
                taskState.applyRunEvent(messageId: msgId, event: .retryRequested)
            case .transport(.disconnected):
                continue
            }
        }

    }

    /// Move a foreground task to background, unlocking the input
    func moveTaskToBackground(_ msgId: UUID) {
        guard let run = taskState.run(for: msgId),
              !run.phase.isTerminal,
              run.placement == .foreground else { return }
        taskState.moveRunToBackground(messageId: msgId)
        chatRunLifecycleCoordinator.cancelAutomaticBackground(messageId: msgId)
        scheduleBackgroundRunHardDeadline(for: msgId)
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

        // Fall back to the inactive stash. Reachable when the auto-background
        // deadline fires as the user is switching sessions — without
        // this branch the placeholder keeps showing "Thinking…" forever
        // when the user navigates back, even though the task is
        // already tracked as background internally.
        if let sessionId = taskState.run(for: msgId)?.identity.sessionId,
           let idx = chatMessagesByInactiveSession[sessionId]?.firstIndex(where: { $0.id == msgId }) {
            let msg = chatMessagesByInactiveSession[sessionId]![idx]
            let content = msg.content.isEmpty ? bgLabel : msg.content
            var messages = chatMessagesByInactiveSession[sessionId]!
            let updated = msg.withTaskStatus(.background, content: content)
            messages[idx] = updated
            chatMessagesByInactiveSession[sessionId] = messages
        }
    }

    /// Record cancellation intent separately from the gateway terminal state.
    /// A run that may already have been delivered remains recoverable until
    /// `chat.abort` is acknowledged or a terminal run event arrives.
    func cancelChat(_ msgId: UUID) {
        guard let run = taskState.run(for: msgId), !run.phase.isTerminal else {
            chatLog.warning("cancelChat: no session bound to msgId \(msgId.uuidString.prefix(8)) — abort skipped")
            return
        }
        taskState.applyRunEvent(messageId: msgId, event: .cancellationRequested)

        if case .preparing = run.phase {
            finishCancelledChatRun(msgId)
            return
        }

        chatRunLifecycleCoordinator.scheduleCancellation(messageId: msgId) { [weak self] in
            await self?.attemptBackendCancellation(messageId: msgId)
        }
    }

    private func attemptBackendCancellation(messageId: UUID) async {
        guard let run = taskState.run(for: messageId),
              run.cancellationRequested,
              !run.phase.isTerminal else { return }

        let result = await gatewayClient.abortChat(
            sessionKey: run.gatewayBinding.sessionKey,
            runId: run.expectedRunId
        )
        guard result.isConfirmed,
              taskState.run(for: messageId)?.cancellationRequested == true else {
            if taskState.run(for: messageId)?.cancellationRequested == true {
                scheduleChatRunReconciliation(messageId: messageId)
            }
            return
        }
        finishCancelledChatRun(messageId)
    }

    func finishCancelledChatRun(_ messageId: UUID) {
        finishChatRun(messageId: messageId, outcome: .cancelled)
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
