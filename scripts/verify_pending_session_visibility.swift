import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func assertContains(_ haystack: String, _ needle: String, _ message: String) {
    guard haystack.contains(needle) else {
        fatalError(message)
    }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let viewModel = read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")
let rebuildSessionsMirror = slice(viewModel, from: "func rebuildSessionsMirror()", to: "/// Remove in-memory UI state")
let switchSession = slice(viewModel, from: "func switchSession(to sessionId: UUID)", to: "/// Switch to a session")
let createNewSession = slice(viewModel, from: "func createNewSession(forAgent agentId: String)", to: "/// Cancel any pending debounced write")
let pendingHelpers = slice(viewModel, from: "private func discardEmptyPendingSessionIfNeeded", to: "/// Cancel any pending debounced write")

assertContains(
    viewModel,
    "private var pendingSessionMetadataByAgent: [String: ChatSessionMetadata] = [:]",
    "view model should track unsaved empty sessions separately from persisted sessions"
)
assertContains(
    rebuildSessionsMirror,
    "let persistedSessionIds = Set(chatSessionStore.index.map(\\.id))",
    "rebuild should detect when a pending session has become persisted"
)
assertContains(
    rebuildSessionsMirror,
    "for pending in pendingSessionMetadataByAgent.values",
    "rebuild should merge unsaved pending sessions into the sidebar mirror"
)
assertContains(
    switchSession,
    "discardEmptyPendingSessionIfNeeded(forAgent: agentId)",
    "switching back to an old session should discard an unused empty pending session first"
)
assertContains(
    createNewSession,
    "pendingSessionMetadataByAgent[agentId] = ChatSessionMetadata(from: new)",
    "new empty sessions should be visible in the sidebar before they are persisted"
)
assertContains(
    createNewSession,
    "rebuildSessionsMirror()",
    "creating an empty pending session should refresh the sidebar mirror immediately"
)
assertContains(
    pendingHelpers,
    "pendingSessionMetadataByAgent.removeValue(forKey: agentId)",
    "discarding an unused pending session should remove its sidebar metadata"
)

print("Pending session visibility checks passed")
