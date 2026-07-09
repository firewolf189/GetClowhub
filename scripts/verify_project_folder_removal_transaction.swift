#!/usr/bin/env swift

import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func contents(_ path: String) throws -> String {
    let url = root.appendingPathComponent(path)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CheckFailure(description: "Missing expected file: \(path)")
    }
    return try String(contentsOf: url, encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw CheckFailure(description: message)
    }
}

func slice(_ text: String, from start: String, to end: String) throws -> String {
    guard let startRange = text.range(of: start),
          let endRange = text.range(of: end, range: startRange.upperBound..<text.endIndex) else {
        throw CheckFailure(description: "Could not slice \(start) -> \(end)")
    }
    return String(text[startRange.lowerBound..<endRange.lowerBound])
}

let sessionPersistence = try contents("OpenClawInstaller/Features/Sessions/SessionPersistence.swift")
let chatSessionStore = try contents("OpenClawInstaller/Features/Sessions/Services/ChatSessionStore.swift")
let dashboardView = try contents("OpenClawInstaller/Features/Dashboard/DashboardView.swift")

let rebuildProjectGroups = try slice(
    sessionPersistence,
    from: "private func rebuildProjectSessionGroups",
    to: "/// Remove in-memory UI state"
)

try require(
    !rebuildProjectGroups.contains("?? AgentProjectBinding"),
    "Project folders must not be recreated from orphan session metadata after the binding is removed."
)
try require(
    rebuildProjectGroups.contains("for binding in projectBindingsByAgent[agentId] ?? []"),
    "Project folders should be built binding-first so the binding is the sidebar source of truth."
)
try require(
    rebuildProjectGroups.contains("filter { $0.projectId == binding.projectId }"),
    "Binding-backed project folders should collect only sessions for that binding's project."
)

try require(
    chatSessionStore.contains("func deleteSessions(forAgent agentId: String, projectId: String) -> [UUID]"),
    "ChatSessionStore should expose a bulk deletion API scoped by agentId + projectId."
)

let bulkDelete = try slice(
    chatSessionStore,
    from: "func deleteSessions(forAgent agentId: String, projectId: String) -> [UUID]",
    to: "// MARK: - Queries"
)
try require(
    bulkDelete.contains("$0.agentId == agentId && $0.projectId == projectId"),
    "Bulk project deletion must filter by both agentId and projectId so other agents using the same project survive."
)
try require(
    bulkDelete.contains("deleteSessionFilesAndCache(id:"),
    "Bulk project deletion should share the same file/cache/debouncer cleanup as single-session deletion."
)
try require(
    bulkDelete.contains("writeIndex(forAgent: agentId)") && bulkDelete.contains("writeLegacyIndex()"),
    "Bulk project deletion should rewrite the affected agent index and legacy index after removing metadata."
)

let removeProject = try slice(
    sessionPersistence,
    from: "func removeProject(_ projectId: String, fromAgent agentId: String)",
    to: "/// Load `agentId`'s active session messages"
)
try require(
    removeProject.contains("chatSessionStore.deleteSessions(forAgent: agentId, projectId: projectId)"),
    "removeProject should delete all sessions under the removed project folder as one domain transaction."
)
try require(
    removeProject.contains("chatSessionStore.index") &&
        removeProject.range(of: "chatSessionStore.index")!.lowerBound < removeProject.range(of: "chatSessionStore.deleteSessions(forAgent: agentId, projectId: projectId)")!.lowerBound,
    "removeProject should collect affected session ids before deleting store metadata."
)
try require(
    removeProject.contains("for sessionId in deletedSessionIds"),
    "removeProject should clean task/runtime UI state for every deleted project session."
)
try require(
    removeProject.contains("cancelTasks(inSession: sessionId)") &&
        removeProject.contains("chatMessagesByInactiveSession.removeValue(forKey: sessionId)") &&
        removeProject.contains("loadingSessionIds.remove(sessionId)"),
    "removeProject should cancel tasks and drop inactive/loading state for deleted project sessions."
)
try require(
    removeProject.contains("promoteNextSession(forAgent: agentId, projectId: nil)"),
    "If the selected project session is deleted, the agent should land in a normal non-project session."
)
try require(
    removeProject.contains("appliedSessionModels.removeValue"),
    "removeProject should clear per-session model override cache entries for deleted project sessions."
)

try require(
    dashboardView.contains("private func prunePendingComposerMessagesForExistingSessions()"),
    "Dashboard chat UI should prune pending composer queues when deleted sessions disappear from navigation metadata."
)
try require(
    dashboardView.contains(".onChange(of: sessionState.sessionsByAgent)") &&
        dashboardView.contains(".onChange(of: sessionState.projectSessionsByAgent)") &&
        dashboardView.contains("prunePendingComposerMessagesForExistingSessions()"),
    "Dashboard chat UI should run pending-composer pruning when sidebar session metadata changes."
)

print("Project folder removal transaction checks passed")
