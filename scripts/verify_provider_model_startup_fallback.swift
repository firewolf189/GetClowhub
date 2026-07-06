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

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let dashboardViewModel = read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")
let configProviderLogs = read("OpenClawInstaller/Features/Settings/ConfigProviderLogs.swift")
let providerModelSettings = read("OpenClawInstaller/Features/Settings/ProviderModels/ProviderModelSettings.swift")
let appSettings = read("OpenClawInstaller/Shared/Models/AppSettings.swift")

let initializerBlock = slice(
    dashboardViewModel,
    from: "// Initialize edited values from real config",
    to: "// Forward nested ObservableObject changes"
)
let syncFields = slice(
    configProviderLogs,
    from: "func syncEditedFieldsFromSettings()",
    to: "    /// Reload from disk and sync fields."
)
let loadModelsForSettings = slice(
    providerModelSettings,
    from: "func loadModelsForSettings() async",
    to: "    private func localProviderModelGroups()"
)

require(
    initializerBlock.contains("refreshAvailableModelsForCurrentProvider()"),
    "DashboardViewModel init must hydrate composer models from saved provider models before any CLI refresh"
)
require(
    syncFields.contains("refreshAvailableModelsForCurrentProvider()"),
    "syncEditedFieldsFromSettings must hydrate available model lists from configuredModels after reload/save"
)
require(
    loadModelsForSettings.contains("let localGroups = localProviderModelGroups()") &&
        loadModelsForSettings.contains("let localModels = localModelOptionsForActiveProvider()"),
    "loadModelsForSettings must compute local provider fallback before reading CLI models"
)
require(
    loadModelsForSettings.contains("availableModelGroups = mergeModelGroups(base: localGroups, overlay: models)") &&
        loadModelsForSettings.contains("mergeModelOptions(base: localModels, overlay: scopedModels)"),
    "loadModelsForSettings must merge same-provider CLI metadata into local models instead of replacing the list"
)
require(
    !loadModelsForSettings.contains("availableModelsForSettings = scopedModels.isEmpty ? localModels : scopedModels"),
    "loadModelsForSettings must not shrink saved custom/official models to a partial non-empty CLI result"
)
require(
    providerModelSettings.contains("private func mergeModelOptions(base: [ModelOption], overlay: [ModelOption]) -> [ModelOption]"),
    "ProviderModelSettings must provide a provider-scoped merge helper for local models plus CLI metadata"
)
require(
    providerModelSettings.contains("private func localModelOptionsForActiveProvider() -> [ModelOption]"),
    "ProviderModelSettings must expose one local provider-model fallback used by init, sync, and CLI refresh"
)

let localFallback = slice(
    providerModelSettings,
    from: "private func localModelOptionsForActiveProvider()",
    to: "    private func activeModelProviderKey()"
)

require(
    localFallback.contains(#"activeModelProviderKey() == "getclawhub""#),
    "local fallback must treat official GetClawHub as a first-class provider"
)
require(
    localFallback.contains(#"presetManager.findProvider(byKey: "getclawhub")?.models"#),
    "official provider fallback must use bundled/local provider preset models when config models are missing"
)
require(
    providerModelSettings.contains("first?.runtimeId"),
    "startup fallback must hydrate the active composer model with a runtime model id"
)
require(
    appSettings.contains(#"if newSettings.activeServiceSource == "getclawhub""#),
    "AppSettings.loadFromFile must populate configuredModels for the active official provider"
)
require(
    appSettings.contains(#"providers["getclawhub"] as? [String: Any]"#),
    "AppSettings.loadFromFile must read GetClawHub provider models from openclaw.json when present"
)
require(
    appSettings.contains("mergedRuntimeModelEntries"),
    "AppSettings.saveToFile must keep all configured provider models available to gateway runtime selection"
)

print("Provider model startup fallback verification passed")
