//
//  DashboardViewModel+ConfigProviderLogs.swift
//  Configuration / provider switching / model-list editing / logs domains
//  extracted from DashboardViewModel.
//  P1 refactor: file split only, no behavior change.
//

import Foundation
import AppKit
import os.log

extension DashboardViewModel {

    // MARK: - Configuration Management

    /// Sync the edited text fields from in-memory settings (no file I/O).
    /// Safe to call from onAppear — does not trigger @Published on AppSettingsManager.
    func syncEditedFieldsFromSettings() {
        editedPort = String(settings.settings.gatewayPort)
        editedAuthToken = settings.settings.gatewayAuthToken
        editedModelBaseUrl = settings.settings.modelBaseUrl
        editedModelApiKey = settings.settings.modelApiKey
        editedSelectedProviderKey = settings.settings.selectedProviderKey
        editedProviderApi = settings.settings.providerApi
        editedConfiguredModels = settings.settings.configuredModels
        editedActiveServiceSource = settings.settings.activeServiceSource
        availableProviders = presetManager.loadPresets().filter { $0.key != "getclawhub" }

        // If no config file exists yet, populate from preset defaults
        if editedModelBaseUrl.isEmpty,
           let preset = availableProviders.first(where: { $0.key == editedSelectedProviderKey }) {
            editedModelBaseUrl = preset.baseUrl
            editedProviderApi = preset.api
            editedConfiguredModels = preset.models
        }
        refreshAvailableModelsForCurrentProvider()
    }

    /// Reload from disk and sync fields.
    func loadConfiguration() {
        settings.loadFromFile()
        syncEditedFieldsFromSettings()
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

        // Write to ~/.openclaw/openclaw.json
        if settings.saveToFile() {
            // If GetClawHub is active and user edited the API key, update getclawhub provider
            if editedActiveServiceSource == "getclawhub" && !editedGetClawHubApiKey.isEmpty {
                let baseUrl = presetManager.findProvider(byKey: "getclawhub")?.baseUrl ?? "https://ai.getclawhub.com/v1"
                let allPresetModels = presetManager.findProvider(byKey: "getclawhub")?.models ?? []
                #if REQUIRE_LOGIN
                // Filter by membership allowed models if available. Case-insensitive
                // to absorb backend ↔ preset casing drift (e.g. `MiniMax-M2.7-highspeed`
                // vs `minimax-m2.7-highspeed`); see MembershipManager.applyKeyToConfig.
                let models: [PresetModel]
                if let allowedModels = membershipManager?.membership?.models, !allowedModels.isEmpty {
                    let allowedLowercased = Set(allowedModels.map { $0.lowercased() })
                    models = allPresetModels.filter { allowedLowercased.contains($0.id.lowercased()) }
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

    // MARK: - Provider Switching

    /// Request to switch provider — shows confirmation alert
    func requestSwitchProvider(to key: String) {
        if key == editedSelectedProviderKey { return }
        pendingProviderKey = key
        showProviderSwitchConfirm = true
    }

    /// Confirm provider switch — fills baseUrl, api, models from preset
    func confirmSwitchProvider() {
        let key = pendingProviderKey
        editedSelectedProviderKey = key
        providerModelFetchMessage = ""
        if let preset = presetManager.findProvider(byKey: key) {
            editedModelBaseUrl = preset.baseUrl
            editedProviderApi = preset.api
            editedConfiguredModels = preset.models
            editedModelApiKey = ""
        }
        pendingProviderKey = ""
        showProviderSwitchConfirm = false
    }

    func fetchModelsForSelectedProvider() async {
        guard !isFetchingProviderModels else { return }
        isFetchingProviderModels = true
        providerModelFetchMessage = ""
        defer { isFetchingProviderModels = false }

        do {
            let models = try await providerModelFetchService.fetchModels(
                baseURL: editedModelBaseUrl,
                apiKey: editedModelApiKey
            )
            editedConfiguredModels = models
            providerModelFetchMessage = "Fetched \(models.count) model\(models.count == 1 ? "" : "s")."
            refreshAvailableModelsForCurrentProvider()
        } catch {
            providerModelFetchMessage = error.localizedDescription
        }
    }

    /// Cancel provider switch
    func cancelSwitchProvider() {
        pendingProviderKey = ""
        showProviderSwitchConfirm = false
    }

    // MARK: - Model List Editing

    /// Add a model to the edited models list
    func addModel(_ model: PresetModel) {
        editedConfiguredModels.append(model)
    }

    /// Remove a model at the given index
    func removeModel(at index: Int) {
        guard index >= 0, index < editedConfiguredModels.count else { return }
        editedConfiguredModels.remove(at: index)
        refreshAvailableModelsForCurrentProvider()
    }

    /// Open the providers preset file in TextEdit
    func openProviderPresetFile() {
        presetManager.openPresetFile()
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
