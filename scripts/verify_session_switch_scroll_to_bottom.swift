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

let dashboard = read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let sessionChangeHandler = slice(
    dashboard,
    from: ".onChange(of: currentActiveSessionId)",
    to: ".overlay(alignment: .trailing)"
)
let scheduledScroll = slice(
    dashboard,
    from: "private func scheduleSessionSwitchScrollToBottom",
    to: "private func beginRenderObservationForCurrentSession"
)

assertContains(
    sessionChangeHandler,
    "scheduleSessionSwitchScrollToBottom()",
    "active session changes should schedule a bottom scroll"
)
assertContains(
    scheduledScroll,
    "chatAutoScrollMode = .sessionJumping",
    "session switch should enter the explicit session-jump auto-scroll mode"
)
assertContains(
    scheduledScroll,
    "scheduledBottomScrollGeneration += 1",
    "session switch should create a cancellable scroll generation"
)
assertContains(
    scheduledScroll,
    "scrollToBottomIfAllowed(generation: generation)",
    "session switch should reuse the guarded bottom-scroll helper"
)
assertContains(
    scheduledScroll,
    "chatAutoScrollMode != .userDetached",
    "delayed bottom scrolls should not override a later user-detached scroll"
)
assertContains(
    scheduledScroll,
    ".now() + 0.05",
    "session switch should perform an early bottom scroll for warm sessions"
)
assertContains(
    scheduledScroll,
    ".now() + 0.25",
    "session switch should perform a follow-up bottom scroll after the first layout pass"
)
assertContains(
    scheduledScroll,
    ".now() + 0.70",
    "session switch should perform a late bottom scroll for cold async session loads"
)

print("Session switch scroll-to-bottom checks passed")
