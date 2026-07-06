import Foundation
import Combine
import UserNotifications
import AppKit
import os.log

@MainActor
class BudgetService: ObservableObject {
    @Published var config: BudgetConfig
    @Published var snapshots: [BudgetSnapshot] = []

    private let configPath: String

    init() {
        self.configPath = NSString("~/.openclaw/budgets.json").expandingTildeInPath
        self.config = BudgetConfig.defaultConfig()
        loadConfig()
    }

    // MARK: - Config Persistence

    func loadConfig() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: configPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let loaded = try? JSONDecoder().decode(BudgetConfig.self, from: data) else {
            // First run: persist the default config to disk
            saveConfig()
            return
        }
        config = loaded
    }

    func saveConfig() {
        let dir = (configPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
    }

    // MARK: - Rule Management

    func addRule(_ rule: BudgetRule) {
        // Prevent duplicate id
        guard !config.rules.contains(where: { $0.id == rule.id }) else { return }
        config.rules.append(rule)
        saveConfig()
    }

    func updateRule(_ rule: BudgetRule) {
        guard let idx = config.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        config.rules[idx] = rule
        saveConfig()
    }

    func removeRule(id: String) {
        config.rules.removeAll { $0.id == id }
        saveConfig()
    }

    func toggleRule(id: String) {
        guard let idx = config.rules.firstIndex(where: { $0.id == id }) else { return }
        config.rules[idx].enabled.toggle()
        saveConfig()
    }

    // MARK: - Evaluate Budget Status

    /// Evaluate all budget rules against current session data and model costs.
    /// When sessions is nil (service not running or no data yet), snapshots show 0 usage.
    func evaluate(sessions: SessionsSummary?, modelCosts: [PresetModel]) -> [BudgetSnapshot] {
        NSLog("[BudgetService] evaluate() called with sessions: %@, modelCosts: %d", String(sessions != nil), modelCosts.count)
        let emptySessions = SessionsSummary(agents: [], totalInput: 0, totalOutput: 0, totalTokens: 0, totalSessions: 0)
        let effectiveSessions = sessions ?? emptySessions

        var results: [BudgetSnapshot] = []

        for rule in config.rules where rule.enabled {
            let (input, output, total) = tokensForRule(rule, sessions: effectiveSessions)
            let cost = estimateCost(inputTokens: input, outputTokens: output, modelCosts: modelCosts)

            let tokenPercent = rule.tokenLimit > 0 ? Double(total) / Double(rule.tokenLimit) : 0
            let costPercent = rule.costLimit > 0 ? cost / rule.costLimit : 0

            let tokenStatus = computeStatus(percent: tokenPercent, warnRatio: rule.warnRatio, hasLimit: rule.tokenLimit > 0)
            let costStatus = computeStatus(percent: costPercent, warnRatio: rule.warnRatio, hasLimit: rule.costLimit > 0)

            let overall = mergeStatus(tokenStatus, costStatus)

            let snapshot = BudgetSnapshot(
                id: rule.id,
                label: rule.label,
                scope: rule.scope,
                tokensUsed: total,
                inputTokens: input,
                outputTokens: output,
                estimatedCost: cost,
                tokenLimit: rule.tokenLimit,
                costLimit: rule.costLimit,
                warnRatio: rule.warnRatio,
                tokenStatus: tokenStatus,
                costStatus: costStatus,
                overallStatus: overall,
                tokenPercent: tokenPercent,
                costPercent: costPercent
            )
            results.append(snapshot)
        }

        // Check for status changes and send notifications
        let previousSnapshots = snapshots
        snapshots = results
        checkAndNotify(previous: previousSnapshots, current: results)

        return results
    }

    // MARK: - Cost Estimation

    /// Estimate cost using configured model prices.
    /// Uses average cost across all configured models as approximation.
    func estimateCost(inputTokens: Int, outputTokens: Int, modelCosts: [PresetModel]) -> Double {
        guard !modelCosts.isEmpty else { return 0 }

        // Use average cost across configured models
        let avgInputCost = modelCosts.map(\.cost.input).reduce(0, +) / Double(modelCosts.count)
        let avgOutputCost = modelCosts.map(\.cost.output).reduce(0, +) / Double(modelCosts.count)

        let inputCost = Double(inputTokens) / 1_000_000.0 * avgInputCost
        let outputCost = Double(outputTokens) / 1_000_000.0 * avgOutputCost

        return inputCost + outputCost
    }

    // MARK: - Helpers

    private func tokensForRule(_ rule: BudgetRule, sessions: SessionsSummary) -> (input: Int, output: Int, total: Int) {
        switch rule.scope {
        case .global:
            return (sessions.totalInput, sessions.totalOutput, sessions.totalTokens)
        case .agent:
            if let agent = sessions.agents.first(where: { $0.agentId == rule.id }) {
                return (agent.inputTokens, agent.outputTokens, agent.totalTokens)
            }
            return (0, 0, 0)
        }
    }

    private func computeStatus(percent: Double, warnRatio: Double, hasLimit: Bool) -> BudgetStatus {
        guard hasLimit else { return .ok }
        if percent >= 1.0 { return .over }
        if percent >= warnRatio { return .warn }
        return .ok
    }

    private func mergeStatus(_ a: BudgetStatus, _ b: BudgetStatus) -> BudgetStatus {
        let priority: [BudgetStatus: Int] = [.ok: 0, .warn: 1, .over: 2]
        return (priority[a] ?? 0) >= (priority[b] ?? 0) ? a : b
    }

    // MARK: - Budget Reset

    /// Reset all budget counters by clearing OpenClaw session data
    func resetAllBudgets() async -> Bool {
        print("[BudgetService] Resetting all budget counters...")

        // Try to get OpenClawService from AppDelegate
        guard let appDelegate = NSApp.delegate as? AppDelegate,
              let openclawService = appDelegate.openclawService else {
            print("[BudgetService] ⚠️ Could not access OpenClawService")
            return false
        }

        let result = await openclawService.runCommand("openclaw sessions reset-all", timeout: 15)
        let success = (result?.contains("success") ?? false) ||
                      (result?.contains("Reset") ?? false) ||
                      (result?.contains("cleared") ?? false)

        if success {
            print("[BudgetService] ✅ All budgets reset successfully")
            // Clear local snapshots to show fresh state
            snapshots = []
        } else {
            print("[BudgetService] ❌ Reset failed: \(result ?? "unknown error")")
        }

        return success
    }

    /// Reset budget counter for a specific agent
    func resetAgentBudget(_ agentId: String) async -> Bool {
        print("[BudgetService] Resetting budget for agent: \(agentId)")

        guard let appDelegate = NSApp.delegate as? AppDelegate,
              let openclawService = appDelegate.openclawService else {
            print("[BudgetService] ⚠️ Could not access OpenClawService")
            return false
        }

        let result = await openclawService.runCommand("openclaw sessions reset \(agentId)", timeout: 15)
        let success = (result?.contains("success") ?? false) ||
                      (result?.contains("Reset") ?? false) ||
                      (result?.contains("cleared") ?? false)

        if success {
            print("[BudgetService] ✅ Agent budget reset successfully")
            // Clear local snapshots for this agent
            snapshots.removeAll { $0.scope == .agent && $0.id == agentId }
        } else {
            print("[BudgetService] ❌ Reset failed: \(result ?? "unknown error")")
        }

        return success
    }

    // MARK: - Notifications

    private func checkAndNotify(previous: [BudgetSnapshot], current: [BudgetSnapshot]) {
        NSLog("[BudgetService] checkAndNotify() - previous: %d, current: %d", previous.count, current.count)
        NSLog("[BudgetService] Config - notifyOnWarn: %@, notifyOnOver: %@", String(config.notifyOnWarn), String(config.notifyOnOver))
        NSLog("[BudgetService] Current config rules count: %d", config.rules.count)

        for snap in current {
            let prev = previous.first(where: { $0.id == snap.id })
            let prevStatus = prev?.overallStatus ?? .ok

            NSLog("[BudgetService] Processing %@ (id:%@) - status: %@, tokens: %d/%d, prevStatus: %@", snap.label, snap.id, snap.overallStatus.label, snap.tokensUsed, snap.tokenLimit, prevStatus.label)

            // Handle warning status: notify on transition OR if already warned and usage increased
            if snap.overallStatus == .warn && config.notifyOnWarn {
                let transitioned = prevStatus != .warn
                let usageIncreased = snap.tokensUsed > (prev?.tokensUsed ?? 0)

                NSLog("[BudgetService] ⚠️ Warning check for %@: transitioned=%@, usageIncreased=%@, prevTokens=%d, currentTokens=%d", snap.label, String(transitioned), String(usageIncreased), prev?.tokensUsed ?? 0, snap.tokensUsed)

                if transitioned || usageIncreased {
                    NSLog("[BudgetService] 🔔 WILL SEND warning notification for %@", snap.label)
                    sendNotification(
                        title: String(localized: "Budget Warning", bundle: LanguageManager.shared.localizedBundle),
                        body: String(format: String(localized: "%@: usage at %d%% of limit", bundle: LanguageManager.shared.localizedBundle), snap.label, Int(snap.tokenPercent * 100))
                    )
                }
            }

            // Handle over status: notify on transition OR if already over and usage continued to increase
            if snap.overallStatus == .over && config.notifyOnOver {
                let transitioned = prevStatus != .over
                let usageIncreased = snap.tokensUsed > (prev?.tokensUsed ?? 0)

                NSLog("[BudgetService] 🔴 Over check for %@: transitioned=%@, usageIncreased=%@, prevTokens=%d, currentTokens=%d", snap.label, String(transitioned), String(usageIncreased), prev?.tokensUsed ?? 0, snap.tokensUsed)

                if transitioned || usageIncreased {
                    NSLog("[BudgetService] 🔔 WILL SEND over notification for %@", snap.label)
                    sendNotification(
                        title: String(localized: "⚠️ Budget Exceeded!", bundle: LanguageManager.shared.localizedBundle),
                        body: String(format: String(localized: "%@: %d / %d tokens used", bundle: LanguageManager.shared.localizedBundle),
                                   snap.label, snap.tokensUsed, snap.tokenLimit)
                    )
                } else {
                    NSLog("[BudgetService] Over status but no notification condition met: transitioned=%@, usageIncreased=%@", String(transitioned), String(usageIncreased))
                }
            } else if snap.overallStatus == .over && !config.notifyOnOver {
                NSLog("[BudgetService] Over status detected but notifyOnOver is DISABLED for %@", snap.label)
            }
        }
    }

    private func sendNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()

        // First, check current authorization status
        center.getNotificationSettings { settings in
            print("[BudgetService] Notification settings - authorizationStatus: \(settings.authorizationStatus.rawValue)")

            if settings.authorizationStatus == .notDetermined {
                // Request authorization for the first time
                print("[BudgetService] Requesting notification authorization...")
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    print("[BudgetService] Authorization response - granted: \(granted), error: \(error?.localizedDescription ?? "none")")
                    if granted {
                        self.deliverNotification(title: title, body: body, center: center)
                    }
                }
            } else if settings.authorizationStatus == .authorized {
                // Already authorized, send directly
                self.deliverNotification(title: title, body: body, center: center)
            } else {
                // Authorization was denied
                print("[BudgetService] Notification authorization denied by user")
            }
        }
    }

    private func deliverNotification(title: String, body: String, center: UNUserNotificationCenter) {
        DispatchQueue.main.async {
            print("[BudgetService] 📢 Delivering notification - \(title): \(body)")
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            center.add(request) { error in
                if let error = error {
                    print("[BudgetService] ❌ Failed to add notification: \(error.localizedDescription)")
                } else {
                    print("[BudgetService] ✅ Notification added successfully")
                }
            }
        }
    }
}
