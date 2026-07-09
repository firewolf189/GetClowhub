//
//  ConfigProviderLogs.swift
//  Configuration / provider switching / model-list editing / logs domains
//  extracted from DashboardViewModel.
//  P1 refactor: file split only, no behavior change.
//

import Foundation
import AppKit
import os.log

private struct ProviderConfigurationSnapshot {
    let modelBaseUrl: String
    let modelApiKey: String
    let selectedProviderKey: String
    let providerApi: String
    let configuredModels: [PresetModel]
    let activeServiceSource: String
    let customProviders: [ConfiguredCustomProvider]
    let providerModelFetchMessage: String
}

extension DashboardViewModel {

    // MARK: - Configuration Management

    /// Sync the edited text fields from in-memory settings (no file I/O).
    /// Safe to call from onAppear — does not trigger @Published on AppSettingsManager.
    func syncEditedFieldsFromSettings() {
        editedPort = String(settings.settings.gatewayPort)
        editedAuthToken = settings.settings.gatewayAuthToken
        syncEditedProviderFieldsFromSettings()
    }

    func syncEditedProviderFieldsFromSettings() {
        editedModelBaseUrl = settings.settings.modelBaseUrl
        editedModelApiKey = settings.settings.modelApiKey
        editedSelectedProviderKey = settings.settings.selectedProviderKey
        editedProviderApi = settings.settings.providerApi
        editedConfiguredModels = settings.settings.configuredModels
        editedActiveServiceSource = settings.settings.activeServiceSource
        configuredCustomProviders = settings.settings.customProviders

        if editedActiveServiceSource != "getclawhub",
           !editedSelectedProviderKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !configuredCustomProviders.contains(where: { $0.key == editedSelectedProviderKey }),
           (!editedModelBaseUrl.isEmpty || !editedConfiguredModels.isEmpty) {
            syncSelectedCustomProviderIntoRegistry()
        }
        refreshAvailableModelsForCurrentProvider()
    }

    /// Reload from disk and sync fields.
    func loadConfiguration() {
        settings.loadFromFile()
        syncEditedFieldsFromSettings()
    }

    func resetProviderConfiguration() {
        settings.loadFromFile()
        syncEditedProviderFieldsFromSettings()
    }

    @discardableResult
    func persistProviderConfiguration(showSuccessMessage shouldShowSuccessMessage: Bool = false) async -> Bool {
        guard !isPersistingProviderConfiguration else { return false }
        isPersistingProviderConfiguration = true
        let previousSettings = settings.settings
        defer { isPersistingProviderConfiguration = false }

        if editedActiveServiceSource == "getclawhub" {
            let trimmedApiKey = editedGetClawHubApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedApiKey.isEmpty else {
                settings.settings = previousSettings
                showErrorMessage(I18n.t("dashboard.config.error.saveFailed"))
                return false
            }

            let baseUrl = presetManager.findProvider(byKey: "getclawhub")?.baseUrl ?? "https://ai.getclawhub.com/v1"
            let allPresetModels = presetManager.findProvider(byKey: "getclawhub")?.models ?? []
            #if REQUIRE_LOGIN
            let models: [PresetModel]
            if let membershipManager {
                models = membershipManager.filterAllowedGetClawHubModels(allPresetModels)
            } else {
                models = allPresetModels
            }
            #else
            let models = allPresetModels
            #endif
            AppSettingsManager.writeGetClawHubProvider(apiKey: trimmedApiKey, models: models, baseUrl: baseUrl, activate: true)
            settings.loadFromFile()
            syncEditedProviderFieldsFromSettings()
            if shouldShowSuccessMessage {
                showSuccessMessage(I18n.t("dashboard.config.toast.saved"))
            }
            return true
        }

        applyEditedProviderConfigurationToSettings()
        guard settings.saveToFile() else {
            settings.settings = previousSettings
            showErrorMessage(I18n.t("dashboard.config.error.saveFailed"))
            return false
        }

        settings.loadFromFile()
        syncEditedProviderFieldsFromSettings()
        if shouldShowSuccessMessage {
            showSuccessMessage(I18n.t("dashboard.config.toast.saved"))
        }
        return true
    }

