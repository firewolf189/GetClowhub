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

let config = read("OpenClawInstaller/Features/Settings/Views/ConfigTabView.swift")
let configProviderLogs = read("OpenClawInstaller/Features/Settings/ConfigProviderLogs.swift")

let customProviderList = slice(
    config,
    from: "struct CustomProviderListSection: View",
    to: "private struct AddCustomProviderSheet: View"
)
let customProviderDetails = slice(
    config,
    from: "private struct CustomProviderDetailsSection: View",
    to: "private struct AddProviderModelSheet: View"
)
let addCustomProvider = slice(
    configProviderLogs,
    from: "func addCustomProvider(",
    to: "func updateCustomProviderAndPersist("
)
let updateCustomProviderAndPersist = slice(
    configProviderLogs,
    from: "func updateCustomProviderAndPersist(",
    to: "func fetchModelsForCustomProvider("
)
let deleteCustomProvider = slice(
    configProviderLogs,
    from: "func deleteCustomProvider(_ provider: ConfiguredCustomProvider)",
    to: "@discardableResult\n    func deleteCustomProviderAndPersist"
)

require(
    customProviderList.contains("@State private var expandedProviderKey: String?") &&
        !customProviderList.contains("@State private var expandedProviderKeys: Set<String>"),
    "Provider cards should use one local expandedProviderKey so only one card can be expanded and highlighted."
)

require(
    customProviderList.contains("isHighlighted: expandedProviderKey == provider.key") &&
        customProviderList.contains("isExpanded: expandedProviderKey == provider.key") &&
        customProviderList.contains("CustomProviderDetailsSection(viewModel: viewModel, provider: provider)") &&
        !customProviderList.contains("isCurrentProvider(provider)") &&
        !customProviderList.contains("ModelConfigSection(viewModel: viewModel)"),
    "Provider card highlight and detail visibility must be driven only by local expansion state, not runtime selected provider state."
)

require(
    !customProviderList.contains("selectCustomProviderAndPersist") &&
        !customProviderList.contains("selectCustomProvider(provider)") &&
        !customProviderList.contains("persistProviderConfiguration()"),
    "Opening or closing a provider card must not select a runtime provider or persist openclaw.json."
)

require(
    customProviderDetails.contains("@State private var draftBaseUrl") &&
        customProviderDetails.contains("@State private var draftApiKey") &&
        customProviderDetails.contains("@State private var draftModels") &&
        customProviderDetails.contains("updateCustomProviderAndPersist(") &&
        customProviderDetails.contains("fetchModelsForCustomProvider(") &&
        !customProviderDetails.contains("$viewModel.editedModelBaseUrl") &&
        !customProviderDetails.contains("$viewModel.editedModelApiKey") &&
        !customProviderDetails.contains("viewModel.editedConfiguredModels"),
    "Expanded provider details must edit a card-local draft and persist that provider registry entry explicitly."
)

require(
    configProviderLogs.contains("func updateCustomProviderAndPersist(") &&
        configProviderLogs.contains("func fetchModelsForCustomProvider(") &&
        configProviderLogs.contains("persistCustomProviderRegistry(") &&
        !configProviderLogs.contains("func selectCustomProvider("),
    "View model should expose provider-registry operations that do not depend on selectedProviderKey UI state."
)

require(
    updateCustomProviderAndPersist.contains("upsertCustomProvider(provider)") &&
        updateCustomProviderAndPersist.contains("persistCustomProviderRegistry(") &&
        !updateCustomProviderAndPersist.contains("selectCustomProvider(") &&
        !updateCustomProviderAndPersist.contains("editedSelectedProviderKey"),
    "Saving a custom provider card must persist only the provider registry entry; it must not select or refresh the runtime provider."
)

require(
    deleteCustomProvider.contains("configuredCustomProviders.removeAll") &&
        !deleteCustomProvider.contains("selectCustomProvider(") &&
        !deleteCustomProvider.contains("configuredCustomProviders.first"),
    "Deleting a custom provider must remove the registry entry and clear stale legacy selection only; it must not auto-select another provider."
)

require(
    !addCustomProvider.contains("selectCustomProvider(provider)") &&
        addCustomProvider.contains("upsertCustomProvider(provider)") &&
        addCustomProvider.contains("await persistCustomProviderRegistry()"),
    "Adding a provider should add it to the registry and persist it without making it the selected runtime provider."
)

print("Provider card UI state boundary verification passed")
