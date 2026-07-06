//
//  CronManagement.swift
//  Cron job management extracted from DashboardViewModel.
//  P1 refactor: file split only, no behavior change.
//

import Foundation

extension DashboardViewModel {

    // MARK: - Cron Job Management

    /// Load cron jobs by running `openclaw cron list --json`
    func loadCronJobs() async {
        guard !isLoadingCronJobs else { return }
        isLoadingCronJobs = true
        cronJobsLoadError = nil
        defer {
            isLoadingCronJobs = false
            hasLoadedCronJobs = true
        }

        let output = await openclawService.runCommand(
            "openclaw cron list --all --json 2>&1",
            timeout: 60
        )
        guard Self.cronJobListOutputContainsJSON(output) else {
            cronJobsLoadError = Self.cronJobLoadErrorMessage(output: output)
            return
        }

        cronJobs = Self.parseCronJobList(output: output)
    }

    /// Parse `openclaw cron list --json` output
    static func parseCronJobList(output: String?) -> [CronJobInfo] {
        guard let jsonString = cronJobListJSONString(output: output),
              let data = jsonString.data(using: .utf8) else { return [] }

        // Try parsing as {"jobs": [...]} or as [...]
        if let wrapper = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let jobsArray = wrapper["jobs"] as? [[String: Any]] {
            return jobsArray.compactMap { Self.parseCronJobDict($0) }
        } else if let jobsArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return jobsArray.compactMap { Self.parseCronJobDict($0) }
        }