    func saveConfiguration() async {
        isPerformingAction = true

        // Validate port
        guard let port = Int(editedPort), port > 0, port < 65536 else {
            showErrorMessage(I18n.t("dashboard.config.error.invalidPort"))
            isPerformingAction = false
            return
        }

        // Update settings in memory
        settings.settings.gatewayPort = port
        settings.settings.gatewayAuthToken = editedAuthToken
        settings.settings.modelBaseUrl = editedModelBaseUrl
        settings.settings.modelApiKey = editedModelApiKey
        settings.settings.selectedProviderKey = editedSelectedProviderKey
        settings.settings.providerApi = editedProviderApi
        settings.settings.configuredModels = editedConfiguredModels
        settings.settings.activeServiceSource = editedActiveServiceSource
        syncSelectedCustomProviderIntoRegistry()
        settings.settings.customProviders = configuredCustomProviders

        // Write to ~/.openclaw/openclaw.json
        if settings.saveToFile() {
            // If GetClawHub is active and user edited the API key, update getclawhub provider
            if editedActiveServiceSource == "getclawhub" && !editedGetClawHubApiKey.isEmpty {
                let baseUrl = presetManager.findProvider(byKey: "getclawhub")?.baseUrl ?? "https://ai.getclawhub.com/v1"
                let allPresetModels = presetManager.findProvider(byKey: "getclawhub")?.models ?? []
                #if REQUIRE_LOGIN
                let models: [PresetModel]
                if let membershipManager {
                    models = membershipManager.filterAllowedGetClawHubModels(allPresetModels)
                } else {
                    models = allPresetModels
                }
                #else
                let models = allPresetModels
                #endif
                AppSettingsManager.writeGetClawHubProvider(apiKey: editedGetClawHubApiKey, models: models, baseUrl: baseUrl, activate: true)
            }
            settings.loadFromFile()
            syncEditedFieldsFromSettings()
            loadAvailableAgents()
            await loadModels()
            await loadModelsForSettings()
            showSuccessMessage(I18n.t("dashboard.config.toast.saved"))
        } else {
            showErrorMessage(I18n.t("dashboard.config.error.saveFailed"))
        }

        isPerformingAction = false
    }

    func saveAndRestartService() async {
        await saveConfiguration()

        if openclawService.status == .running {
            await restartService()
        }
    }

    func resetConfiguration() {
        loadConfiguration()
    }

    func openConfigFile() {
        settings.openConfigFile()
    }

    // MARK: - Provider Management

    func addCustomProvider(
        baseUrl: String,
        apiKey: String,
        api: String = "openai-completions",
        fetchModels: Bool
    ) async -> String? {
        let snapshot = providerConfigurationSnapshot()
        let trimmedBaseUrl = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseUrl.isEmpty else {
            providerModelFetchMessage = "Base URL is required."
            return nil
        }
        guard !fetchModels || !isFetchingProviderModels else { return nil }

        let providerKey = makeCustomProviderKey(baseUrl: trimmedBaseUrl)
        var provider = ConfiguredCustomProvider(
            key: providerKey,
            baseUrl: trimmedBaseUrl,
            apiKey: trimmedApiKey,
            api: api,
            models: []
        )

        upsertCustomProvider(provider)

        guard fetchModels else {
            providerModelFetchMessage = ""
            guard await persistCustomProviderRegistry() else {
                restoreProviderConfiguration(snapshot)
                return nil
            }
            return providerKey
        }
        isFetchingProviderModels = true
        providerModelFetchMessage = ""
        defer { isFetchingProviderModels = false }

        do {
            provider.models = try await providerModelFetchService.fetchModels(
                baseURL: trimmedBaseUrl,
                apiKey: trimmedApiKey
            )
            upsertCustomProvider(provider)
            providerModelFetchMessage = "Fetched \(provider.models.count) model\(provider.models.count == 1 ? "" : "s")."
        } catch {
            providerModelFetchMessage = error.localizedDescription
        }
        guard await persistCustomProviderRegistry() else {
            restoreProviderConfiguration(snapshot)
            return nil
        }
        return providerKey
    }

    @discardableResult
    func updateCustomProviderAndPersist(
        _ provider: ConfiguredCustomProvider,
        showSuccessMessage shouldShowSuccessMessage: Bool = false
    ) async -> Bool {
        let snapshot = providerConfigurationSnapshot()
        upsertCustomProvider(provider)
        guard await persistCustomProviderRegistry(showSuccessMessage: shouldShowSuccessMessage) else {
            restoreProviderConfiguration(snapshot)
            return false
        }
        return true
    }

    func fetchModelsForCustomProvider(baseUrl: String, apiKey: String) async throws -> [PresetModel] {
        try await providerModelFetchService.fetchModels(baseURL: baseUrl, apiKey: apiKey)
    }

    func deleteCustomProvider(_ provider: ConfiguredCustomProvider) {
        configuredCustomProviders.removeAll { $0.key == provider.key }
        if editedSelectedProviderKey == provider.key {
            clearSelectedCustomProviderConfiguration()
        }
    }

