//
//  DashboardViewModel+AgentSettings.swift
//  Agent settings panel logic extracted from DashboardViewModel.
//  P1 refactor: file split only, no behavior change.
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

    /// Load available models for the settings panel.
    func loadModelsForSettings() async {
        let localGroups = localProviderModelGroups()
        let localModels = localModelOptionsForActiveProvider()
        let output = await openclawService.runCommand(
            "openclaw models list --json 2>&1",
            timeout: 30
        )
        let models = SubAgentsViewModel.parseModelList(output: output)
        let scopedModels = modelsForActiveProvider(from: models)
        availableModelGroups = mergeModelGroups(base: localGroups, overlay: models)
        let activeProviderModels = mergeModelOptions(base: localModels, overlay: scopedModels)
        availableModelsForSettings = flattenModelGroups(availableModelGroups).isEmpty
            ? activeProviderModels
            : flattenModelGroups(availableModelGroups)
        ensureActiveComposerModel()
    }

    private func localProviderModelGroups() -> [ProviderModelGroup] {
        let configuredSources = settings.loadConfiguredProviderModelSources()
        let currentProviderKey = activeModelProviderKey()
        var getclawhubModels = configuredSources.first(where: { $0.providerKey == "getclawhub" })?.models ?? []
        getclawhubModels = filterAllowedGetClawHubModels(getclawhubModels)

        if getclawhubModels.isEmpty {
            getclawhubModels = allowedGetClawHubPresetModels()
        }

        var groups: [ProviderModelGroup] = []
        if !getclawhubModels.isEmpty {
            groups.append(ProviderModelGroup(
                providerKey: "getclawhub",
                displayName: "GetClawHub",
                models: modelOptions(from: getclawhubModels, providerKey: "getclawhub")
            ))
        }

        var customModels: [ModelOption] = []
        for source in configuredSources where source.providerKey != "getclawhub" {
            let sourceModels = source.providerKey == currentProviderKey && !editedConfiguredModels.isEmpty
                ? editedConfiguredModels
                : source.models
            customModels.append(contentsOf: modelOptions(from: sourceModels, providerKey: source.providerKey))
        }

        if currentProviderKey != "getclawhub",
           !configuredSources.contains(where: { $0.providerKey == currentProviderKey }),
           !editedConfiguredModels.isEmpty {
            customModels.append(contentsOf: modelOptions(from: editedConfiguredModels, providerKey: currentProviderKey))
        }

        let dedupedCustomModels = dedupeModelOptions(customModels)
        if !dedupedCustomModels.isEmpty {
            groups.append(ProviderModelGroup(
                providerKey: "custom",
                displayName: "Custom",
                models: dedupedCustomModels
            ))
        }

        return groups
    }

    private func localModelOptionsForActiveProvider() -> [ModelOption] {
        let providerKey = activeModelProviderKey()
        var models = editedConfiguredModels

        if activeModelProviderKey() == "getclawhub", models.isEmpty {
            models = presetManager.findProvider(byKey: "getclawhub")?.models ?? []
        }

        return models.map { model in
            let modelId = model.id.hasPrefix("\(providerKey)/") ? model.id : "\(providerKey)/\(model.id)"
            return ModelOption(id: modelId, name: model.name.isEmpty ? model.id : model.name, tags: [])
        }
    }

    private func activeModelProviderKey() -> String {
        if editedActiveServiceSource == "getclawhub" {
            return "getclawhub"
        }

        if !editedSelectedProviderKey.isEmpty {
            return editedSelectedProviderKey
        }

        if let currentAgentModel = availableAgents.first(where: { $0.id == selectedAgentId })?.model,
           let slash = currentAgentModel.firstIndex(of: "/") {
            let provider = String(currentAgentModel[..<slash])
            if provider != "getclawhub" {
                return provider
            }
        }

        return "custom"
    }

    private func modelsForActiveProvider(from models: [ModelOption]) -> [ModelOption] {
        let providerKey = activeModelProviderKey()
        return models.filter { option in
            option.id == providerKey || option.id.hasPrefix("\(providerKey)/")
        }
    }

    // internal: called from provider/config paths still in the main class (P1.5)
    func refreshAvailableModelsForCurrentProvider() {
        let groups = localProviderModelGroups()
        availableModelGroups = groups
        let flattenedGroups = flattenModelGroups(groups)
        availableModelsForSettings = flattenedGroups.isEmpty ? localModelOptionsForActiveProvider() : flattenedGroups
        ensureActiveComposerModel()
    }

    func ensureActiveComposerModel() {
        guard activeComposerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let defaultModel = modelOverview.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !defaultModel.isEmpty, defaultModel != "-" {
            activeComposerModel = defaultModel
            return
        }

        if let firstModel = flattenModelGroups(availableModelGroups).first?.id {
            activeComposerModel = firstModel
            return
        }

        if let firstModel = availableModelsForSettings.first?.id {
            activeComposerModel = firstModel
        }
    }

    private func modelOptions(from models: [PresetModel], providerKey: String) -> [ModelOption] {
        models.map { model in
            let modelId = model.id.hasPrefix("\(providerKey)/") ? model.id : "\(providerKey)/\(model.id)"
            return ModelOption(id: modelId, name: model.name.isEmpty ? model.id : model.name, tags: [])
        }
    }

    private func mergeModelGroups(base: [ProviderModelGroup], overlay: [ModelOption]) -> [ProviderModelGroup] {
        let overlayByProvider = Dictionary(grouping: overlay) { providerKey(for: $0.id) ?? "" }
        return base.map { group in
            let providerKeys = Set(group.models.compactMap { providerKey(for: $0.id) })
            let matchingOverlay = overlayByProvider
                .filter { providerKeys.contains($0.key) }
                .flatMap(\.value)
            return ProviderModelGroup(
                providerKey: group.providerKey,
                displayName: group.displayName,
                models: mergeModelOptions(base: group.models, overlay: matchingOverlay)
            )
        }
    }

    private func mergeModelOptions(base: [ModelOption], overlay: [ModelOption]) -> [ModelOption] {
        guard !overlay.isEmpty else { return dedupeModelOptions(base) }

        let overlayById = Dictionary(uniqueKeysWithValues: overlay.map { ($0.id, $0) })
        var result = base.map { baseModel in
            guard let overlayModel = overlayById[baseModel.id] else { return baseModel }
            return ModelOption(
                id: baseModel.id,
                name: overlayModel.name.isEmpty ? baseModel.name : overlayModel.name,
                tags: overlayModel.tags.isEmpty ? baseModel.tags : overlayModel.tags
            )
        }
        let baseIds = Set(base.map(\.id))
        result.append(contentsOf: overlay.filter { !baseIds.contains($0.id) })
        return dedupeModelOptions(result)
    }

    private func dedupeModelOptions(_ models: [ModelOption]) -> [ModelOption] {
        var seen = Set<String>()
        var result: [ModelOption] = []
        for model in models where !seen.contains(model.id) {
            seen.insert(model.id)
            result.append(model)
        }
        return result
    }

    private func flattenModelGroups(_ groups: [ProviderModelGroup]) -> [ModelOption] {
        dedupeModelOptions(groups.flatMap(\.models))
    }

    private func providerKey(for modelId: String) -> String? {
        guard let slash = modelId.firstIndex(of: "/") else { return nil }
        let provider = String(modelId[..<slash])
        return provider.isEmpty ? nil : provider
    }

    private func allowedGetClawHubPresetModels() -> [PresetModel] {
        let allPresetModels = presetManager.findProvider(byKey: "getclawhub")?.models ?? []
        return filterAllowedGetClawHubModels(allPresetModels)
    }

    private func filterAllowedGetClawHubModels(_ models: [PresetModel]) -> [PresetModel] {
        #if REQUIRE_LOGIN
        if let allowedModels = membershipManager?.membership?.models, !allowedModels.isEmpty {
            let allowedLowercased = Set(allowedModels.map { $0.lowercased() })
            return models.filter { allowedLowercased.contains($0.id.lowercased()) }
        }
        #endif
        return models
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

    /// Update the composer's app-level model selection without changing agent defaults.
    func selectComposerModel(_ model: String) {
        activeComposerModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
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
