#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("OpenClawInstaller/Core/Gateway/GatewayClient.swift")
let source = try String(contentsOf: sourceURL, encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

// Token-failure keywords must stay in the single declared table.
require(
    source.contains("static let deviceTokenFailureSignals: [String]"),
    "Device-token failure keywords must live in the deviceTokenFailureSignals table."
)
require(
    source.contains("for s in deviceTokenFailureSignals"),
    "isDeviceTokenAuthFailure must iterate deviceTokenFailureSignals, not inline literals."
)

// Tool-name → activity-kind mapping must stay in the single declared table.
require(
    source.contains("static let activityKindByToolName: [String: GatewayActivityEvent.Kind]"),
    "Tool classification must live in the activityKindByToolName table."
)
require(
    source.contains("Self.activityKindByToolName[normalizedTool]"),
    "parseToolActivity must resolve kinds through activityKindByToolName."
)
require(
    !source.contains("case \"read\", \"read_file\""),
    "Tool classification must not regress to an inline switch over tool-name literals."
)

// Unknown tools must degrade visibly, never silently.
require(
    source.contains("GatewayActivityEvent(kind: .loadedTools, detail: toolName"),
    "Unknown tool names must fall back to .loadedTools with the raw name as detail."
)

print("OK: gateway protocol string tables are centralized")
