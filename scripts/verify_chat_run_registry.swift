#!/usr/bin/env swift

import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) throws -> String {
    let url = root.appendingPathComponent(path)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CheckFailure(description: "Missing expected file: \(path)")
    }
    return try String(contentsOf: url, encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure(description: message) }
}

let taskState = try read("OpenClawInstaller/Features/Chat/State/TaskActivityState.swift")
let viewModel = try read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")
let helpers = try read("OpenClawInstaller/Features/Chat/ChatHelpers.swift")
let reconciliation = try read("OpenClawInstaller/Features/Chat/State/ChatRunReconciliation.swift")

try require(
    taskState.contains("@Published private(set) var runsByMessageId: [UUID: ChatRunState] = [:]"),
    "TaskActivityState must own one typed registry for every active or unresolved chat run."
)
for api in ["registerRun(", "bindGatewayRun(", "applyRunEvent(", "moveRunToBackground(", "removeRun("] {
    try require(taskState.contains("func \(api)"), "TaskActivityState is missing the \(api) API.")
}
try require(
    taskState.contains("var foregroundTaskIds: Set<UUID>") &&
        taskState.contains("var backgroundTaskIds: Set<UUID>"),
    "Foreground/background projections must be derived from the run registry."
)
try require(
    !taskState.contains("@Published var foregroundTaskIds") &&
        !taskState.contains("@Published var backgroundTaskIds") &&
        !taskState.contains("var taskAgentMap:") &&
        !taskState.contains("var taskSessionMap:"),
    "Parallel mutable task maps must not remain as competing sources of truth."
)
try require(
    !viewModel.contains("var activeChatRuns:") &&
        !viewModel.contains("var taskSessionKeyOverride:") &&
        !viewModel.contains("var taskAgentMap:") &&
        !viewModel.contains("var taskSessionMap:"),
    "DashboardViewModel must not recreate the removed parallel run dictionaries."
)
try require(
    helpers.contains("taskState.registerRun(") &&
        helpers.contains("taskState.bindGatewayRun(") &&
        helpers.contains("taskState.applyRunEvent("),
    "The send pipeline must drive the typed run registry through named transitions."
)
try require(
    helpers.contains("guard eventRunId == runId, eventSessionKey == sessionKey else { continue }"),
    "Every text terminal/delta event must match both the bound runId and sessionKey."
)
try require(
    helpers.contains("let run = taskState.run(for: messageId)") &&
        helpers.contains("sessionKey: run.gatewayBinding.sessionKey") &&
        reconciliation.contains("run.gatewayBinding.sessionKey == sessionKey"),
    "Cancellation must use the exact sessionKey in the current gateway binding."
)

print("PASS: chat run registry verified")
