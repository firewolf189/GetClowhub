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

let dashboardViewModel = try contents("OpenClawInstaller/ViewModels/DashboardViewModel.swift")
let chatRuntimeState = try contents("OpenClawInstaller/ViewModels/ChatRuntimeState.swift")
let taskActivityState = try contents("OpenClawInstaller/ViewModels/TaskActivityState.swift")
let sessionNavigationState = try contents("OpenClawInstaller/ViewModels/SessionNavigationState.swift")
let dashboardView = try contents("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let chatTimelineSurface = try contents("OpenClawInstaller/Views/Dashboard/ChatTimelineSurface.swift")

let dashboardPublishedBlockedNames = [
    "chatMessagesByAgent",
    "sessionsByAgent",
    "pinnedSessions",
    "projectBindingsByAgent",
    "projectSessionsByAgent",
    "generalSessionsByAgent",
    "projectsById",
    "selectedSessionIdByAgent",
    "isSendingMessage",
    "foregroundTaskIds",
    "backgroundTaskIds",
    "chatMessagesByInactiveSession",
    "loadingSessionIds",
    "selectedAgentId",
    "availableAgents"
]

for name in dashboardPublishedBlockedNames {
    try require(
        !dashboardViewModel.contains("@Published var \(name)"),
        "DashboardViewModel should not publish high-churn chat/session state: \(name)"
    )
}

for name in [
    "chatMessagesByAgent",
    "chatMessagesByInactiveSession",
    "loadingSessionIds"
] {
    try require(
        chatRuntimeState.contains("@Published var \(name)"),
        "ChatRuntimeState should publish chat runtime state: \(name)"
    )
}

for name in [
    "isSendingMessage",
    "foregroundTaskIds",
    "backgroundTaskIds"
] {
    try require(
        !chatRuntimeState.contains("@Published var \(name)"),
        "ChatRuntimeState should not publish task activity state: \(name)"
    )
    try require(
        taskActivityState.contains("@Published var \(name)"),
        "TaskActivityState should publish task activity state: \(name)"
    )
}

for name in [
    "taskAgentMap",
    "taskSessionMap"
] {
    try require(
        !chatRuntimeState.contains("var \(name)"),
        "ChatRuntimeState should not own task routing maps: \(name)"
    )
    try require(
        taskActivityState.contains("var \(name)"),
        "TaskActivityState should own task routing maps: \(name)"
    )
}

for name in [
    "sessionsByAgent",
    "pinnedSessions",
    "projectBindingsByAgent",
    "projectSessionsByAgent",
    "generalSessionsByAgent",
    "projectsById",
    "selectedSessionIdByAgent",
    "selectedAgentId",
    "availableAgents"
] {
    try require(
        sessionNavigationState.contains("@Published var \(name)"),
        "SessionNavigationState should publish session/sidebar state: \(name)"
    )
}

try require(
    dashboardViewModel.contains("let chatState = ChatRuntimeState()") &&
        dashboardViewModel.contains("let taskState = TaskActivityState()") &&
        dashboardViewModel.contains("let sessionState = SessionNavigationState()"),
    "DashboardViewModel should compose chat/task/session stores without publishing their high-churn fields itself."
)

try require(
    !dashboardView.contains("@ObservedObject private var chatState: ChatRuntimeState"),
    "DashboardView root should not observe chat message state; high-frequency message changes belong in ChatView/Timeline."
)

try require(
    dashboardView.contains("@ObservedObject var chatState: ChatRuntimeState") &&
        dashboardView.contains("@ObservedObject var taskState: TaskActivityState") &&
        dashboardView.contains("@ObservedObject var sessionState: SessionNavigationState"),
    "Dashboard chat surfaces should observe the dedicated chat/task/session stores directly."
)

try require(
    dashboardView.contains("private struct DashboardSessionTitleToolbarChip: View") &&
        dashboardView.contains("DashboardSessionTitleToolbarChip("),
    "Session title toolbar should be isolated in a small chat-observing child view."
)

try require(
    chatTimelineSurface.contains("@ObservedObject var taskState: TaskActivityState") &&
        !chatTimelineSurface.contains("@ObservedObject var chatState: ChatRuntimeState"),
    "ChatTimelineSurface should observe task activity only; messages are passed as value input."
)

print("chat/session state boundary checks passed")
