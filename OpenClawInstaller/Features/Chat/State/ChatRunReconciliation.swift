import Foundation
import os.log

enum ChatRunTerminalOutcome: Equatable, Sendable {
    case completed(text: String)
    case failed(message: String)
    case cancelled
    case timedOut(message: String)
}

enum ChatRunReconciliationResult: Equatable, Sendable {
    case terminal(ChatRunTerminalOutcome)
    case suspended
    case superseded
}

private struct ChatRunReconciliationObservation {
    let status: GatewayChatRunStatusSnapshot
    let decision: GatewayChatRecoveryDecision
}

extension DashboardViewModel {
    /// Starts one generation-scoped reconciliation operation for a run. A new
    /// reconnect or manual retry replaces the older operation for that message.
    func scheduleChatRunReconciliation(messageId: UUID) {
        guard let run = taskState.run(for: messageId),
              !run.phase.isTerminal,
              run.executionKind == .conversation else { return }
        chatRunLifecycleCoordinator.scheduleReconciliation(messageId: messageId) { [weak self] in
            await self?.reconcileChatRun(messageId: messageId)
        }
    }

    /// Applies visible-message ownership only after the owner-neutral resolver
    /// has produced an authoritative terminal result.
    func reconcileChatRun(messageId: UUID) async {
        guard let initialRun = taskState.run(for: messageId),
              !initialRun.phase.isTerminal,
              initialRun.executionKind == .conversation else { return }

        if case .terminal(let outcome) = await reconcileChatRunOutcome(messageId: messageId) {
            finishChatRun(messageId: messageId, outcome: outcome)
        }
    }

    /// Reconciles transport-independent run state. Foreground runs have no
    /// total client deadline: an authoritative `running` observation continues
    /// at a low polling frequency until the gateway reports a terminal state or
    /// the user cancels. Unavailable RPCs are bounded and become manually
    /// retryable without discarding the run identity.
    func reconcileChatRunOutcome(messageId: UUID) async -> ChatRunReconciliationResult {
        guard let initialRun = taskState.run(for: messageId), !initialRun.phase.isTerminal else {
            return .superseded
        }
        let expectedRunId = initialRun.expectedRunId
        let sessionKey = initialRun.gatewayBinding.sessionKey
        var cursor = ChatRunReconciliationCursor()

        while !Task.isCancelled {
            guard let run = currentChatRun(
                messageId: messageId,
                expectedRunId: expectedRunId,
                sessionKey: sessionKey
            ) else { return .superseded }

            guard gatewayClient.isConnected else {
                switch gatewayClient.connectionState {
                case .connecting:
                    taskState.applyRunEvent(messageId: messageId, event: .retryRequested)
                case .reconnecting(let attempt, let maximum):
                    taskState.applyRunEvent(
                        messageId: messageId,
                        event: .transportReconnecting(attempt: attempt, maxAttempts: maximum)
                    )
                case .recoveryExhausted(let attempts):
                    taskState.applyRunEvent(
                        messageId: messageId,
                        event: .recoveryExhausted(attempts: attempts)
                    )
                    return .suspended
                case .connected, .disconnected:
                    break
                }
                guard await sleepForChatReconciliation(seconds: 1) else { return .superseded }
                continue
            }

            if run.cancellationRequested {
                let abortResult = await gatewayClient.abortChat(
                    sessionKey: sessionKey,
                    runId: expectedRunId
                )
                guard currentChatRun(
                    messageId: messageId,
                    expectedRunId: expectedRunId,
                    sessionKey: sessionKey
                ) != nil else { return .superseded }
                if abortResult.isConfirmed {
                    return .terminal(.cancelled)
                }
            }

            guard let observation = await fetchChatRunReconciliationObservation(
                runId: expectedRunId,
                sessionKey: sessionKey,
                fallbackStartedAt: run.gatewayBinding.startedAt
            ) else {
                guard currentChatRun(
                    messageId: messageId,
                    expectedRunId: expectedRunId,
                    sessionKey: sessionKey
                ) != nil else { return .superseded }
                if !gatewayClient.isConnected { continue }
                if let result = await applyChatReconciliationDirective(
                    cursor.recordUnavailableObservation(),
                    messageId: messageId
                ) {
                    return result
                }
                continue
            }

            guard let currentRun = currentChatRun(
                messageId: messageId,
                expectedRunId: expectedRunId,
                sessionKey: sessionKey
            ) else { return .superseded }
            cursor.recordAuthoritativeObservation()

            if currentRun.runId == nil,
               observation.status.indicatesNoRegisteredRun,
               Date().timeIntervalSince(currentRun.gatewayBinding.startedAt)
                    >= ChatRunDeliveryPolicy.unregisteredRunGracePeriod {
                let message = String(
                    localized: "Failed to send message. Please try again.",
                    bundle: LanguageManager.shared.localizedBundle
                )
                return .terminal(.failed(message: message))
            }

            switch observation.decision {
            case .complete(let text):
                return .terminal(.completed(text: text))

            case .failed(let message):
                let fallback = String(
                    localized: "Failed",
                    bundle: LanguageManager.shared.localizedBundle
                )
                return .terminal(.failed(message: message ?? fallback))

            case .cancelled:
                return .terminal(.cancelled)

            case .resume(let bufferedText):
                applyRecoveredChatDraft(messageId: messageId, bufferedText: bufferedText)
                if let result = await applyChatReconciliationDirective(
                    cursor.pollActiveRun(),
                    messageId: messageId
                ) {
                    return result
                }

            case .awaitingAuthoritativeState:
                switch observation.status.state {
                case .completed:
                    if let result = await applyChatReconciliationDirective(
                        cursor.recordCompletedReplyUnavailable(),
                        messageId: messageId
                    ) {
                        return result
                    }
                case .running, .unknown:
                    applyRecoveredChatDraft(messageId: messageId, bufferedText: nil)
                    if let result = await applyChatReconciliationDirective(
                        cursor.pollActiveRun(),
                        messageId: messageId
                    ) {
                        return result
                    }
                case .failed, .cancelled:
                    return .superseded
                }
            }
        }
        return .superseded
    }

