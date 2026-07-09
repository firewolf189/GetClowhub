#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let configURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Features")
    .appendingPathComponent("Settings")
    .appendingPathComponent("Views")
    .appendingPathComponent("ConfigTabView.swift")

let config = try String(contentsOf: configURL, encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fputs("FAIL: could not slice source between \(start) and \(end)\n", stderr)
        exit(1)
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let providerSettingsContent = slice(
    config,
    from: "case .provider:\n            settingsScroll {",
    to: "case .budget:"
)
let customProviderList = slice(
    config,
    from: "struct CustomProviderListSection: View",
    to: "// MARK: - Custom API Provider"
)
let customProviderCard = slice(
    config,
    from: "private struct CustomProviderCard: View",
    to: "// MARK: - Custom API Provider"
)
let modelConfigSection = slice(
    config,
    from: "struct ModelConfigSection: View",
    to: "// MARK: - Save Buttons"
)
let customProviderDetails = slice(
    config,
    from: "private struct CustomProviderDetailsSection: View",
    to: "private struct AddProviderModelSheet: View"
)
let addCustomProviderSheet = slice(
    config,
    from: "private struct AddCustomProviderSheet: View",
    to: "private struct CustomProviderCard: View"
)

require(
    providerSettingsContent.contains("ProviderSettingsIntro()") &&
        providerSettingsContent.contains("GetClawHubServiceSection(viewModel: viewModel)") &&
        providerSettingsContent.contains("CustomProviderListSection(viewModel: viewModel)") &&
        !providerSettingsContent.contains("HStack(alignment: .top, spacing: 16)"),
    "Provider settings should use a vertical provider card list instead of the old two-column layout."
)

require(
    customProviderList.contains("ForEach(viewModel.configuredCustomProviders)") &&
        !customProviderList.contains("ForEach(viewModel.availableProviders)") &&
        customProviderList.contains("Button") &&
        customProviderList.contains("isShowingAddProviderSheet = true") &&
        customProviderList.contains("AddCustomProviderSheet(") &&
        !customProviderList.contains("AddCustomProviderCard(viewModel: viewModel)") &&
        customProviderList.contains("@State private var expandedProviderKey: String?") &&
        customProviderList.contains("CustomProviderCard(") &&
        customProviderList.contains("provider: provider") &&
        customProviderList.contains("SettingsCollapsibleContent(") &&
        customProviderList.contains("CustomProviderDetailsSection(viewModel: viewModel, provider: provider)") &&
        customProviderList.contains("isHighlighted: expandedProviderKey == provider.key") &&
        customProviderList.contains("isExpanded: expandedProviderKey == provider.key") &&
        !customProviderList.contains("ModelConfigSection(viewModel: viewModel)") &&
        !customProviderList.contains("isCurrentProvider(provider)"),
    "Custom providers should render configured providers only, with freeform add and one local expansion/highlight state."
)

require(
    customProviderCard.contains("let provider: ConfiguredCustomProvider") &&
        customProviderCard.contains("let isHighlighted: Bool") &&
        customProviderCard.contains("let isExpanded: Bool") &&
        customProviderCard.contains("let isDeleteArmed: Bool") &&
        customProviderCard.contains("let isConfigured: Bool") &&
        customProviderCard.contains("let modelCount: Int") &&
        customProviderCard.contains("let onPrimaryTap: () -> Void") &&
        customProviderCard.contains("let onToggleExpansion: () -> Void") &&
        customProviderCard.contains("let onDeleteTap: () -> Void"),
    "Custom provider cards should be explicit configured-provider rows with separated highlight, expansion, and delete actions."
)

require(
    customProviderCard.contains("ProviderStatusBadge(") &&
        customProviderCard.contains("localizedString(\"Configured\")") &&
        customProviderCard.contains("settings.provider.custom.needsSetup") &&
        customProviderCard.contains("return .warning") &&
        !customProviderCard.contains("localizedString(\"Selected\")"),
    "Custom provider cards should show setup status without duplicating selected state as text."
)

require(
    customProviderCard.contains(".onTapGesture(perform: onPrimaryTap)") &&
        !customProviderCard.contains("Button(role: .destructive") &&
        customProviderCard.contains("onDeleteTap()") &&
        customProviderCard.contains("onToggleExpansion()") &&
        customProviderCard.contains("Image(systemName: isExpanded ? \"chevron.up\" : \"chevron.down\")") &&
        !customProviderCard.contains("rotationEffect") &&
        !customProviderCard.contains("localizedString(isSelected ? \"Editing\" : \"Use\")") &&
        customProviderCard.contains(".contentShape(Rectangle())"),
    "Custom provider card rows should be full-width selectable while keeping chevron expansion and delete as explicit actions."
)

require(
        customProviderDetails.contains("private var providerDisplayName: String") &&
        customProviderDetails.contains("Text(providerDisplayName)") &&
        customProviderDetails.contains("@State private var draftBaseUrl") &&
        customProviderDetails.contains("@State private var draftApiKey") &&
        customProviderDetails.contains("@State private var draftModels") &&
        customProviderDetails.contains("@State private var isShowingAddModelSheet = false") &&
        customProviderDetails.contains("Add Model") &&
        customProviderDetails.contains("updateCustomProviderAndPersist(") &&
        customProviderDetails.contains("fetchModelsForCustomProvider(") &&
        !customProviderDetails.contains("Picker(\"\", selection: Binding(") &&
        modelConfigSection.contains("fetchModelsForSelectedProvider"),
    "Expanded custom provider editor should use card-local draft state, while legacy gateway model config remains separate."
)

require(
    config.contains("private struct AddCustomProviderSheet: View") &&
        !addCustomProviderSheet.contains("TextField(localizedString(\"Display Name\"") &&
        addCustomProviderSheet.contains("TextField(\"http://192.168.0.10:8080/v1\"") &&
        addCustomProviderSheet.contains("await viewModel.addCustomProvider(baseUrl:") &&
        addCustomProviderSheet.contains("fetchModels: true") &&
        !config.contains("private struct AddCustomProviderCard: View"),
    "Add Provider should be a dialog-based freeform flow for local/internal OpenAI-compatible providers without a display-name field."
)

let officialServiceSection = slice(
    config,
    from: "struct GetClawHubServiceSection: View",
    to: "// MARK: - Logged In Content"
)
let officialLoggedInContent = slice(
    config,
    from: "private func loggedInContent",
    to: "private var availableModelsView"
)

require(
    officialServiceSection.contains("@State private var isExpanded = false") &&
        officialServiceSection.contains("toggleOfficialProviderExpansion()") &&
        officialServiceSection.contains("let shouldCollapse = isSelected && isExpanded") &&
        officialServiceSection.contains("isExpanded = !shouldCollapse") &&
        !officialServiceSection.contains("localizedString(\"Selected\")") &&
        !officialServiceSection.contains("localizedString(isSelected ? \"Editing\" : \"Use\")"),
    "Official provider card should default collapsed, toggle closed on a second click, and avoid duplicate Selected/Editing right-side controls."
)

require(
    !officialLoggedInContent.contains("Text(localizedString(\"Budget\"))") &&
        !officialLoggedInContent.contains("membership.maxBudget") &&
        !officialLoggedInContent.contains("membership.rpmLimit"),
    "Official provider editor should not duplicate budget details from Billing/Budget settings."
)

print("Provider card layout verification passed")
