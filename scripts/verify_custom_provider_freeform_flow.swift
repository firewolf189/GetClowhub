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
    to: "private struct CustomProviderCard: View"
)
let customProviderCard = slice(
    config,
    from: "private struct CustomProviderCard: View",
    to: "private struct EmptyCustomProvidersView"
)
let addCustomProviderSheet = slice(
    config,
    from: "private struct AddCustomProviderSheet: View",
    to: "private struct CustomProviderCard: View"
)

require(
    customProviderList.contains("@State private var expandedProviderKey: String?") &&
        customProviderList.contains("toggleProviderExpansion(provider)") &&
        customProviderList.contains("activateProviderCard(provider)") &&
        customProviderList.contains("expandedProviderKey == provider.key") &&
        customProviderList.contains("isExpanded: expandedProviderKey == provider.key"),
    "Custom provider list must keep card expansion state separate from selected provider state."
)

require(
    customProviderList.contains("@State private var isShowingAddProviderSheet = false") &&
        customProviderList.contains(".sheet(isPresented: $isShowingAddProviderSheet)") &&
        customProviderList.contains("AddCustomProviderSheet(") &&
        !customProviderList.contains("AddCustomProviderCard(") &&
        !customProviderList.contains("openProviderPresetFile()") &&
        !customProviderList.contains("Manage Presets"),
    "Custom provider list should open a dedicated add dialog and no longer expose preset management."
)

require(
    !addCustomProviderSheet.contains("TextField(localizedString(\"Display Name\"") &&
        addCustomProviderSheet.contains("TextField(\"http://192.168.0.10:8080/v1\"") &&
        addCustomProviderSheet.contains("SecureField(") &&
        addCustomProviderSheet.contains("text: $apiKey") &&
        addCustomProviderSheet.contains("api: \"openai-completions\"") &&
        addCustomProviderSheet.contains("await viewModel.addCustomProvider(baseUrl:") &&
        addCustomProviderSheet.contains("fetchModels: true") &&
        addCustomProviderSheet.contains("let providerKey = await viewModel.addCustomProvider"),
    "Add Custom Provider sheet must support direct freeform local/internal base URLs and optional API keys without a separate display-name field."
)

require(
    customProviderCard.contains("let isExpanded: Bool") &&
        customProviderCard.contains("let onPrimaryTap: () -> Void") &&
        customProviderCard.contains("let onToggleExpansion: () -> Void") &&
        customProviderCard.contains("Image(systemName: isExpanded ? \"chevron.up\" : \"chevron.down\")") &&
        !customProviderCard.contains("rotationEffect") &&
        customProviderCard.contains(".onTapGesture(perform: onPrimaryTap)"),
    "Custom provider cards must separate primary select/toggle behavior from the chevron expansion action."
)

require(
    configProviderLogs.contains("func addCustomProvider(") &&
        !configProviderLogs.contains("displayName: String") &&
        configProviderLogs.contains("baseUrl: String") &&
        configProviderLogs.contains(") async -> String?") &&
        configProviderLogs.contains("guard !trimmedBaseUrl.isEmpty else") &&
        !configProviderLogs.contains("guard !trimmedBaseUrl.isEmpty, !trimmedApiKey.isEmpty else") &&
        configProviderLogs.contains("fetchModels: Bool") &&
        configProviderLogs.contains("makeCustomProviderKey(baseUrl:") &&
        !configProviderLogs.contains("func addCustomProvider(from preset: ProviderPreset"),
    "View model provider logic must add freeform providers without requiring a preset, API key, or display name."
)

print("Custom provider freeform flow verification passed")
