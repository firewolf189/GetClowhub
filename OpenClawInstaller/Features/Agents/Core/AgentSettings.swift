//
//  AgentSettings.swift
//  Agent settings panel and persona file logic.
//

import Foundation
import SwiftUI

extension DashboardViewModel {

    // MARK: - Agent Settings Panel

    /// Load full agent detail (SubAgentInfo) for the currently selected agent.
    func loadSelectedAgentDetail() {
        let configPath = NSString("~/.openclaw/openclaw.json").expandingTildeInPath

        let agentList: [[String: Any]] = {
            guard let data = FileManager.default.contents(atPath: configPath),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let agents = json["agents"] as? [String: Any],
                  let list = agents["list"] as? [[String: Any]] else { return [] }
            return list
        }()

        let agentId = selectedAgentId
        // Sub-agents must exist in agents.list. The "main" agent is special:
        // openclaw doesn't always register it there (the workspace alone
        // defines it), so we treat a missing entry as an empty dict and let
        // the workspace files supply name/emoji/persona content.
        let entry: [String: Any] = agentList.first { $0["id"] as? String == agentId } ?? [:]
        guard !entry.isEmpty || agentId == "main" else {
            NSLog("[AgentSettings] loadSelectedAgentDetail: agent %@ not found in agents.list", agentId)
            return
        }

        // Determine workspace (faithful to openclaw's resolveAgentWorkspaceDir).
        let workspace = Self.resolveAgentWorkspace(agentId)

        let agentDir = entry["agentDir"] as? String ?? ""
        let model = entry["model"] as? String ?? ""
        let isDefault = entry["isDefault"] as? Bool ?? (agentId == "main")

        // Bindings
        var bindingDetails: [String] = []
        if let bindings = entry["bindings"] as? [[String: Any]] {
            for b in bindings {
                if let from = b["from"] as? String, let to = b["to"] as? String {
                    bindingDetails.append("\(from) → \(to)")
                }
            }
        } else if let bindings = entry["bindingDetails"] as? [String] {
            bindingDetails = bindings
        }

        // Read persona files
        let identityContent = readPersonaFile(workspace, "IDENTITY.md")
        let soulContent = readPersonaFile(workspace, "SOUL.md")
        let memoryContent = readPersonaFile(workspace, "MEMORY.md")
        let userContent = readPersonaFile(workspace, "USER.md")
        let agentsContent = readPersonaFile(workspace, "AGENTS.md")
        let bootstrapContent = readPersonaFile(workspace, "BOOTSTRAP.md")
        let heartbeatContent = readPersonaFile(workspace, "HEARTBEAT.md")
        let toolsContent = readPersonaFile(workspace, "TOOLS.md")

        let parsed = PersonaViewModel.parseIdentity(identityContent)
        let identity = entry["identity"] as? [String: Any]

        let name: String = {
            if !parsed.name.isEmpty { return parsed.name }
            if let n = identity?["name"] as? String, !n.isEmpty { return n }
            return entry["name"] as? String ?? agentId
        }()

        let identitySource = entry["identitySource"] as? String ?? ""

        var info = SubAgentInfo(
            id: agentId,
            name: name,
            emoji: "",
            creature: parsed.creature,
            model: model,
            isDefault: isDefault,
            bindingsCount: bindingDetails.count,
            bindingDetails: bindingDetails,
            identitySource: identitySource,
            workspace: workspace,
            agentDir: agentDir
        )
        info.identityContent = identityContent
        info.soulContent = soulContent
        info.memoryContent = memoryContent
        info.userContent = userContent
        info.agentsContent = agentsContent
        info.bootstrapContent = bootstrapContent
        info.heartbeatContent = heartbeatContent
        info.toolsContent = toolsContent
        info.identityOriginal = identityContent
        info.soulOriginal = soulContent
        info.memoryOriginal = memoryContent
        info.userOriginal = userContent
        info.agentsOriginal = agentsContent
        info.bootstrapOriginal = bootstrapContent
        info.heartbeatOriginal = heartbeatContent
        info.toolsOriginal = toolsContent

        selectedAgentDetail = info
    }

    /// Save a persona file for the selected agent.
    func saveAgentPersonaFile(file: PersonaViewModel.FileType) {
        guard var detail = selectedAgentDetail, !detail.workspace.isEmpty else { return }
        let workspace = detail.workspace

        switch file {
        case .identity:
            writePersonaFile(workspace, "IDENTITY.md", content: detail.identityContent)
            detail.identityOriginal = detail.identityContent
        case .soul:
            writePersonaFile(workspace, "SOUL.md", content: detail.soulContent)
            detail.soulOriginal = detail.soulContent
        case .memory:
            writePersonaFile(workspace, "MEMORY.md", content: detail.memoryContent)
            detail.memoryOriginal = detail.memoryContent
        case .user:
            break
        }
        selectedAgentDetail = detail
        loadAvailableAgents()
    }

