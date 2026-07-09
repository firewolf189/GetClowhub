#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func require(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}

let appSettings = read("OpenClawInstaller/Shared/Models/AppSettings.swift")
let dashboardViewModel = read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")
let configProviderLogs = read("OpenClawInstaller/Features/Settings/ConfigProviderLogs.swift")
let config = read("OpenClawInstaller/Features/Settings/Views/ConfigTabView.swift")

require(
    appSettings.contains("struct ConfiguredCustomProvider") &&
        appSettings.contains("var customProviders: [ConfiguredCustomProvider] = []"),
    "AppSettings must model user-configured custom providers separately from provider presets."
)
require(
    appSettings.contains("customProvider(\n        from key: String") &&
        appSettings.contains("runtimeCustomProviderDictionary(from provider: ConfiguredCustomProvider)") &&
        !appSettings.contains("customProviderSnapshotDictionary(from provider: ConfiguredCustomProvider)") &&
        !appSettings.contains("customProviderSnapshotsKey"),
    "AppSettings save/load must round-trip custom providers from openclaw.json without duplicate UI snapshots."
)
require(
    dashboardViewModel.contains("@Published var configuredCustomProviders: [ConfiguredCustomProvider] = []") &&
        (dashboardViewModel.contains("configuredCustomProviders != settings.settings.customProviders") ||
            dashboardViewModel.contains("configuredCustomProviders != s.customProviders")),
    "DashboardViewModel must publish configured custom providers and include them in unsaved-change tracking."
)
require(
    !configProviderLogs.contains("func addCustomProvider(from preset: ProviderPreset, apiKey: String)") &&
        configProviderLogs.contains("func deleteCustomProvider(_ provider: ConfiguredCustomProvider)") &&
        !configProviderLogs.contains("func selectCustomProvider(_ provider: ConfiguredCustomProvider)") &&
        configProviderLogs.contains("syncSelectedCustomProviderIntoRegistry()") &&
        configProviderLogs.contains("func addModel(_ model: PresetModel)") &&
        configProviderLogs.contains("syncSelectedCustomProviderIntoRegistry()") &&
        configProviderLogs.contains("refreshAvailableModelsForCurrentProvider()"),
    "Provider settings must add, delete, edit models, and persist configured custom providers through the view model without exposing an unused card-selection helper."
)
require(
    config.contains("ForEach(viewModel.configuredCustomProviders)") &&
        config.contains("providerTitle(for: provider)") &&
        !config.contains("return !provider.models.isEmpty"),
    "Provider UI must derive provider titles from runtime provider fields and not treat preset model lists as configured-provider state."
)

print("Configured custom provider registry verification passed")