    func scheduleBackgroundRunHardDeadline(for messageId: UUID) {
        guard let run = taskState.run(for: messageId),
              run.placement == .background,
              !run.phase.isTerminal else {
            chatRunLifecycleCoordinator.cancelHardDeadline(messageId: messageId)
            return
        }
        let deadline = run.startedAt.addingTimeInterval(ChatRunLifetimePolicy.backgroundHardLimit)
        chatRunLifecycleCoordinator.scheduleHardDeadline(
            messageId: messageId,
            deadline: deadline
        ) { [weak self] in
            await self?.expireBackgroundChatRun(messageId: messageId)
        }
    }

    func finishChatRun(
        messageId: UUID,
        outcome: ChatRunTerminalOutcome,
        activityEvents: [ChatActivityEvent]? = nil
    ) {
        guard let run = taskState.run(for: messageId), !run.phase.isTerminal else { return }
        let existingMessage = findMessage(byId: messageId)
        let streamState = chatState.activeStreamStatesByMessageId[messageId]
        let resolvedEvents = activityEvents
            ?? streamState?.activityEvents
            ?? existingMessage?.activityEvents
            ?? []
        let resolvedEmoji = existingMessage?.agentEmoji
        let taskStatus: ChatMessage.TaskStatus
        let content: String
        let runEvent: ChatRunEvent

        switch outcome {
        case .completed(let text):
            taskStatus = .completed
            content = text
            runEvent = .completed
        case .failed(let message):
            taskStatus = .completed
            content = terminalChatContent(
                draft: streamState?.visibleDraftText,
                notice: message
            )
            runEvent = .failed
        case .cancelled:
            taskStatus = .cancelled
            content = streamState?.visibleDraftText ?? existingMessage?.content ?? ""
            runEvent = .cancelled
        case .timedOut(let message):
            taskStatus = .timedOut
            content = terminalChatContent(
                draft: streamState?.visibleDraftText,
                notice: message
            )
            runEvent = .failed
        }

        if existingMessage != nil {
            updateMessage(
                msgId: messageId,
                content: content,
                status: taskStatus,
                agentId: run.identity.agentId,
                agentEmoji: resolvedEmoji,
                activityEvents: resolvedEvents
            )
        } else {
            updatePersistedChatRunMessage(
                run: run,
                content: content,
                status: taskStatus,
                activityEvents: resolvedEvents
            )
        }

        taskState.applyRunEvent(messageId: messageId, event: runEvent)
        if case .completed = outcome,
           run.placement == .background,
           selectedSessionIdByAgent[run.identity.agentId] == run.identity.sessionId,
           existingMessage != nil {
            appendBackgroundNotification(
                agentId: run.identity.agentId,
                agentEmoji: resolvedEmoji,
                completed: true,
                msgId: messageId
            )
        }

        gatewayClient.unsubscribe(subscriberId: messageId.uuidString)
        unregisterInFlightRun(msgId: messageId)
        clearTaskTracking(messageId)
    }

