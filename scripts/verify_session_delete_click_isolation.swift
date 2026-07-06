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

func assertNotContains(_ haystack: String, _ needle: String, _ message: String) {
    guard !haystack.contains(needle) else {
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

let dashboard = read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let viewModel = read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")

let sessionRows = slice(
    dashboard,
    from: "private func sessionRows(",
    to: "private func projectFolderRow"
)
let activeSessionChangeHandler = slice(
    dashboard,
    from: ".onChange(of: currentActiveSessionId)",
    to: ".overlay(alignment: .trailing)"
)
let deleteSession = slice(
    viewModel,
    from: "func deleteSession(_ sessionId: UUID)",
    to: "/// Toggle pinned state"
)

assertNotContains(
    sessionRows,
    "onSelect: {",
    "session row selection should stay on the whole row wrapper, not move into ChatSessionRow"
)
assertNotContains(
    sessionRows,
    "onRename: {",
    "session row rename should stay on the whole row wrapper, not move into ChatSessionRow"
)
assertContains(
    sessionRows,
    ".contentShape(Rectangle())",
    "the full session row should remain clickable"
)
assertContains(
    sessionRows,
    ".onTapGesture(count: 2)",
    "the full session row should keep double-click rename"
)
assertContains(
    sessionRows,
    "actions.switchSession(meta.id)",
    "the full session row should keep click-to-switch behavior"
)
assertContains(
    viewModel,
    "private var shouldSuppressNextSessionSwitchBottomScroll = false",
    "DashboardViewModel should track one-shot suppression for delete-triggered active-session promotion"
)
assertContains(
    viewModel,
    "func consumeSuppressNextSessionSwitchBottomScroll() -> Bool",
    "ChatView should consume delete-triggered scroll suppression without publishing another UI update"
)
assertContains(
    deleteSession,
    "shouldSuppressNextSessionSwitchBottomScroll = true",
    "deleting the active session should mark the following promoted session switch as scroll-suppressed"
)
assertContains(
    activeSessionChangeHandler,
    "viewModel.consumeSuppressNextSessionSwitchBottomScroll()",
    "active session changes should skip scheduled bottom scrolling when the change came from active-session deletion"
)

print("Session delete active-promotion scroll guard checks passed")
