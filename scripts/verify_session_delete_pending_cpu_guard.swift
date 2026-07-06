#!/usr/bin/env swift

import Foundation

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

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let dashboard = read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let tooltip = read("OpenClawInstaller/DesignSystem/Components/UnifiedTooltip.swift")

let sessionRows = slice(
    dashboard,
    from: "private func sessionRows(",
    to: "private func projectFolderRow"
)
let deleteIntent = slice(
    sessionRows,
    from: "onDeleteIntent: {",
    to: "onDeleteConfirm: {"
)
let hoverHandler = slice(
    sessionRows,
    from: ".onHover { hovering in",
    to: ".contextMenu"
)
let cancelDelete = slice(
    dashboard,
    from: "private func cancelSessionDeleteConfirmation()",
    to: "private func toggleAgentSectionCollapse()"
)
let tooltipCoordinator = slice(
    tooltip,
    from: "private final class UnifiedTooltipCoordinator",
    to: "private struct UnifiedTooltipBubble"
)
let tooltipPresent = slice(
    tooltipCoordinator,
    from: "private func present(relativeTo sourceView: NSView)",
    to: "private var fittingSize"
)

require(
    deleteIntent.contains("setSessionDeleteConfirmation(meta.id)"),
    "delete intent should enter pending delete through a single helper, not assign confirmingDeleteSessionId directly"
)
require(
    cancelDelete.contains("hoveredSessionId = nil"),
    "canceling pending delete should also clear session hover so hidden action buttons cannot keep a stale hover/update loop"
)
require(
    hoverHandler.contains("cancelSessionDeleteConfirmation()") &&
        hoverHandler.contains("else if hoveredSessionId == meta.id"),
    "leaving a session row should clear pending delete confirmation for that row"
)
require(
    tooltipCoordinator.contains("private var visibleFrame: NSRect?") &&
        tooltipCoordinator.contains("private var visibleContent: UnifiedTooltipContent?"),
    "UnifiedTooltip should track visible panel frame/content so repeated SwiftUI updates can be no-ops"
)
require(
    tooltipPresent.contains("guard !panel.isVisible") &&
        tooltipPresent.contains("visibleFrame != frame") &&
        tooltipPresent.contains("visibleContent != self.content") &&
        tooltipPresent.contains("else { return }"),
    "UnifiedTooltip present should be idempotent when the panel is already visible with the same frame and content"
)
require(
    tooltipCoordinator.contains("visibleFrame = nil") &&
        tooltipCoordinator.contains("visibleContent = nil"),
    "UnifiedTooltip close should reset visible frame/content bookkeeping"
)

print("Session delete pending CPU guard checks passed")