    private func fetchChatRunReconciliationObservation(
        runId: String,
        sessionKey: String,
        fallbackStartedAt: Date
    ) async -> ChatRunReconciliationObservation? {
        guard let status = await gatewayClient.fetchChatRunStatus(runId: runId) else {
            return nil
        }

        switch status.state {
        case .failed:
            return ChatRunReconciliationObservation(
                status: status,
                decision: .failed(message: status.errorMessage)
            )
        case .cancelled:
            return ChatRunReconciliationObservation(status: status, decision: .cancelled)
        case .completed, .running, .unknown:
            let snapshot = await gatewayClient.fetchChatRecoverySnapshot(sessionKey: sessionKey)
            let decision = snapshot?.decision(
                expectedRunId: runId,
                expectedRunStatus: status,
                fallbackStartedAt: fallbackStartedAt
            ) ?? .awaitingAuthoritativeState
            return ChatRunReconciliationObservation(status: status, decision: decision)
        }
    }

    private func currentChatRun(
        messageId: UUID,
        expectedRunId: String,
        sessionKey: String
    ) -> ChatRunState? {
        guard !Task.isCancelled,
              let run = taskState.run(for: messageId),
              !run.phase.isTerminal,
              run.expectedRunId == expectedRunId,
              run.gatewayBinding.sessionKey == sessionKey else {
            return nil
        }
        return run
    }

    private func applyRecoveredChatDraft(messageId: UUID, bufferedText: String?) {
        guard let run = taskState.run(for: messageId), !run.phase.isTerminal else { return }
        let currentStreamState = chatState.activeStreamStatesByMessageId[messageId]
        let visibleText = bufferedText ?? currentStreamState?.visibleDraftText ?? ""
        let events = currentStreamState?.activityEvents
            ?? findMessage(byId: messageId)?.activityEvents
            ?? []
        if run.executionKind == .conversation, !visibleText.isEmpty {
            updateActiveStreamState(
                msgId: messageId,
                visibleDraftText: visibleText,
                activityEvents: events
            )
        }
        taskState.applyRunEvent(
            messageId: messageId,
            event: .recoveryResumed(hasBufferedText: !visibleText.isEmpty)
        )
    }

    private func applyChatReconciliationDirective(
        _ directive: ChatRunReconciliationDirective,
        messageId: UUID
    ) async -> ChatRunReconciliationResult? {
        switch directive {
        case .retry(let delay), .poll(let delay):
            return await sleepForChatReconciliation(seconds: delay) ? nil : .superseded
        case .suspend(let attempts):
            taskState.applyRunEvent(
                messageId: messageId,
                event: .reconciliationUnavailable(attempts: attempts)
            )
            return .suspended
        }
    }

    private func sleepForChatReconciliation(seconds: TimeInterval) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func expireBackgroundChatRun(messageId: UUID) async {
        guard let run = taskState.run(for: messageId),
              run.placement == .background,
              !run.phase.isTerminal else { return }
        let expectedRunId = run.expectedRunId
        let sessionKey = run.gatewayBinding.sessionKey
        _ = await gatewayClient.abortChat(sessionKey: sessionKey, runId: expectedRunId)
        guard currentChatRun(
            messageId: messageId,
            expectedRunId: expectedRunId,
            sessionKey: sessionKey
        ) != nil else { return }
        let message = String(
            localized: "The task timed out and has been terminated. You can try again or switch to another agent.",
            bundle: LanguageManager.shared.localizedBundle
        )
        finishChatRun(messageId: messageId, outcome: .timedOut(message: message))
    }

    private func terminalChatContent(draft: String?, notice: String) -> String {
        let normalizedDraft = draft?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let warning = "⚠️ " + notice
        guard !normalizedDraft.isEmpty else { return warning }
        return normalizedDraft + "\n\n---\n> " + warning
    }

    private func updatePersistedChatRunMessage(
        run: ChatRunState,
        content: String,
        status: ChatMessage.TaskStatus,
        activityEvents: [ChatActivityEvent]
    ) {
        guard var session = chatSessionStore.loadSession(id: run.identity.sessionId),
              let index = session.messages.firstIndex(where: { $0.id == run.identity.messageId }) else {
            chatLog.warning(
                "phase=chat_terminal_message_missing messageId=\(run.identity.messageId.uuidString, privacy: .public) session=\(run.identity.sessionId.uuidString, privacy: .public)"
            )
            return
        }
        let message = session.messages[index]
        let resolvedContent = status == .cancelled && content.isEmpty
            ? message.content
            : content
        let resolvedActivityEvents = activityEvents.isEmpty
            ? message.activityEvents
            : activityEvents
        session.messages[index] = ChatMessage(
            role: .assistant,
            content: resolvedContent,
            agentId: message.agentId ?? run.identity.agentId,
            agentEmoji: message.agentEmoji,
            attachments: message.attachments,
            taskStatus: status,
            id: message.id,
            scrollTargetId: message.scrollTargetId,
            timestamp: message.timestamp,
            completedAt: Date(),
            activityEvents: resolvedActivityEvents
        )
        session.updatedAt = Date()
        chatSessionStore.saveSession(session)
    }
}
