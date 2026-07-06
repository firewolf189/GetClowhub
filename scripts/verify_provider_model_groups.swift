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

let appSettings = read("OpenClawInstaller/Shared/Models/AppSettings.swift")
let dashboardViewModel = read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")
let providerModelSettings = read("OpenClawInstaller/Features/Settings/ProviderModels/ProviderModelSettings.swift")
let dashboard = read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let membershipManager = read("OpenClawInstaller/Core/Auth/MembershipManager.swift")
let configTabView = read("OpenClawInstaller/Features/Settings/Views/ConfigTabView.swift")
let configProviderLogs = read("OpenClawInstaller/Features/Settings/ConfigProviderLogs.swift")

let loadModelsForSettings = slice(
    providerModelSettings,
    from: "func loadModelsForSettings() async",
    to: "    private func localProviderModelGroups()"
)
let composerPanel = slice(
    dashboard,
    from: "private struct ComposerModelPanel: View",
    to: "private extension View"
)
let composerOverlay = slice(
    dashboard,
    from: "ComposerModelPanel(",
    to: "                    .fixedSize(horizontal: true, vertical: false)"
)

require(
    appSettings.contains("struct ConfiguredProviderModelSource"),
    "AppSettings must expose all configured provider model sources instead of only active configuredModels"
)
require(
    appSettings.contains("func loadConfiguredProviderModelSources() -> [ConfiguredProviderModelSource]"),
    "AppSettingsManager must provide a config/app-state merged provider model source API"
)
require(
    appSettings.contains("customProviderSnapshotsKey"),
    "provider model source loading must include saved custom provider snapshots"
)
require(
    dashboardViewModel.contains("var availableModelGroups: [ProviderModelGroup]"),
    "DashboardViewModel must expose grouped models through ModelSettingsViewModel"
)
require(
    providerModelSettings.contains("private func localProviderModelGroups() -> [ProviderModelGroup]"),
    "ProviderModelSettings must derive grouped models from local config and provider presets"
)
require(
    providerModelSettings.contains(#"displayName: "Custom""#),
    "custom and user-configured provider models must be grouped under Custom"
)
require(
    providerModelSettings.contains("providerKeys.contains($0.key)") &&
        !providerModelSettings.contains(#"group.providerKey == "custom" && $0.key != "getclawhub""#),
    "Custom group must not absorb every non-GetClawHub CLI model; it can only merge already configured provider keys"
)
require(
    providerModelSettings.contains(#"displayName: "GetClawHub""#),
    "official GetClawHub models must be grouped separately"
)
require(
    membershipManager.contains("func allowedGetClawHubModelIDs() -> [String]") &&
        membershipManager.contains("apiKeys.last(where: { $0.isActive })") &&
        membershipManager.contains("if let membership, !membership.models.isEmpty"),
    "MembershipManager must centralize GetClawHub allow-list priority as active key models, then membership models"
)
require(
    membershipManager.contains("func filterAllowedGetClawHubModels(_ models: [PresetModel]) -> [PresetModel]"),
    "MembershipManager must provide the shared official model filter"
)
require(
    providerModelSettings.contains("membershipManager.filterAllowedGetClawHubModels(models)") &&
        configTabView.contains("membershipManager.filterAllowedGetClawHubModels(officialPresetModels)") &&
        configProviderLogs.contains("membershipManager.filterAllowedGetClawHubModels(allPresetModels)"),
    "Composer, official settings card, and save flow must share the same GetClawHub model allow-list filter"
)
require(
    !providerModelSettings.contains("membershipManager?.membership?.models") &&
        !configProviderLogs.contains("membershipManager?.membership?.models") &&
        !configTabView.contains("activeOfficialModelAllowList"),
    "GetClawHub model filtering must not keep separate membership-only allow-list implementations"
)
require(
    loadModelsForSettings.contains("let localGroups = localProviderModelGroups()"),
    "loadModelsForSettings must start from local provider groups"
)
require(
    loadModelsForSettings.contains("mergeModelGroups(base: localGroups"),
    "loadModelsForSettings must merge CLI metadata into groups instead of replacing visible groups"
)
require(
    providerModelSettings.contains("availableModelsForSettings = flattenModelGroups("),
    "legacy flat model list must be a projection of the grouped source"
)
require(
    composerOverlay.contains("modelGroups: viewModel.availableModelGroups"),
    "composer overlay must pass provider groups into the model panel"
)
require(
    composerPanel.contains("let modelGroups: [ProviderModelGroup]"),
    "ComposerModelPanel must receive grouped model data"
)
require(
    composerPanel.contains("ForEach(modelGroups)"),
    "ComposerModelPanel must render provider sections"
)
require(
    composerPanel.contains("group.displayName"),
    "ComposerModelPanel must show provider section headers"
)
require(
    !composerPanel.contains("providerSubtitle("),
    "ComposerModelPanel must not show underlying custom provider keys inside Custom group rows"
)
require(
    composerPanel.contains("allModelIds"),
    "ComposerModelPanel must preserve a current-model row when it is outside all groups"
)

print("Provider model groups verification passed")