    @discardableResult
    func deleteCustomProviderAndPersist(_ provider: ConfiguredCustomProvider) async -> Bool {
        let snapshot = providerConfigurationSnapshot()
        deleteCustomProvider(provider)
        guard await persistCustomProviderRegistry() else {
            restoreProviderConfiguration(snapshot)
            return false
        }
        return true
    }

    func syncSelectedCustomProviderIntoRegistry() {
        guard editedActiveServiceSource != "getclawhub" else { return }
        let providerKey = editedSelectedProviderKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !providerKey.isEmpty else { return }
        let provider = ConfiguredCustomProvider(
            key: providerKey,
            baseUrl: editedModelBaseUrl,
            apiKey: editedModelApiKey,
            api: editedProviderApi,
            models: editedConfiguredModels
        )
        upsertCustomProvider(provider)
    }

    private func upsertCustomProvider(_ provider: ConfiguredCustomProvider) {
        if let index = configuredCustomProviders.firstIndex(where: { $0.key == provider.key }) {
            configuredCustomProviders[index] = provider
        } else {
            configuredCustomProviders.append(provider)
        }
    }

    private func clearSelectedCustomProviderConfiguration() {
        editedSelectedProviderKey = ""
        editedModelBaseUrl = ""
        editedModelApiKey = ""
        editedProviderApi = "openai-completions"
        editedConfiguredModels = []
        providerModelFetchMessage = ""
        refreshAvailableModelsForCurrentProvider()
    }

    @discardableResult
    func persistCustomProviderRegistry(showSuccessMessage shouldShowSuccessMessage: Bool = false) async -> Bool {
        guard !isPersistingProviderConfiguration else { return false }
        isPersistingProviderConfiguration = true
        let previousSettings = settings.settings
        defer { isPersistingProviderConfiguration = false }

        applyCustomProviderRegistryToSettings()
        guard settings.saveToFile() else {
            settings.settings = previousSettings
            showErrorMessage(I18n.t("dashboard.config.error.saveFailed"))
            return false
        }

        settings.loadFromFile()
        syncEditedProviderFieldsFromSettings()
        if shouldShowSuccessMessage {
            showSuccessMessage(I18n.t("dashboard.config.toast.saved"))
        }
        return true
    }

    func fetchModelsForSelectedProvider() async {
        guard !isFetchingProviderModels else { return }
        let snapshot = providerConfigurationSnapshot()
        isFetchingProviderModels = true
        providerModelFetchMessage = ""
        defer { isFetchingProviderModels = false }

        do {
            let models = try await providerModelFetchService.fetchModels(
                baseURL: editedModelBaseUrl,
                apiKey: editedModelApiKey
            )
            editedConfiguredModels = models
            syncSelectedCustomProviderIntoRegistry()
            providerModelFetchMessage = "Fetched \(models.count) model\(models.count == 1 ? "" : "s")."
            refreshAvailableModelsForCurrentProvider()
            guard await persistProviderConfiguration() else {
                restoreProviderConfiguration(snapshot)
                return
            }
        } catch {
            providerModelFetchMessage = error.localizedDescription
        }
    }

    // MARK: - Model List Editing

