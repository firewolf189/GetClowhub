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

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let dashboard = read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")
let configProviderLogs = read("OpenClawInstaller/Features/Settings/ConfigProviderLogs.swift")
let configView = read("OpenClawInstaller/Features/Settings/Views/ConfigTabView.swift")

let providerPage = slice(
    configView,
    from: "case .provider:\n            settingsScroll {",
    to: "case .budget:"
)
let customProviderList = slice(
    configView,
    from: "struct CustomProviderListSection: View",
    to: "private struct AddCustomProviderSheet: View"
)
let addProviderSheet = slice(
    configView,
    from: "private struct AddCustomProviderSheet: View",
    to: "private struct CustomProviderCard: View"
)
let modelConfigSection = slice(
    configView,
    from: "struct ModelConfigSection: View",
    to: "private struct AddProviderModelSheet: View"
)

require(
    dashboard.contains("@Published var isPersistingProviderConfiguration = false"),
    "DashboardViewModel should expose a provider-scoped persistence state instead of reusing global restart/save state."
)

require(
    !providerPage.contains("SaveButtonsSection(viewModel: viewModel)") &&
        !providerPage.contains("saveAndRestartService"),
    "Providers page must not show the generic Save & Restart controls."
)

require(
    configProviderLogs.contains("func persistProviderConfiguration(") &&
        configProviderLogs.contains("applyEditedProviderConfigurationToSettings()") &&
        configProviderLogs.contains("settings.saveToFile()") &&
        configProviderLogs.contains("syncEditedProviderFieldsFromSettings()") &&
        !slice(configProviderLogs, from: "func persistProviderConfiguration(", to: "func saveConfiguration()").contains("restartService"),
    "Provider persistence should write openclaw.json through AppSettingsManager without restarting OpenClaw."
)

require(
    configProviderLogs.contains("func addCustomProvider(") &&
        configProviderLogs.contains("let snapshot = providerConfigurationSnapshot()") &&
        configProviderLogs.contains("restoreProviderConfiguration(snapshot)") &&
        configProviderLogs.contains("await persistProviderConfiguration()"),
    "Adding a provider should auto-persist after real provider state changes and rollback the UI state when saving fails."
)

require(
    customProviderList.contains("if pendingDeleteProviderKey == provider.key") &&
        customProviderList.contains("Task {") &&
        customProviderList.contains("await viewModel.deleteCustomProviderAndPersist(provider)") &&
        customProviderList.contains("pendingDeleteProviderKey = provider.key") &&
        !slice(customProviderList, from: "} else {", to: "    private func clearPendingProviderDelete()").contains("persistProviderConfiguration"),
    "The first provider delete click should only arm confirmation; only the confirmed second click may persist."
)

require(
    addProviderSheet.contains("viewModel.isPersistingProviderConfiguration") &&
        modelConfigSection.contains("await viewModel.persistProviderConfiguration(showSuccessMessage: true)") &&
        modelConfigSection.contains("await viewModel.addModelAndPersist(model)") &&
        modelConfigSection.contains("await viewModel.removeModelAndPersist(at: index)") &&
        modelConfigSection.contains("viewModel.isPersistingProviderConfiguration"),
    "Provider detail edits and model mutations should use provider-scoped persistence without Save & Restart."
)

print("Provider auto-persist without restart verification passed")
