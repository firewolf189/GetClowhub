//
//  InFlightRuns.swift
//  In-flight run crash-recovery persistence extracted from DashboardViewModel.
//

import Foundation
import os.log

extension DashboardViewModel {

    // MARK: - In-Flight Run Persistence

    /// Persisted record of an in-flight chat run, written on chat.send
    /// success and removed only on a confirmed terminal outcome or explicit
    /// cancellation. Survives app crash / force-quit so the next launch can
    /// rehydrate the typed run and use the shared reconciler.
    ///
    /// Without this, killing the app mid-task leaves the placeholder
    /// stuck at `.loading` or `.background` on disk forever, with no
    /// way to reattach to the gateway-side run (the runId is gone from
    /// memory). The user sees a permanent "Thinking…" / "Running in
    /// background…" UI for a task that's actually long since finished.
    private struct PersistedInFlightRun: Codable {
        let runId: String
        let deliveryAcknowledged: Bool?
        let sessionKey: String
        let msgId: UUID
        let sessionId: UUID
        let agentId: String
        let agentEmoji: String?
        let startedAt: Date
    }

    private var inFlightRunsFileURL: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let bundleId = Bundle.main.bundleIdentifier ?? "com.cc.OpenClawInstaller"
        let dir = appSupport
            .appendingPathComponent(bundleId)
            .appendingPathComponent("chat-sessions")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("in-flight-runs.json")
    }

    private func readInFlightRuns() -> [PersistedInFlightRun] {
        guard let data = try? Data(contentsOf: inFlightRunsFileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PersistedInFlightRun].self, from: data)) ?? []
    }

    private func writeInFlightRuns(_ runs: [PersistedInFlightRun]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(runs) {
            try? data.write(to: inFlightRunsFileURL, options: .atomic)
        }
    }

    /// Append a fresh in-flight record after `chat.send` is acknowledged or its
    /// delivery becomes uncertain. Both cases retain one stable run identity.
    func registerInFlightRun(_ run: ChatRunState, agentEmoji: String?) {
        var runs = readInFlightRuns()
        runs.removeAll { $0.msgId == run.identity.messageId }
        runs.append(PersistedInFlightRun(
            runId: run.expectedRunId,
            deliveryAcknowledged: run.runId != nil,
            sessionKey: run.gatewayBinding.sessionKey,
            msgId: run.identity.messageId,
            sessionId: run.identity.sessionId,
            agentId: run.identity.agentId,
            agentEmoji: agentEmoji,
            startedAt: run.gatewayBinding.startedAt
        ))
        writeInFlightRuns(runs)
    }

    /// Remove an in-flight record after the task terminates (any reason
    /// — completed, cancelled, errored, timed out, or stream cleanup).
    func unregisterInFlightRun(msgId: UUID) {
        var runs = readInFlightRuns()
        runs.removeAll { $0.msgId == msgId }
        writeInFlightRuns(runs)
    }

    /// Rehydrate runs left behind by a crash and hand them to the same
    /// run-specific reconciler used by live reconnects. `agent.wait` supplies
    /// the terminal identity; timestamped `chat.history` supplies only content
    /// that falls inside that run's window. Multiple runs in one session are
    /// therefore recoverable independently without a latest-message heuristic.
    func recoverInFlightRunsOnLaunch() {
        let allEntries = readInFlightRuns()
        guard !allEntries.isEmpty else { return }

        let now = Date()
        let cutoff = now.addingTimeInterval(-ChatRunLifetimePolicy.backgroundHardLimit)
        var fresh: [PersistedInFlightRun] = []
        var stale: [PersistedInFlightRun] = []
        for entry in allEntries {
            if entry.startedAt >= cutoff {
                fresh.append(entry)
            } else {
                stale.append(entry)
            }
        }

        chatLog.info("In-flight recovery: \(fresh.count) recoverable, \(stale.count) stale")

        Task { [weak self] in
            guard let self else { return }

            for entry in stale {
                await self.markEntryTimedOut(entry, reason: .stale)
                self.unregisterInFlightRun(msgId: entry.msgId)
            }
            for entry in fresh {
                self.recoverSingleInFlightRun(entry)
            }
        }
    }

    private enum RecoveryFailReason {
        case stale
    }

    private func markEntryTimedOut(_ entry: PersistedInFlightRun, reason: RecoveryFailReason) async {
        await MainActor.run {
            guard var session = self.chatSessionStore.loadSession(id: entry.sessionId),
                  let idx = session.messages.firstIndex(where: { $0.id == entry.msgId }) else {
                return
            }
            let msg = session.messages[idx]
            guard msg.taskStatus == .loading || msg.taskStatus == .background else { return }

            let noteText: String
            switch reason {
            case .stale:
                noteText = "Task started over an hour ago and result is no longer recoverable. Please re-send."
            }
            let note = String(localized: String.LocalizationValue(noteText), bundle: LanguageManager.shared.localizedBundle)
            let content = msg.content.isEmpty
                ? note
                : msg.content + "\n\n---\n> ⚠️ " + note

            session.messages[idx] = msg.withTaskStatus(.timedOut, content: content)
            session.updatedAt = Date()
            self.chatSessionStore.saveSession(session)

            if self.selectedSessionIdByAgent[entry.agentId] == entry.sessionId,
               var messages = self.chatMessagesByAgent[entry.agentId],
               let memIdx = messages.firstIndex(where: { $0.id == entry.msgId }) {
                messages[memIdx] = session.messages[idx]
                self.chatMessagesByAgent[entry.agentId] = messages
            }
        }
    }

    private func recoverSingleInFlightRun(_ entry: PersistedInFlightRun) {
        guard let session = chatSessionStore.loadSession(id: entry.sessionId),
              let message = session.messages.first(where: { $0.id == entry.msgId }) else {
            chatLog.warning("recovery: session \(entry.sessionId) or msg \(entry.msgId) not found, skipping")
            unregisterInFlightRun(msgId: entry.msgId)
            return
        }

        guard message.taskStatus == .loading || message.taskStatus == .background else {
            unregisterInFlightRun(msgId: entry.msgId)
            return
        }

        rehydratePersistedRun(entry, message: message)
        scheduleBackgroundRunHardDeadline(for: entry.msgId)
        scheduleChatRunReconciliation(messageId: entry.msgId)
    }

    private func rehydratePersistedRun(
        _ entry: PersistedInFlightRun,
        message: ChatMessage
    ) {
        guard taskState.run(for: entry.msgId) == nil else { return }

        taskState.registerRun(ChatRunState(
            identity: ChatRunIdentity(
                messageId: entry.msgId,
                agentId: entry.agentId,
                sessionId: entry.sessionId
            ),
            gatewayBinding: ChatGatewayRunBinding(
                sessionKey: entry.sessionKey,
                idempotencyKey: entry.runId,
                startedAt: entry.startedAt,
                runId: entry.deliveryAcknowledged == false ? nil : entry.runId
            ),
            startedAt: entry.startedAt,
            placement: .background,
            phase: .reconciling
        ))
        recomputeIsSendingMessage()
    }
}
