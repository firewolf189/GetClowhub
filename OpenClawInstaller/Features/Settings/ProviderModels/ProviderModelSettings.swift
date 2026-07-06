//
//  ProviderModelSettings.swift
//  Provider/model settings and composer model selection logic.
//

import Foundation

extension DashboardViewModel {

    // MARK: - Provider Model Settings

    /// Load available models for the settings panel and composer model picker.
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
            let runtimeModelId = modelId
            return ModelOption(id: modelId, name: model.name.isEmpty ? model.id : model.name, tags: [], runtimeId: runtimeModelId)
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

        if let firstModel = flattenModelGroups(availableModelGroups).first?.runtimeId {
            activeComposerModel = firstModel
            return
        }

        if let firstModel = availableModelsForSettings.first?.runtimeId {
            activeComposerModel = firstModel
        }
    }

    /// Update the composer's app-level model selection without changing agent defaults.
    func selectComposerModel(_ model: String) {
        activeComposerModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func modelOptions(from models: [PresetModel], providerKey: String) -> [ModelOption] {
        models.map { model in
            let modelId = model.id.hasPrefix("\(providerKey)/") ? model.id : "\(providerKey)/\(model.id)"
            let runtimeModelId = modelId
            return ModelOption(id: modelId, name: model.name.isEmpty ? model.id : model.name, tags: [], runtimeId: runtimeModelId)
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
                tags: overlayModel.tags.isEmpty ? baseModel.tags : overlayModel.tags,
                runtimeId: baseModel.runtimeId
            )
        }
        let baseIds = Set(base.map(\.id))
        result.append(contentsOf: overlay.filter { !baseIds.contains($0.id) })
        return dedupeModelOptions(result)
    }

    private func dedupeModelOptions(_ models: [ModelOption]) -> [ModelOption] {
        var seen = Set<String>()
        var result: [ModelOption] = []
        for model in models where !seen.contains(model.runtimeId) {
            seen.insert(model.runtimeId)
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
        if let membershipManager {
            return membershipManager.filterAllowedGetClawHubModels(models)
        }
        #endif
        return models
    }

}
