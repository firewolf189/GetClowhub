import SwiftUI
import os.log

struct BudgetTabView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1. Budget Overview Cards
                BudgetOverviewSection(viewModel: viewModel)

                // 2. Per-Agent Budget Status
                AgentBudgetListSection(viewModel: viewModel)

                // 3. Budget Rules Management
                BudgetRulesSection(viewModel: viewModel)
            }
            .padding(24)
        }
        .task {
            await viewModel.loadBudgets()
        }
    }
}

// MARK: - Budget Overview Section

struct BudgetOverviewSection: View {
    @ObservedObject var viewModel: DashboardViewModel

    private var globalSnapshot: BudgetSnapshot? {
        viewModel.budgetSnapshots.first(where: { $0.scope == .global })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(String(localized: "Budget Overview", bundle: LanguageManager.shared.localizedBundle), systemImage: "dollarsign.gauge.chart.lefthalf.righthalf")
                    .font(.headline)

                Spacer()

                // Refresh button
                Button(action: {
                    Task {
                        await viewModel.loadBudgets()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help(String(localized: "Refresh", bundle: LanguageManager.shared.localizedBundle))
            }

            if viewModel.isLoadingBudgets {
                HStack {
                    Spacer()
                    ProgressView().scaleEffect(0.8)
                    Spacer()
                }
                .frame(minHeight: 80)
            } else if let snap = globalSnapshot {
                HStack(spacing: 16) {
                    BudgetGaugeCard(
                        title: String(localized: "Total Tokens", bundle: LanguageManager.shared.localizedBundle),
                        used: formatTokenCount(snap.tokensUsed),
                        limit: snap.tokenLimit > 0 ? formatTokenCount(snap.tokenLimit) : String(localized: "No Limit", bundle: LanguageManager.shared.localizedBundle),
                        percent: snap.tokenPercent,
                        status: snap.tokenStatus,
                        hasLimit: snap.tokenLimit > 0
                    )
                }
            } else {
                Text(String(localized: "No global budget rule configured. Add one below to start tracking.", bundle: LanguageManager.shared.localizedBundle))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Budget Gauge Card

struct BudgetGaugeCard: View {
    let title: String
    let used: String
    let limit: String
    let percent: Double
    let status: BudgetStatus
    let hasLimit: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(used)
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.bold)

                if hasLimit {
                    Text("/ \(limit)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            if hasLimit {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(NSColor.separatorColor))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(statusColor)
                            .frame(width: max(0, min(geo.size.width, geo.size.width * percent)), height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("\(Int(min(percent, 9.99) * 100))%")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)

                    Spacer()

                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(LocalizedStringKey(status.label))
                            .font(.caption)
                            .foregroundColor(statusColor)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text(String(localized: "No Limit", bundle: LanguageManager.shared.localizedBundle))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(hasLimit && status != .ok ? statusColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
    }

    private var statusColor: Color {
        switch status {
        case .ok: return .green
        case .warn: return .orange
        case .over: return .red
        }
    }
}

// MARK: - Agent Budget List

struct AgentBudgetListSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var isResetting = false
    @State private var showResetConfirm = false
    @State private var agentToReset: BudgetSnapshot?
    @State private var showDebugAlert = false
    @State private var debugMessage = ""

    private var agentSnapshots: [BudgetSnapshot] {
        viewModel.budgetSnapshots.filter { $0.scope == .agent }
    }

    var body: some View {
        if !agentSnapshots.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label(String(localized: "Per-Agent Budget", bundle: LanguageManager.shared.localizedBundle), systemImage: "person.3.fill")
                    .font(.headline)

                VStack(spacing: 6) {
                    HStack {
                        Text(String(localized: "Agent", bundle: LanguageManager.shared.localizedBundle))
                            .frame(width: 100, alignment: .leading)
                        Text(String(localized: "Tokens", bundle: LanguageManager.shared.localizedBundle))
                            .frame(width: 120, alignment: .trailing)
                        Text(String(localized: "Progress", bundle: LanguageManager.shared.localizedBundle))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(String(localized: "Status", bundle: LanguageManager.shared.localizedBundle))
                            .frame(width: 80, alignment: .center)
                        Text("")
                            .frame(width: 50)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Divider()

                    ForEach(agentSnapshots) { snap in
                        AgentBudgetRow(
                            snapshot: snap,
                            onReset: {
                                agentToReset = snap
                                debugMessage = "Agent ID: \(snap.id)\nAgent Label: \(snap.label)\nCommand: openclaw sessions cleanup --agent \(snap.id)"
                                showResetConfirm = true
                            }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .alert(
                String(localized: "Reset Agent Session?", bundle: LanguageManager.shared.localizedBundle),
                isPresented: $showResetConfirm
            ) {
                Button(String(localized: "Cancel", bundle: LanguageManager.shared.localizedBundle), role: .cancel) { }
                Button(String(localized: "Reset", bundle: LanguageManager.shared.localizedBundle), role: .destructive) {
                    if let agent = agentToReset {
                        isResetting = true
                        Task {
                            await resetAgentSession(agentId: agent.id)
                            isResetting = false
                        }
                    }
                }
            } message: {
                Text(String(localized: "This will clear session data and reset token counters. This action cannot be undone.", bundle: LanguageManager.shared.localizedBundle))
            }
        }
    }

    private func resetAgentSession(agentId: String) async {
        print("[AgentBudgetListSection] 🔄 Starting reset for agent ID: \(agentId)")

        do {
            let cmdExecutor = viewModel.commandExecutor

            // Delete the session files to reset token counts
            let baseDir = NSString("~/.openclaw").expandingTildeInPath
            let sessionsDir = (baseDir as NSString).appendingPathComponent("agents/\(agentId)/sessions")

            print("[AgentBudgetListSection] 📂 Sessions directory: \(sessionsDir)")
            print("[AgentBudgetListSection] 📋 Attempting to reset by removing session files")

            let fm = FileManager.default
            var deletedCount = 0

            // Delete sessions.json
            let sessionsJsonPath = (sessionsDir as NSString).appendingPathComponent("sessions.json")
            if fm.fileExists(atPath: sessionsJsonPath) {
                do {
                    try fm.removeItem(atPath: sessionsJsonPath)
                    print("[AgentBudgetListSection] ✅ Deleted: sessions.json")
                    deletedCount += 1
                } catch {
                    print("[AgentBudgetListSection] ⚠️ Failed to delete sessions.json: \(error)")
                }
            }

            // Delete all .jsonl files in sessions directory
            do {
                let sessionFiles = try fm.contentsOfDirectory(atPath: sessionsDir)
                for file in sessionFiles where file.hasSuffix(".jsonl") {
                    let filePath = (sessionsDir as NSString).appendingPathComponent(file)
                    try fm.removeItem(atPath: filePath)
                    print("[AgentBudgetListSection] ✅ Deleted: \(file)")
                    deletedCount += 1
                }
            } catch {
                print("[AgentBudgetListSection] ⚠️ Error reading sessions directory: \(error)")
            }

            if deletedCount > 0 {
                print("[AgentBudgetListSection] ✅ Successfully deleted \(deletedCount) session file(s)")
            } else {
                print("[AgentBudgetListSection] ⚠️ No session files found to delete")
            }

            // Reload budgets to show fresh state
            await viewModel.loadBudgets()
        } catch {
            print("[AgentBudgetListSection] ❌ Error: \(error)")
            os_log("[AgentBudgetListSection] Failed to reset agent %@: %@", log: OSLog.default, type: .error, agentId, error.localizedDescription)
        }
    }
}

struct AgentBudgetRow: View {
    let snapshot: BudgetSnapshot
    let onReset: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack {
            Text(snapshot.label)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)

            Text(formatTokenCount(snapshot.tokensUsed))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .trailing)

            if snapshot.tokenLimit > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(NSColor.separatorColor))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(statusColor(snapshot.overallStatus))
                            .frame(
                                width: max(0, min(geo.size.width, geo.size.width * snapshot.tokenPercent)),
                                height: 6
                            )
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 6)
            } else {
                Text("-")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor(snapshot.overallStatus))
                    .frame(width: 8, height: 8)
                Text(LocalizedStringKey(snapshot.overallStatus.label))
                    .font(.caption)
                    .foregroundColor(statusColor(snapshot.overallStatus))
            }
            .frame(width: 80, alignment: .center)

            Button(action: {
                print("🔘 Reset button clicked for: \(snapshot.label) (id: \(snapshot.id))")
                onReset()
            }) {
                Image(systemName: "arrow.counterclockwise.circle")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Reset agent session", bundle: LanguageManager.shared.localizedBundle))
            .frame(width: 50)
            .onHover { hovering in
                isHovering = hovering
                print("Button hovered: \(hovering) for \(snapshot.label)")
            }
        }
        .padding(.vertical, 2)
        .background(isHovering ? Color.blue.opacity(0.1) : Color.clear)
    }

    private func statusColor(_ status: BudgetStatus) -> Color {
        switch status {
        case .ok: return .green
        case .warn: return .orange
        case .over: return .red
        }
    }
}

// MARK: - Budget Rules Section

struct BudgetRulesSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showAddSheet = false
    @State private var editingRule: BudgetRule?
    @State private var ruleToDelete: BudgetRule?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(String(localized: "Budget Rules", bundle: LanguageManager.shared.localizedBundle), systemImage: "list.bullet.rectangle")
                    .font(.headline)

                Spacer()

                Button(action: { showAddSheet = true }) {
                    Label(String(localized: "Add Rule", bundle: LanguageManager.shared.localizedBundle), systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            // Notification settings
            HStack(spacing: 16) {
                Toggle(String(localized: "Notify on Warning", bundle: LanguageManager.shared.localizedBundle), isOn: Binding(
                    get: { viewModel.budgetService.config.notifyOnWarn },
                    set: { val in
                        viewModel.budgetService.config.notifyOnWarn = val
                        viewModel.budgetService.saveConfig()
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)

                Toggle(String(localized: "Notify on Over", bundle: LanguageManager.shared.localizedBundle), isOn: Binding(
                    get: { viewModel.budgetService.config.notifyOnOver },
                    set: { val in
                        viewModel.budgetService.config.notifyOnOver = val
                        viewModel.budgetService.saveConfig()
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
            }

            Divider()

            if viewModel.budgetRules.isEmpty {
                Text(String(localized: "No budget rules configured.", bundle: LanguageManager.shared.localizedBundle))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                VStack(spacing: 4) {
                    ForEach(viewModel.budgetRules) { rule in
                        BudgetRuleRow(
                            rule: rule,
                            onToggle: {
                                viewModel.budgetService.toggleRule(id: rule.id)
                                viewModel.syncBudgetRules()
                                Task { await viewModel.loadBudgets() }
                            },
                            onEdit: {
                                editingRule = rule
                            },
                            onDelete: {
                                ruleToDelete = rule
                            }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .sheet(isPresented: $showAddSheet) {
            AddBudgetRuleSheet(
                viewModel: viewModel,
                isPresented: $showAddSheet
            )
        }
        .sheet(item: $editingRule) { rule in
            EditBudgetRuleSheet(
                viewModel: viewModel,
                rule: rule,
                isPresented: Binding(
                    get: { editingRule != nil },
                    set: { if !$0 { editingRule = nil } }
                )
            )
        }
        .alert(String(localized: "Delete Budget Rule?", bundle: LanguageManager.shared.localizedBundle), isPresented: Binding(
            get: { ruleToDelete != nil },
            set: { if !$0 { ruleToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { ruleToDelete = nil }
            Button("Delete", role: .destructive) {
                if let rule = ruleToDelete {
                    viewModel.budgetService.removeRule(id: rule.id)
                    viewModel.syncBudgetRules()
                    Task { await viewModel.loadBudgets() }
                }
                ruleToDelete = nil
            }
        } message: {
            if let rule = ruleToDelete {
            Text(String(format: String(localized: "Remove the budget rule for \"%@\"?", bundle: LanguageManager.shared.localizedBundle), rule.label))
            }
        }
    }
}

// MARK: - Budget Rule Row

struct BudgetRuleRow: View {
    let rule: BudgetRule
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(rule.enabled ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            Text(LocalizedStringKey(rule.scope == .global ? "Global" : "Agent"))
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(rule.scope == .global ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15))
                .cornerRadius(4)

            Text(rule.label)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)

            Spacer()

            if rule.tokenLimit > 0 {
            (Text(String(localized: "budget.token.prefix", defaultValue: "Token: ", bundle: LanguageManager.shared.localizedBundle)) + Text(formatTokenCount(rule.tokenLimit)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if rule.tokenLimit == 0 {
                Text(String(localized: "No limit set", bundle: LanguageManager.shared.localizedBundle))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: onToggle) {
                Image(systemName: rule.enabled ? "pause.circle" : "play.circle")
                    .foregroundColor(rule.enabled ? .orange : .green)
            }
            .buttonStyle(.plain)
            .help(rule.enabled ? String(localized: "Disable", bundle: LanguageManager.shared.localizedBundle) : String(localized: "Enable", bundle: LanguageManager.shared.localizedBundle))

            Button(action: onEdit) {
                Image(systemName: "pencil.circle")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Edit", bundle: LanguageManager.shared.localizedBundle))

            Button(action: onDelete) {
                Image(systemName: "trash.circle")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Delete", bundle: LanguageManager.shared.localizedBundle))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}

// MARK: - Add Budget Rule Sheet

struct AddBudgetRuleSheet: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var isPresented: Bool

    @State private var scope: BudgetScope = .global
    @State private var agentId: String = "main"
    @State private var tokenLimitStr: String = "100000"
    @State private var costLimitStr: String = ""
    @State private var warnRatioStr: String = "80"

    private var existingIds: Set<String> {
        Set(viewModel.budgetService.config.rules.map(\.id))
    }

    private var hasGlobalRule: Bool {
        existingIds.contains("global")
    }

    /// Agents available for the picker, filtered out already-budgeted ones
    private var selectableAgents: [AgentOption] {
        viewModel.availableAgents
    }

    private var effectiveId: String {
        scope == .global ? "global" : agentId.trimmingCharacters(in: .whitespaces)
    }

    private var canSave: Bool {
        let id = effectiveId
        if id.isEmpty { return false }
        if existingIds.contains(id) { return false }
        return true
    }

    private var validationMessage: String? {
        let id = effectiveId
        if id.isEmpty { return String(localized: "Please select an Agent.", bundle: LanguageManager.shared.localizedBundle) }
        if existingIds.contains(id) { return String(format: String(localized: "A rule for \"%@\" already exists.", bundle: LanguageManager.shared.localizedBundle), id) }
        return nil
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(String(localized: "Add Budget Rule", bundle: LanguageManager.shared.localizedBundle))
                .font(.headline)

            Form {
                Picker(String(localized: "budget.scope.label", defaultValue: "Scope", bundle: LanguageManager.shared.localizedBundle), selection: $scope) {
                    Text(String(localized: "Global", bundle: LanguageManager.shared.localizedBundle)).tag(BudgetScope.global)
                    Text(String(localized: "Per Agent", bundle: LanguageManager.shared.localizedBundle)).tag(BudgetScope.agent)
                }

                if scope == .agent {
                    Picker(String(localized: "Agent", bundle: LanguageManager.shared.localizedBundle), selection: $agentId) {
                        ForEach(selectableAgents) { agent in
                            Text("\(agent.emoji) \(agent.name)")
                                .tag(agent.id)
                        }
                    }

                    if let msg = validationMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } else if hasGlobalRule {
                    Text(String(localized: "A global rule already exists. You can edit it from the rules list.", bundle: LanguageManager.shared.localizedBundle))
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                TextField(String(localized: "Token Limit", bundle: LanguageManager.shared.localizedBundle), text: $tokenLimitStr, prompt: Text(String(localized: "0 = no limit", bundle: LanguageManager.shared.localizedBundle)))
                    .textFieldStyle(.roundedBorder)

                TextField(String(localized: "budget.warning.pct", defaultValue: "Warning (%)", bundle: LanguageManager.shared.localizedBundle), text: $warnRatioStr, prompt: Text(String(localized: "e.g. 80", bundle: LanguageManager.shared.localizedBundle)))
                    .textFieldStyle(.roundedBorder)
            }
            .formStyle(.grouped)

            HStack {
                Button(String(localized: "Cancel", bundle: LanguageManager.shared.localizedBundle)) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(String(localized: "Add", bundle: LanguageManager.shared.localizedBundle)) {
                    let id = effectiveId
                    let agentName = viewModel.availableAgents.first(where: { $0.id == id })?.name ?? id
                    let ruleLabel = scope == .global ? String(localized: "Global", bundle: LanguageManager.shared.localizedBundle) : agentName

                    let rule = BudgetRule(
                        id: id,
                        scope: scope,
                        label: ruleLabel,
                        tokenLimit: Int(tokenLimitStr) ?? 0,
                        costLimit: Double(costLimitStr) ?? 0,
                        warnRatio: (Double(warnRatioStr) ?? 80) / 100.0,
                        enabled: true
                    )
                    viewModel.budgetService.addRule(rule)
                    viewModel.syncBudgetRules()
                    Task { await viewModel.loadBudgets() }
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            scope = hasGlobalRule ? .agent : .global
            // Ensure agents are loaded for the picker
            viewModel.loadAvailableAgents()
            // Default to first selectable agent
            if let first = selectableAgents.first {
                agentId = first.id
            }
        }
    }
}

// MARK: - Edit Budget Rule Sheet

struct EditBudgetRuleSheet: View {
    @ObservedObject var viewModel: DashboardViewModel
    let rule: BudgetRule
    @Binding var isPresented: Bool

    @State private var label: String = ""
    @State private var tokenLimitStr: String = ""
    @State private var costLimitStr: String = ""
    @State private var warnRatioStr: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text(String(localized: "Edit Budget Rule", bundle: LanguageManager.shared.localizedBundle))
                .font(.headline)

            Form {
                HStack {
                    Text(String(localized: "budget.scope.display", defaultValue: "Scope:", bundle: LanguageManager.shared.localizedBundle))
                    Text(LocalizedStringKey(rule.scope == .global ? "Global" : "Agent"))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text(String(localized: "ID:", bundle: LanguageManager.shared.localizedBundle))
                    Text(rule.id)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                TextField(String(localized: "Label", bundle: LanguageManager.shared.localizedBundle), text: $label)
                    .textFieldStyle(.roundedBorder)

                TextField(String(localized: "Token Limit", bundle: LanguageManager.shared.localizedBundle), text: $tokenLimitStr, prompt: Text(String(localized: "0 = no limit", bundle: LanguageManager.shared.localizedBundle)))
                    .textFieldStyle(.roundedBorder)

                TextField(String(localized: "budget.warning.pct", defaultValue: "Warning (%)", bundle: LanguageManager.shared.localizedBundle), text: $warnRatioStr, prompt: Text(String(localized: "e.g. 80", bundle: LanguageManager.shared.localizedBundle)))
                    .textFieldStyle(.roundedBorder)
            }
            .formStyle(.grouped)

            HStack {
                Button(String(localized: "Cancel", bundle: LanguageManager.shared.localizedBundle)) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(String(localized: "Save", bundle: LanguageManager.shared.localizedBundle)) {
                    var updated = rule
                    updated.label = label.isEmpty ? rule.label : label
                    updated.tokenLimit = Int(tokenLimitStr) ?? 0
                    updated.costLimit = Double(costLimitStr) ?? 0
                    updated.warnRatio = (Double(warnRatioStr) ?? 80) / 100.0
                    viewModel.budgetService.updateRule(updated)
                    viewModel.syncBudgetRules()
                    Task { await viewModel.loadBudgets() }
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            label = rule.label
            tokenLimitStr = rule.tokenLimit > 0 ? "\(rule.tokenLimit)" : ""
            costLimitStr = rule.costLimit > 0 ? String(format: "%.2f", rule.costLimit) : ""
            warnRatioStr = "\(Int(rule.warnRatio * 100))"
        }
    }
}

// MARK: - Formatting Helpers

private func formatTokenCount(_ n: Int) -> String {
    if n >= 1_000_000 {
        return String(format: "%.1fM", Double(n) / 1_000_000.0)
    } else if n >= 1_000 {
        return String(format: "%.1fK", Double(n) / 1_000.0)
    }
    return "\(n)"
}

