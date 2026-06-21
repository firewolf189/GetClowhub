#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

let gateway = try read("OpenClawInstaller/Services/GatewayClient.swift")
let viewModel = try read("OpenClawInstaller/ViewModels/DashboardViewModel.swift")

require(gateway.contains("\"caps\": [\"tool-events\"]"), "macOS gateway connect should subscribe to structured tool events")
require(gateway.contains("case activity(runId: String, sessionKey: String?, event: GatewayActivityEvent)"), "gateway chat events should include structured activity")
require(gateway.contains("handleAgentEventPayload"), "gateway should handle agent events, not only chat text events")
require(gateway.contains("stream == \"tool\""), "gateway should parse tool stream events")
require(gateway.contains("data[\"args\"] as? [String: Any]"), "gateway tool activity parser should read tool start args")
require(gateway.contains("delete data.result") == false, "macOS client should not depend on full tool result payloads")

require(viewModel.contains("case .activity(let eventRunId, _, let event):"), "dashboard stream loop should handle activity events")
require(viewModel.contains("mergeActivityEvent(event, into: &accumulatedActivityEvents)"), "activity events should merge into accumulated activities")
require(!viewModel.contains("ChatActivityExtractor.extract(from: accumulatedText)"), "activity should not be extracted from assistant text deltas")
require(!viewModel.contains("ChatActivityExtractor.extract(from: finalText)"), "activity should not be extracted from final assistant text")
require(!viewModel.contains("enum ChatActivityExtractor"), "hard-coded assistant-text activity extractor should be removed")

print("PASS: structured chat activity event contracts verified")
