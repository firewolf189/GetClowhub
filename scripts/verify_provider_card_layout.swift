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
        customProviderList.contains("AddCustomProviderSheet(") &&
        customProviderList.contains("CustomProviderCard(") &&
        customProviderList.contains("provider: provider") &&
        customProviderList.contains("ModelConfigSection(viewModel: viewModel)") &&
        customProviderList.contains("if isCurrentProvider(provider)"),
    "Custom providers should render configured providers only, with presets moved behind an Add Provider flow."
)

require(
    customProviderCard.contains("let provider: ConfiguredCustomProvider") &&
        customProviderCard.contains("let isSelected: Bool") &&
        customProviderCard.contains("let isConfigured: Bool") &&
        customProviderCard.contains("let modelCount: Int") &&
        customProviderCard.contains("let onSelect: () -> Void") &&
        customProviderCard.contains("let onDelete: () -> Void"),
    "Custom provider cards should be explicit configured-provider rows with selection and delete actions."
)

require(
    customProviderCard.contains("ProviderStatusBadge(") &&
        customProviderCard.contains("localizedString(\"Selected\")") &&
        customProviderCard.contains("localizedString(\"Configured\")") &&
        customProviderCard.contains("localizedString(\"Needs key\")"),
    "Custom provider cards should show selected/configured/needs-key status based on saved or edited API keys."
)

require(
    customProviderCard.contains(".onTapGesture(perform: onSelect)") &&
        customProviderCard.contains("Button(role: .destructive") &&
        customProviderCard.contains("localizedString(isSelected ? \"Editing\" : \"Use\")") &&
        customProviderCard.contains(".contentShape(Rectangle())"),
    "Custom provider card rows should be full-width selectable without nesting the delete button inside the row action."
)

require(
    modelConfigSection.contains("private var selectedProviderDisplayName: String") &&
        modelConfigSection.contains("Text(selectedProviderDisplayName)") &&
        !modelConfigSection.contains("Picker(\"\", selection: Binding("),
    "Expanded custom provider editor should use the selected card context instead of duplicating a provider picker."
)

require(
    config.contains("struct AddCustomProviderSheet: View") &&
        config.contains("viewModel.addCustomProvider(from: selectedPreset, apiKey: apiKey)") &&
        config.contains("availableProviderPresets") &&
        config.contains("configuredCustomProviders"),
    "Add Provider should be a dedicated preset-selection flow that requires an API key before adding to the configured list."
)

print("Provider card layout verification passed")