    /// Update the model for the selected agent in openclaw.json.
    func updateAgentModel(model: String) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(homeDir)/.openclaw/openclaw.json"
        SubAgentsViewModel.patchAgentModel(configPath: configPath, agentId: selectedAgentId, model: model)

        // Update local detail
        selectedAgentDetail?.model = model
        loadAvailableAgents()
    }

    /// Binding for editing a persona file in the settings panel.
    func settingsBinding(for file: PersonaViewModel.FileType) -> Binding<String> {
        Binding<String>(
            get: {
                guard let detail = self.selectedAgentDetail else { return "" }
                switch file {
                case .identity: return detail.identityContent
                case .soul: return detail.soulContent
                case .memory: return detail.memoryContent
                case .user: return ""
                }
            },
            set: { newValue in
                guard self.selectedAgentDetail != nil else { return }
                switch file {
                case .identity: self.selectedAgentDetail?.identityContent = newValue
                case .soul: self.selectedAgentDetail?.soulContent = newValue
                case .memory: self.selectedAgentDetail?.memoryContent = newValue
                case .user: break
                }
            }
        )
    }

    /// Binding for editing a persona file in the settings panel (by file name string).
    func settingsBindingByName(_ fileName: String) -> Binding<String> {
        Binding<String>(
            get: {
                guard let detail = self.selectedAgentDetail else { return "" }
                switch fileName {
                case "USER.md": return detail.userContent
                case "AGENTS.md": return detail.agentsContent
                case "BOOTSTRAP.md": return detail.bootstrapContent
                case "HEARTBEAT.md": return detail.heartbeatContent
                case "TOOLS.md": return detail.toolsContent
                default: return ""
                }
            },
            set: { newValue in
                guard self.selectedAgentDetail != nil else { return }
                switch fileName {
                case "USER.md": self.selectedAgentDetail?.userContent = newValue
                case "AGENTS.md": self.selectedAgentDetail?.agentsContent = newValue
                case "BOOTSTRAP.md": self.selectedAgentDetail?.bootstrapContent = newValue
                case "HEARTBEAT.md": self.selectedAgentDetail?.heartbeatContent = newValue
                case "TOOLS.md": self.selectedAgentDetail?.toolsContent = newValue
                default: break
                }
            }
        )
    }

    /// Save a persona file by file name string.
    func savePersonaFileByName(_ fileName: String) {
        guard var detail = selectedAgentDetail, !detail.workspace.isEmpty else { return }
        let workspace = detail.workspace

        switch fileName {
        case "USER.md":
            writePersonaFile(workspace, fileName, content: detail.userContent)
            detail.userOriginal = detail.userContent
        case "AGENTS.md":
            writePersonaFile(workspace, fileName, content: detail.agentsContent)
            detail.agentsOriginal = detail.agentsContent
        case "BOOTSTRAP.md":
            writePersonaFile(workspace, fileName, content: detail.bootstrapContent)
            detail.bootstrapOriginal = detail.bootstrapContent
        case "HEARTBEAT.md":
            writePersonaFile(workspace, fileName, content: detail.heartbeatContent)
            detail.heartbeatOriginal = detail.heartbeatContent
        case "TOOLS.md":
            writePersonaFile(workspace, fileName, content: detail.toolsContent)
            detail.toolsOriginal = detail.toolsContent
        default: return
        }
        selectedAgentDetail = detail
        loadAvailableAgents()
    }

    /// Check if a persona file is dirty by file name string.
    func isFileDirtyByName(_ fileName: String) -> Bool {
        guard let detail = selectedAgentDetail else { return false }
        switch fileName {
        case "USER.md": return detail.userDirty
        case "AGENTS.md": return detail.agentsDirty
        case "BOOTSTRAP.md": return detail.bootstrapDirty
        case "HEARTBEAT.md": return detail.heartbeatDirty
        case "TOOLS.md": return detail.toolsDirty
        default: return false
        }
    }

    /// Check if a persona file exists (content or original is non-empty) by file name string.
    func hasPersonaFile(_ fileName: String) -> Bool {
        guard let detail = selectedAgentDetail else { return false }
        switch fileName {
        case "USER.md": return !detail.userContent.isEmpty || !detail.userOriginal.isEmpty
        case "AGENTS.md": return !detail.agentsContent.isEmpty || !detail.agentsOriginal.isEmpty
        case "BOOTSTRAP.md": return !detail.bootstrapContent.isEmpty || !detail.bootstrapOriginal.isEmpty
        case "HEARTBEAT.md": return !detail.heartbeatContent.isEmpty || !detail.heartbeatOriginal.isEmpty
        case "TOOLS.md": return !detail.toolsContent.isEmpty || !detail.toolsOriginal.isEmpty
        default: return false
        }
    }

    private func readPersonaFile(_ dirPath: String, _ name: String) -> String {
        let path = (dirPath as NSString).appendingPathComponent(name)
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private func writePersonaFile(_ dirPath: String, _ name: String, content: String) {
        let path = (dirPath as NSString).appendingPathComponent(name)
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
