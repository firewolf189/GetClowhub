#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let configURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Features")
    .appendingPathComponent("Settings")
    .appendingPathComponent("Views")
    .appendingPathComponent("ConfigTabView.swift")

let config = try String(contentsOf: configURL, encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fputs("FAIL: could not slice source between \(start) and \(end)\n", stderr)
        exit(1)
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let selectedSettingsContent = slice(
    config,
    from: "private var selectedSettingsContent: some View",
    to: "private func settingsScroll"
)

let personaCase = slice(
    selectedSettingsContent,
    from: "case .persona:",
    to: "case .status:"
)

require(
    personaCase.contains("AgentPersonaSettingsList(viewModel: viewModel)"),
    "Settings Persona should render the in-page agent persona manager instead of a jump button."
)

let agentPersonaView = slice(
    config,
    from: "private struct AgentPersonaSettingsList: View",
    to: "// MARK: - Gateway Settings Group"
)

require(
    agentPersonaView.contains("@State private var expandedAgentId: String?") &&
        agentPersonaView.contains("ForEach(viewModel.availableAgents)") &&
        agentPersonaView.contains("expandedAgentId = agent.id") &&
        agentPersonaView.contains("expandedAgentId = nil"),
    "Agent Persona settings should use a single expanded agent row from the available agents list."
)

require(
    agentPersonaView.contains("viewModel.loadAvailableAgents()") &&
        agentPersonaView.contains("viewModel.loadSelectedAgentDetail()") &&
        agentPersonaView.contains("viewModel.selectedAgentId = agent.id"),
    "Selecting an agent should reuse DashboardViewModel selection and detail loading."
)

require(
    agentPersonaView.contains("MarkdownFileEditor(") &&
        agentPersonaView.contains(#"title: "IDENTITY.md""#) &&
        agentPersonaView.contains(#"title: "SOUL.md""#) &&
        agentPersonaView.contains(#"title: "MEMORY.md""#) &&
        agentPersonaView.contains("viewModel.settingsBinding(for: .identity)") &&
        agentPersonaView.contains("viewModel.saveAgentPersonaFile(file: .identity)") &&
        agentPersonaView.contains("viewModel.settingsBinding(for: .soul)") &&
        agentPersonaView.contains("viewModel.saveAgentPersonaFile(file: .soul)") &&
        agentPersonaView.contains("viewModel.settingsBinding(for: .memory)") &&
        agentPersonaView.contains("viewModel.saveAgentPersonaFile(file: .memory)"),
    "Expanded agent rows should expose the core persona files with existing bindings and save actions."
)

require(
    agentPersonaView.contains("DisclosureGroup") &&
        agentPersonaView.contains("More files") &&
        agentPersonaView.contains(#""USER.md""#) &&
        agentPersonaView.contains(#""AGENTS.md""#) &&
        agentPersonaView.contains(#""BOOTSTRAP.md""#) &&
        agentPersonaView.contains(#""HEARTBEAT.md""#) &&
        agentPersonaView.contains(#""TOOLS.md""#) &&
        agentPersonaView.contains("viewModel.hasPersonaFile(fileName)") &&
        agentPersonaView.contains("viewModel.settingsBindingByName(fileName)") &&
        agentPersonaView.contains("viewModel.savePersonaFileByName(fileName)"),
    "Optional persona files should live in a collapsed More files group."
)

require(
    agentPersonaView.contains("personaStatusText") &&
        agentPersonaView.contains("unsavedFileCount") &&
        agentPersonaView.contains("compactWorkspacePath"),
    "Agent rows should stay compact with status and shortened workspace metadata."
)

print("Settings agent persona verification passed")