    /// Add a model to the edited models list
    func addModel(_ model: PresetModel) {
        let trimmedId = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return }
        var normalized = model
        normalized.id = trimmedId
        if normalized.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized.name = trimmedId
        }
        if let index = editedConfiguredModels.firstIndex(where: { $0.id == trimmedId }) {
            editedConfiguredModels[index] = normalized
        } else {
            editedConfiguredModels.append(normalized)
        }
        syncSelectedCustomProviderIntoRegistry()
        refreshAvailableModelsForCurrentProvider()
    }

    func addModelAndPersist(_ model: PresetModel) async {
        let snapshot = providerConfigurationSnapshot()
        addModel(model)
        guard await persistProviderConfiguration() else {
            restoreProviderConfiguration(snapshot)
            return
        }
    }

    /// Remove a model at the given index
    func removeModel(at index: Int) {
        guard index >= 0, index < editedConfiguredModels.count else { return }
        editedConfiguredModels.remove(at: index)
        syncSelectedCustomProviderIntoRegistry()
        refreshAvailableModelsForCurrentProvider()
    }

    func removeModelAndPersist(at index: Int) async {
        let snapshot = providerConfigurationSnapshot()
        removeModel(at: index)
        guard await persistProviderConfiguration() else {
            restoreProviderConfiguration(snapshot)
            return
        }
    }

    /// Open the providers preset file in TextEdit
    func openProviderPresetFile() {
        presetManager.openPresetFile()
    }

    private func makeCustomProviderKey(baseUrl: String) -> String {
        let seed = customProviderKeySeed(baseUrl: baseUrl)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        var slug = seed
            .lowercased()
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { partial, character in
                if character == "-", partial.last == "-" {
                    return
                }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        if slug.isEmpty || slug == "getclawhub" {
            slug = "custom"
        }

        let existingKeys = Set(configuredCustomProviders.map(\.key))
        guard existingKeys.contains(slug) else { return slug }

        var suffix = 2
        while existingKeys.contains("\(slug)-\(suffix)") {
            suffix += 1
        }
        return "\(slug)-\(suffix)"
    }

    private func customProviderKeySeed(baseUrl: String) -> String {
        guard let host = URLComponents(string: baseUrl)?.host, !host.isEmpty else {
            return "custom"
        }
        let cleanedHost = host
            .replacingOccurrences(of: "www.", with: "")
            .replacingOccurrences(of: "api.", with: "")
        if cleanedHost.rangeOfCharacter(from: CharacterSet.letters) == nil {
            return cleanedHost
        }
        return cleanedHost
            .split(separator: ".")
            .first
            .map(String.init)
            ?? "custom"
    }

    private func providerConfigurationSnapshot() -> ProviderConfigurationSnapshot {
        ProviderConfigurationSnapshot(
            modelBaseUrl: editedModelBaseUrl,
            modelApiKey: editedModelApiKey,
            selectedProviderKey: editedSelectedProviderKey,
            providerApi: editedProviderApi,
            configuredModels: editedConfiguredModels,
            activeServiceSource: editedActiveServiceSource,
            customProviders: configuredCustomProviders,
            providerModelFetchMessage: providerModelFetchMessage
        )
    }

    private func restoreProviderConfiguration(_ snapshot: ProviderConfigurationSnapshot) {
        editedModelBaseUrl = snapshot.modelBaseUrl
        editedModelApiKey = snapshot.modelApiKey
        editedSelectedProviderKey = snapshot.selectedProviderKey
        editedProviderApi = snapshot.providerApi
        editedConfiguredModels = snapshot.configuredModels
        editedActiveServiceSource = snapshot.activeServiceSource
        configuredCustomProviders = snapshot.customProviders
        providerModelFetchMessage = snapshot.providerModelFetchMessage
        refreshAvailableModelsForCurrentProvider()
    }

    private func applyEditedProviderConfigurationToSettings() {
        syncSelectedCustomProviderIntoRegistry()
        settings.settings.modelBaseUrl = editedModelBaseUrl
        settings.settings.modelApiKey = editedModelApiKey
        settings.settings.selectedProviderKey = editedSelectedProviderKey
        settings.settings.providerApi = editedProviderApi
        settings.settings.configuredModels = editedConfiguredModels
        settings.settings.activeServiceSource = editedActiveServiceSource
        settings.settings.customProviders = configuredCustomProviders
    }

    private func applyCustomProviderRegistryToSettings() {
        if editedActiveServiceSource != "getclawhub",
           let selectedProvider = configuredCustomProviders.first(where: { $0.key == editedSelectedProviderKey }) {
            editedModelBaseUrl = selectedProvider.baseUrl
            editedModelApiKey = selectedProvider.apiKey
            editedProviderApi = selectedProvider.api
            editedConfiguredModels = selectedProvider.models
        }

        settings.settings.modelBaseUrl = editedModelBaseUrl
        settings.settings.modelApiKey = editedModelApiKey
        settings.settings.selectedProviderKey = editedSelectedProviderKey
        settings.settings.providerApi = editedProviderApi
        settings.settings.configuredModels = editedConfiguredModels
        settings.settings.activeServiceSource = editedActiveServiceSource
        settings.settings.customProviders = configuredCustomProviders
    }

    // MARK: - Logs Management

    /// Load gateway logs from file
    func loadGatewayLogs() async {
        isLoadingLogs = true
        gatewayLogs = await openclawService.readGatewayLogs(lines: 200)
        isLoadingLogs = false
    }

    /// Start auto-refreshing logs every few seconds
    func startLogRefresh(interval: TimeInterval = 3.0) {
        stopLogRefresh()
        Task {
            await loadGatewayLogs()
        }
        logRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.loadGatewayLogs()
            }
        }
    }

    /// Stop auto-refreshing logs
    func stopLogRefresh() {
        logRefreshTimer?.invalidate()
        logRefreshTimer = nil
    }

    func clearLogs() {
        openclawService.clearLogs()
        showSuccessMessage(I18n.t("dashboard.logs.toast.cleared"))
    }

    func exportLogs() -> String {
        return openclawService.getLogsString()
    }

    func openLogFile() {
        openclawService.openLogs()
    }

}
