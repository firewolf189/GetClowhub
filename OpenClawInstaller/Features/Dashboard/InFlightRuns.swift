//
//  InFlightRuns.swift
//  In-flight run crash-recovery persistence extracted from DashboardViewModel.
//  P1 refactor: file split only, no behavior change.
//  (activityToken stored property stays in the main class.)
//

import Foundation
import os.log

extension DashboardViewModel {

    // MARK: - In-Flight Run Persistence

    /// Persisted record of an in-flight chat run, written on chat.send
    /// success and removed on terminal event (completed/cancelled/error/
    /// timeout) or stream cleanup. Survives app crash / force-quit so
    /// the next launch can attempt recovery via `chat.history`.
    ///
    /// Without this, killing the app mid-task leaves the placeholder
    /// stuck at `.loading` or `.background` on disk forever, with no
    /// way to reattach to the gateway-side run (the runId is gone from
    /// memory). The user sees a permanent "Thinking…" / "Running in
    /// background…" UI for a task that's actually long since finished.
    private struct PersistedInFlightRun: Codable {
        let runId: String
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

    /// Append a fresh in-flight record. Called from `sendChatMessage`
    /// right after `chat.send` returns a runId.
    func registerInFlightRun(runId: String, sessionKey: String, msgId: UUID,
                                      sessionId: UUID, agentId: String, agentEmoji: String?) {
        var runs = readInFlightRuns()
        runs.append(PersistedInFlightRun(
            runId: runId, sessionKey: sessionKey, msgId: msgId,
            sessionId: sessionId, agentId: agentId, agentEmoji: agentEmoji,
            startedAt: Date()
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

    /// On app launch, look at leftover entries in `in-flight-runs.json`
    /// — they represent tasks the user started but the app died before
    /// they finished. For each, ask the gateway for the session's last
    /// assistant message (via `chat.history`); if found, update the
    /// disk-side placeholder to `.completed` so the user sees the
    /// recovered reply when they next open the session. If history
    /// has nothing, mark `.timedOut` with an explanatory note.
    ///
    /// Runs as a background Task after WS connects (waits up to 30s).
    /// Doesn't block init or the chat UI.
    func recoverInFlightRunsOnLaunch() {
        let allEntries = readInFlightRuns()
        guard !allEntries.isEmpty else { return }

        // Freshness guard: anything older than 1 hour is presumed to
        // be either truly lost (gateway no longer running it / no
        // longer in history) or worse — its sessionKey may have been
        // reused since by other channels (DingTalk / Weixin share the
        // same `agent:X:<sid>` namespace). Recovering against a stale
        // entry would attribute someone ELSE's reply to our crashed
        // task. Safer to just mark these timed out and let the user
        // re-send.
        let now = Date()
        let cutoff = now.addingTimeInterval(-3600)
        var fresh: [PersistedInFlightRun] = []
        var stale: [PersistedInFlightRun] = []
        for entry in allEntries {
            if entry.startedAt >= cutoff {
                fresh.append(entry)
            } else {
                stale.append(entry)
            }
        }

        // Multi-entry-per-session guard: if the user fired off N sends
        // in the same session before the crash, fetchLastAssistantMessage
        // returns ONE reply (the most recent one gateway completed) but
        // we'd otherwise attribute it to all N placeholders. Recover
        // only the LATEST entry per sessionId; mark earlier ones timed
        // out (their reply, if any, is no longer addressable from
        // history without per-runId metadata).
        var latestBySession: [UUID: PersistedInFlightRun] = [:]
        var supersededByLater: [PersistedInFlightRun] = []
        for entry in fresh {
            if let existing = latestBySession[entry.sessionId] {
                if entry.startedAt > existing.startedAt {
                    supersededByLater.append(existing)
                    latestBySession[entry.sessionId] = entry
                } else {
                    supersededByLater.append(entry)
                }
            } else {
                latestBySession[entry.sessionId] = entry
            }
        }
        let recoverable = Array(latestBySession.values)
        let unrecoverable = stale + supersededByLater

        chatLog.info("In-flight recovery: \(recoverable.count) recoverable, \(unrecoverable.count) marked timed-out (\(stale.count) stale + \(supersededByLater.count) superseded)")

        Task { [weak self] in
            guard let self = self else { return }

            // Stale + superseded: no recovery attempt, straight to timedOut.
            for entry in unrecoverable {
                await self.markEntryTimedOut(entry, reason: .stale)
            }

            // Wait for WS for the recoverable batch.
            let deadline = Date().addingTimeInterval(30)
            while !self.gatewayClient.isConnected && Date() < deadline {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            for entry in recoverable {
                await self.recoverSingleInFlightRun(entry)
            }

            // Clear the file — recovered or not, we tried.
            await MainActor.run {
                self.writeInFlightRuns([])
            }
        }
    }

    private enum RecoveryFailReason {
        case stale            // > 1h old, didn't try history
        case superseded       // newer entry exists for same session
        case noHistory        // history fetch returned nothing useful
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
            case .superseded:
                noteText = "A more recent task in the same session was recovered instead. Please re-send if needed."
            case .noHistory:
                noteText = "Task was interrupted by app restart. Result could not be recovered."
            }
            let note = String(localized: String.LocalizationValue(noteText), bundle: LanguageManager.shared.localizedBundle)
            let content = msg.content.isEmpty
                ? note
                : msg.content + "\n\n---\n> ⚠️ " + note

            session.messages[idx] = ChatMessage(
                role: .assistant,
                content: content,
                agentId: msg.agentId,
                agentEmoji: msg.agentEmoji,
                taskStatus: .timedOut,
                id: entry.msgId,
                timestamp: msg.timestamp
            )
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

    private func recoverSingleInFlightRun(_ entry: PersistedInFlightRun) async {
        guard var session = chatSessionStore.loadSession(id: entry.sessionId),
              let idx = session.messages.firstIndex(where: { $0.id == entry.msgId }) else {
            chatLog.warning("recovery: session \(entry.sessionId) or msg \(entry.msgId) not found, skipping")
            return
        }

        let msg = session.messages[idx]
        // Only touch placeholders that are still in non-terminal state.
        // If the user already saw it complete in a previous session
        // (somehow), don't overwrite.
        guard msg.taskStatus == .loading || msg.taskStatus == .background else {
            return
        }

        let recovered = await gatewayClient.fetchLastAssistantMessage(sessionKey: entry.sessionKey)

        await MainActor.run {
            let newStatus: ChatMessage.TaskStatus
            let newContent: String

            if let text = recovered, !text.isEmpty, text.count > msg.content.count {
                // History has more content than the disk placeholder —
                // the run completed gateway-side while we were dead.
                newStatus = .completed
                newContent = text
                chatLog.info("recovery: session \(entry.sessionId.uuidString.prefix(8)) msg \(entry.msgId.uuidString.prefix(8)) → restored \(text.count) chars")
            } else {
                // Nothing useful — mark timed out with note so the user
                // knows the previous run was lost and can resend.
                newStatus = .timedOut
                let note = String(localized: "Task was interrupted by app restart. Result could not be recovered.",
                                  bundle: LanguageManager.shared.localizedBundle)
                newContent = msg.content.isEmpty
                    ? note
                    : msg.content + "\n\n---\n> ⚠️ " + note
                chatLog.warning("recovery: session \(entry.sessionId.uuidString.prefix(8)) msg \(entry.msgId.uuidString.prefix(8)) — no usable history, marked timed out")
            }

            session.messages[idx] = ChatMessage(
                role: .assistant,
                content: newContent,
                agentId: msg.agentId,
                agentEmoji: msg.agentEmoji,
                taskStatus: newStatus,
                id: entry.msgId,
                timestamp: msg.timestamp
            )
            session.updatedAt = Date()
            self.chatSessionStore.saveSession(session)

            // Mirror into in-memory state if this session happens to be
            // currently loaded for an agent — otherwise the user would
            // see the stale state until they switched away and back.
            if self.selectedSessionIdByAgent[entry.agentId] == entry.sessionId,
               var messages = self.chatMessagesByAgent[entry.agentId],
               let memIdx = messages.firstIndex(where: { $0.id == entry.msgId }) {
                messages[memIdx] = session.messages[idx]
                self.chatMessagesByAgent[entry.agentId] = messages
            }
        }
    }
}
