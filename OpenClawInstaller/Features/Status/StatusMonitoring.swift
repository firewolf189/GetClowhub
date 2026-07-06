//
//  StatusMonitoring.swift
//  Status/sessions summary (status-tab monitoring) extracted from DashboardViewModel.
//  P1 refactor: file split only, no behavior change.
//

import Foundation

extension DashboardViewModel {

    // MARK: - Status Summary

    func getStatusSummary() -> String {
        let status = openclawService.status.rawValue
        let version = openclawService.version.isEmpty ? "Unknown" : openclawService.version

        if openclawService.status == .running {
            let uptime = formatUptime(openclawService.uptime)
            return "\(status) • v\(version) • Uptime: \(uptime)"
        } else {
            return "\(status) • v\(version)"
        }
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }

    // MARK: - Sessions Summary (Status Tab Monitoring)

    /// Load agent sessions summary by running `openclaw sessions --all-agents --json`
    func loadSessionsSummary() async {
        isLoadingSessionsSummary = true
        let output = await openclawService.runCommand(
            "openclaw sessions --all-agents --json 2>&1", timeout: 15
        )
        sessionsSummary = Self.parseSessionsSummary(output: output)
        isLoadingSessionsSummary = false
    }

    /// Parse `openclaw sessions --all-agents --json` output into a SessionsSummary.
    /// Output may contain non-JSON prefix (warnings), so we find the first `[`.
    /// Sessions are aggregated by agentId. Main sessions have keys ending in `:main` (no `:cron:`).
    /// Tokens are accumulated across ALL sessions (including cron).
    static func parseSessionsSummary(output: String?) -> SessionsSummary? {
        guard let output = output else { return nil }

        // Strip ANSI escape codes
        let ansiPattern = "\u{1B}\\[[0-9;]*[a-zA-Z]"
        let cleaned = output.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)

        // Find first '{' or '[' to locate JSON start
        var sessions: [[String: Any]] = []

        if let objStart = cleaned.firstIndex(of: "{") {
            // Output is a JSON object like { "sessions": [...] }
            let jsonString = String(cleaned[objStart...])
            if let data = jsonString.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let arr = obj["sessions"] as? [[String: Any]] {
                sessions = arr
            }
        }

        // Fallback: try parsing as top-level array if object parsing yielded nothing
        if sessions.isEmpty, let arrStart = cleaned.firstIndex(of: "[") {
            let arrString = String(cleaned[arrStart...])
            if let arrData = arrString.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: arrData) as? [[String: Any]] {
                sessions = parsed
            }
        }

        guard !sessions.isEmpty else { return nil }

        // Accumulate totals across all sessions
        var totalInput = 0
        var totalOutput = 0
        var totalTokens = 0

        // Group by agentId for agent-level info
        // Key: agentId, Value: (model, inputTokens, outputTokens, totalTokens, latestUpdatedAt, sessionCount)
        struct AgentAccum {
            var model: String = ""
            var inputTokens: Int = 0
            var outputTokens: Int = 0
            var totalTokens: Int = 0
            var latestUpdatedAt: Double = 0
            var sessionCount: Int = 0
        }
        var agentMap: [String: AgentAccum] = [:]

        for session in sessions {
            let key = session["key"] as? String ?? ""
            let agentId = session["agentId"] as? String ?? ""
            let inputTk = session["inputTokens"] as? Int ?? 0
            let outputTk = session["outputTokens"] as? Int ?? 0
            let totalTk = session["totalTokens"] as? Int ?? 0
            let model = session["model"] as? String ?? ""
            let updatedAt = session["updatedAt"] as? Double ?? 0

            // Accumulate total tokens across ALL sessions
            totalInput += inputTk
            totalOutput += outputTk
            totalTokens += totalTk

            // Aggregate all sessions by agentId (main, cron, dingtalk, etc.)
            if !agentId.isEmpty {
                var accum = agentMap[agentId] ?? AgentAccum()
                accum.model = model
                accum.inputTokens += inputTk
                accum.outputTokens += outputTk
                accum.totalTokens += totalTk
                accum.sessionCount += 1
                if updatedAt > accum.latestUpdatedAt {
                    accum.latestUpdatedAt = updatedAt
                }
                agentMap[agentId] = accum
            }
        }

        // Build AgentSessionInfo array sorted by latest activity
        let agents = agentMap.map { (agentId, accum) -> AgentSessionInfo in
            let lastActive: Date? = accum.latestUpdatedAt > 0
                ? Date(timeIntervalSince1970: accum.latestUpdatedAt / 1000.0)
                : nil
            return AgentSessionInfo(
                agentId: agentId,
                model: accum.model,
                inputTokens: accum.inputTokens,
                outputTokens: accum.outputTokens,
                totalTokens: accum.totalTokens,
                lastActiveAt: lastActive,
                sessionCount: accum.sessionCount
            )
        }.sorted { a, b in
            (a.lastActiveAt ?? .distantPast) > (b.lastActiveAt ?? .distantPast)
        }

        return SessionsSummary(
            agents: agents,
            totalInput: totalInput,
            totalOutput: totalOutput,
            totalTokens: totalTokens,
            totalSessions: sessions.count
        )
    }
}
