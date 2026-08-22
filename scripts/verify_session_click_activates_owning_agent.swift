import Foundation

// Clicking a session must activate the agent that OWNS it.
//
// Reported 2026-07-27: "直接点击切换会话时，激活的智能体没有跟着切换". The sidebar
// tap called `switchSession(to:)`, which applies the session to whatever agent
// happens to be selected. Clicking a session under another agent therefore:
//   * left the OLD agent highlighted (the row highlight is keyed on
//     `meta.agentId`, so the sidebar contradicted itself), and
//   * pointed that old agent at the session — the next send would build the
//     gateway key `agent:<wrong-agent>:<session>`.
//
// Only the pinned list passed `switchGlobally: true`, which is why pinned rows
// behaved correctly and in-agent rows did not.

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
        fputs("FAIL: could not read \(path)\n", stderr)
        exit(1)
    }
    return text
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let dashboard = ["OpenClawInstaller/Features/Dashboard/DashboardTypography.swift", "OpenClawInstaller/Features/Dashboard/DashboardView.swift", "OpenClawInstaller/Features/Dashboard/Sidebar/DashboardSidebar.swift", "OpenClawInstaller/Features/Chat/Views/ChatView.swift", "OpenClawInstaller/Features/Chat/Views/ComposerChrome.swift", "OpenClawInstaller/Features/Chat/Views/ChatBubbleViews.swift", "OpenClawInstaller/Features/Agents/Views/AgentSettingsPanel.swift", "OpenClawInstaller/Features/Dashboard/TerminalPanel.swift", "OpenClawInstaller/Features/Sessions/Views/SessionDetailsPanel.swift"].map(read).joined(separator: "\n")
let viewModel = read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")

// --- 1. The unsafe action must not be reachable from the sidebar at all ---
require(
    !dashboard.contains("let switchSession: (UUID) -> Void"),
    "DashboardSidebarActions must not expose an agent-agnostic session switch — that is the API that caused the bug"
)
require(
    dashboard.contains("let switchSessionInAgent: (UUID, String) -> Void"),
    "the sidebar needs an action that carries the owning agent id"
)
require(
    !dashboard.contains("actions.switchSession(meta.id)"),
    "session rows must not switch sessions without naming the owning agent"
)

// --- 2. The tap resolves the owner from the row, not from the selection ---
require(
    dashboard.contains("actions.switchSessionInAgent(meta.id, ownerAgentId)"),
    "the session row tap should pass the owning agent id"
)
require(
    dashboard.contains("agent.map(\\.id).flatMap { $0.isEmpty ? nil : $0 } ?? meta.agentId"),
    "the owner is the row's agent, falling back to the session metadata's agentId"
)
// The invariant that exposed the mismatch: the row highlight is keyed on the
// session's own agent, so the selection must follow it.
require(
    dashboard.contains("state.selectedAgentId == meta.agentId"),
    "the row highlight is keyed on the session's own agent — keep it that way, it is what makes a wrong selection visible"
)

// --- 3. The view model activates the agent before switching ---
require(
    viewModel.contains("func switchSession(to sessionId: UUID, inAgent agentId: String)"),
    "the view model needs a switch that also activates the owning agent"
)
guard let inAgentRange = viewModel.range(of: "func switchSession(to sessionId: UUID, inAgent agentId: String)") else {
    fputs("FAIL: could not locate switchSession(to:inAgent:)\n", stderr)
    exit(1)
}
let inAgentBody = String(viewModel[inAgentRange.upperBound...].prefix(900))
require(
    inAgentBody.contains("selectedAgentId = resolvedAgentId"),
    "switchSession(to:inAgent:) must set selectedAgentId"
)
require(
    inAgentBody.range(of: "selectedAgentId = resolvedAgentId")!.lowerBound
        < (inAgentBody.range(of: "switchSession(to: sessionId)")?.lowerBound ?? inAgentBody.endIndex),
    "the agent must be activated BEFORE delegating, or the delegate still writes the old agent's slot"
)
require(
    inAgentBody.contains("fromMetadata.isEmpty ? \"main\" : fromMetadata"),
    "keep the empty-agentId fallback: rows poisoned by the 2026-07-22 bug would otherwise blank the selection"
)

// --- 4. One implementation, not two ---
require(
    viewModel.contains("switchSession(to: sessionId, inAgent: meta.agentId)"),
    "switchSessionGlobally should delegate to switchSession(to:inAgent:) instead of repeating the agent-activation logic"
)

print("session-click agent activation guards hold")
