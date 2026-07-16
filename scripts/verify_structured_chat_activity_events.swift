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

let gateway = try read("OpenClawInstaller/Core/Gateway/GatewayClient.swift")
let gatewayEvents = try read("OpenClawInstaller/Core/Gateway/GatewayChatEvent.swift")
let viewModel = try read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")
let helpers = try read("OpenClawInstaller/Features/Chat/ChatHelpers.swift")
let activityModel = try read("OpenClawInstaller/Features/Chat/Models/ChatActivityEvent.swift")
let chatImplementation = viewModel + helpers + activityModel
let gatewayProtocol = gateway + gatewayEvents

require(gateway.contains("\"caps\": [\"tool-events\"]"), "macOS gateway connect should subscribe to structured tool events")
require(gatewayProtocol.contains("case activity(runId: String, sessionKey: String?, event: GatewayActivityEvent)"), "gateway chat events should include structured activity")
require(gateway.contains("handleAgentEventPayload"), "gateway should handle agent events, not only chat text events")
require(gateway.contains("stream == \"tool\""), "gateway should parse tool stream events")
require(gateway.contains("data[\"args\"] as? [String: Any]"), "gateway tool activity parser should read tool start args")
require(gatewayProtocol.contains("case agentUsed"), "gateway activity events should include structured agent usage")
require(gatewayProtocol.contains("case agentRecruited"), "gateway activity events should include structured agent recruitment")
require(gateway.contains("parseAgentActivity"), "gateway should parse structured agent/recruit events without reading assistant prose")
require(gateway.contains("delete data.result") == false, "macOS client should not depend on full tool result payloads")

require(helpers.contains("case .activity(let eventRunId, let eventSessionKey, let event):"), "dashboard stream loop should handle activity events")
require(chatImplementation.contains("mergeActivityEvent(event, into: &accumulatedActivityEvents)"), "activity events should merge into accumulated activities")
require(chatImplementation.contains("case agentUsed"), "chat activity model should represent structured agent usage")
require(chatImplementation.contains("case agentRecruited"), "chat activity model should represent structured agent recruitment")
require(chatImplementation.contains("Used \\(count) \\(count == 1 ? \"agent\" : \"agents\")"), "working summary should describe used agents")
require(chatImplementation.contains("Recruited \\(count) \\(count == 1 ? \"agent\" : \"agents\")"), "working summary should describe recruited agents")
require(!chatImplementation.contains("ChatActivityExtractor.extract(from: accumulatedText)"), "activity should not be extracted from assistant text deltas")
require(!chatImplementation.contains("ChatActivityExtractor.extract(from: finalText)"), "activity should not be extracted from final assistant text")
require(!chatImplementation.contains("enum ChatActivityExtractor"), "hard-coded assistant-text activity extractor should be removed")

print("PASS: structured chat activity event contracts verified")
