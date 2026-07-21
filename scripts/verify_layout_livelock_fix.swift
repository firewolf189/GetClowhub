import Foundation

// Guards against the 2026-07-21 main-thread livelock: a SwiftUI <-> AppKit
// AutoLayout feedback loop (GraphHost.flushTransactions -> requestUpdate ->
// _postWindowNeedsUpdateConstraints -> _willUpdateConstraintsForSubtree ->
// minSize -> sizeThatFits -> ...) amplified by rebuilding the full chat
// timeline snapshot on every render.

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}

let dashboard = read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let timelineModels = read("OpenClawInstaller/Features/Chat/Models/ChatTimelineModels.swift")
let splitView = read("OpenClawInstaller/Features/Workspace/Views/Inspector/RightInspectorSplitView.swift")
let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")

// --- Amplifier: the timeline snapshot must be memoized, not rebuilt per render ---
require(
    timelineModels.contains("final class ChatTimelineSnapshotCache"),
    "ChatTimelineSnapshotCache must exist so the timeline is only rebuilt when inputs change"
)
require(
    !dashboard.contains("ChatTimelineSnapshot.build("),
    "DashboardView must not call ChatTimelineSnapshot.build directly inside a ViewBuilder — every render would copy every message row (livelock amplifier)"
)
require(
    dashboard.contains("timelineSnapshotCache.snapshot("),
    "DashboardView should obtain the timeline through the memoizing cache"
)

// --- Trigger: no synchronous re-layout while a layout pass may be running ---
// setSidebarWidth is reachable from viewDidLayout (applySidebarWidth) and from
// updateNSViewController; forcing layoutSubtreeIfNeeded there re-enters layout
// and keeps posting window constraint passes that never converge. Only the
// explicit animation setup (animateSidebarWidth) may force synchronous layout.
let setSidebarWidthBody: String = {
    guard let start = splitView.range(of: "private func setSidebarWidth(") else {
        fatalError("setSidebarWidth not found in RightInspectorSplitView")
    }
    let tail = splitView[start.lowerBound...]
    guard let end = tail.range(of: "\n    }") else {
        fatalError("setSidebarWidth body end not found")
    }
    return String(tail[..<end.upperBound])
}()
require(
    !setSidebarWidthBody.contains("layoutSubtreeIfNeeded"),
    "setSidebarWidth must not force synchronous layout — it runs inside viewDidLayout/updateNSViewController; use view.needsLayout = true"
)
require(
    setSidebarWidthBody.contains("needsLayout = true"),
    "setSidebarWidth should mark needsLayout so AppKit coalesces the pass"
)

require(
    project.contains("ChatTimelineModels.swift in Sources"),
    "ChatTimelineModels.swift must be compiled by the app target"
)

print("layout-livelock guards hold: snapshot memoized, no sync re-layout inside layout passes")