        return []
    }

    static func cronJobListOutputContainsJSON(_ output: String?) -> Bool {
        guard let jsonString = cronJobListJSONString(output: output),
              let data = jsonString.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private static func cronJobListJSONString(output: String?) -> String? {
        guard let output = output else { return nil }

        // Strip ANSI escape codes
        let ansiPattern = "\\u{1B}\\[[0-9;]*[a-zA-Z]"
        let cleaned = output.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)

        // Try to extract JSON from the output (skip any non-JSON lines)
        let lines = cleaned.components(separatedBy: .newlines)
        var jsonString = ""
        var inJson = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inJson {
                if trimmed == "[" || trimmed.hasPrefix("[{") || trimmed.hasPrefix("[\"") {
                    inJson = true
                } else if trimmed.hasPrefix("{") {
                    inJson = true
                }
            }
            if inJson {
                jsonString += line + "\n"
            }
        }

        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func cronJobLoadErrorMessage(output: String?) -> String {
        let trimmed = output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return "Unable to read cron jobs. The command did not return JSON output."
        }

        let firstLines = trimmed
            .components(separatedBy: .newlines)
            .prefix(3)
            .joined(separator: " ")
        let compact = firstLines.count > 220 ? String(firstLines.prefix(220)) + "..." : firstLines
        return "Unable to read cron jobs. \(compact)"
    }

    /// Parse a single cron job dictionary
    private static func parseCronJobDict(_ dict: [String: Any]) -> CronJobInfo? {
        guard let id = dict["id"] as? String else { return nil }

        let name = dict["name"] as? String ?? id

        // schedule is a nested object: { kind, expr, tz }
        let scheduleObj = dict["schedule"] as? [String: Any]
        let schedule = scheduleObj?["expr"] as? String ?? dict["schedule"] as? String ?? ""
        let timezone = scheduleObj?["tz"] as? String ?? dict["timezone"] as? String ?? ""

        let agentId = dict["agentId"] as? String ?? dict["agent_id"] as? String ?? ""
        let sessionTarget = dict["sessionTarget"] as? String ?? dict["session_target"] as? String ?? ""

        // message is nested in payload: { kind, message, timeoutSeconds }
        let payloadObj = dict["payload"] as? [String: Any]
        let message = payloadObj?["message"] as? String ?? dict["message"] as? String ?? ""

        let enabled = dict["enabled"] as? Bool ?? true

        // nextRun / lastRun are timestamps in state: { nextRunAtMs, lastRunAtMs }
        let stateObj = dict["state"] as? [String: Any]
        let nextRun = Self.formatTimestamp(stateObj?["nextRunAtMs"])
        let lastRun = Self.formatTimestamp(stateObj?["lastRunAtMs"])

        let status = dict["status"] as? String ?? (enabled ? "idle" : "disabled")
        let model = dict["model"] as? String ?? ""

        return CronJobInfo(
            cronId: id,
            name: name,
            schedule: schedule,
            timezone: timezone,
            agentId: agentId,
            sessionTarget: sessionTarget,
            message: message,
            enabled: enabled,
            nextRun: nextRun,
            lastRun: lastRun,
            status: status,
            model: model
        )
    }

    /// Format a millisecond timestamp to a readable date string
    private static func formatTimestamp(_ value: Any?) -> String {
        guard let ms = value as? Double ?? (value as? Int).map({ Double($0) }) else { return "" }
        let date = Date(timeIntervalSince1970: ms / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    /// Add a new cron job
    func addCronJob(name: String, schedule: String, timezone: String, agentId: String, message: String, sessionTarget: String) async {
        isPerformingAction = true
        var cmd = "openclaw cron add --name '\(name)' --cron '\(schedule)'"
        if !timezone.isEmpty {
            cmd += " --tz '\(timezone)'"
        }
        if !agentId.isEmpty {
            cmd += " --agent '\(agentId)'"
        }
        if !sessionTarget.isEmpty {
            // openclaw CLI 实际接受的是 `--session <target>` (target ∈ main|isolated|current|session:<id>),
            // 不是 `--session-target` — 后者从 v1.1.15 起就拼错了,但定时任务功能用户少,40+ 版本一直没人撞到。
            // 2026.3.2 / 2026.5.10 都不认 --session-target,本地脚手架就是 --session。
            cmd += " --session '\(sessionTarget)'"
        }
        if !message.isEmpty {
            let escapedMessage = message.replacingOccurrences(of: "'", with: "'\\''")
            cmd += " --message '\(escapedMessage)'"
        }
        cmd += " --json 2>&1"

        let output = await openclawService.runCommand(cmd)
        if let output = output, output.lowercased().contains("error") && !output.contains("{") {
            showErrorMessage(I18n.format("dashboard.cron.toast.addFailed", output))
        } else {
            showSuccessMessage(I18n.format("dashboard.cron.toast.created", name))
        }
        await loadCronJobs()
        isPerformingAction = false
    }

    /// Enable a cron job
    func enableCronJob(_ job: CronJobInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw cron enable \(job.cronId) 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage(I18n.format("dashboard.cron.toast.enableFailed", output))
        } else {
            showSuccessMessage(I18n.format("dashboard.cron.toast.enabled", job.name))
        }
        await loadCronJobs()
        isPerformingAction = false
    }

    /// Disable a cron job
    func disableCronJob(_ job: CronJobInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw cron disable \(job.cronId) 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage(I18n.format("dashboard.cron.toast.disableFailed", output))
        } else {
            showSuccessMessage(I18n.format("dashboard.cron.toast.disabled", job.name))
        }
        await loadCronJobs()
        isPerformingAction = false
    }

    /// Remove a cron job
    func removeCronJob(_ job: CronJobInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw cron rm \(job.cronId) 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage(I18n.format("dashboard.cron.toast.removeFailed", output))
        } else {
            showSuccessMessage(I18n.format("dashboard.cron.toast.removed", job.name))
        }
        await loadCronJobs()
        isPerformingAction = false
    }

    /// Manually run a cron job
    func runCronJob(_ job: CronJobInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw cron run \(job.cronId) 2>&1",
            timeout: 120
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage(I18n.format("dashboard.cron.toast.runFailed", output))
        } else {
            showSuccessMessage(I18n.format("dashboard.cron.toast.triggered", job.name))
        }
        await loadCronJobs()
        isPerformingAction = false
    }

}
