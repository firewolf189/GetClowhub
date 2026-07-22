import Foundation

// Guards against the 2026-07-22 "Malformed agent session key" incident: the
// create-agent sheet read the @State-derived `sanitizedId` AFTER dismissing
// itself (`isPresented = false`), and SwiftUI returns the @State INITIAL value
// ("") once the view is torn down — so onCreatedWithId received "" and the
// chat pipeline built `agent::<uuid>` keys the gateway rejects.

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

let sheet = read("OpenClawInstaller/Features/Agents/SubAgents/SubAgentsTabView.swift")
let helpers = read("OpenClawInstaller/Features/Chat/ChatHelpers.swift")
let dvm = read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")

// Root fix: the id must be captured into a constant BEFORE the async Task so
// it survives sheet dismissal.
require(
    sheet.contains("let createdId = sanitizedId"),
    "CreateAgentSheet must capture sanitizedId into a constant before the create Task — @State reads after dismissal return the initial empty value"
)
require(
    !sheet.contains("onCreatedWithId?(sanitizedId)"),
    "onCreatedWithId must report the pre-captured id, never re-read sanitizedId after dismissal"
)

// Defense: the send pipeline must never build a session key with an empty
// agent id (gateway: parseAgentSessionKey -> malformed_agent -> refusal).
require(
    helpers.contains("currentAgentId.isEmpty"),
    "sendChatMessage must guard against an empty selectedAgentId before building the session key"
)

// Defense: switching to a session whose stored metadata carries an empty
// agentId (already-poisoned index rows) must not re-poison the selection.
require(
    dvm.contains("meta.agentId.isEmpty"),
    "switchSessionGlobally must normalize empty stored agentIds instead of assigning them to selectedAgentId"
)

print("agent-creation id-capture guards hold")
