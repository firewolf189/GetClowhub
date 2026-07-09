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
let shell = read("OpenClawInstaller/Features/Settings/Views/SettingsShellView.swift")
let localization = read("OpenClawInstaller/Localization/Resources/Localizable.xcstrings")

let settingsSectionEnum = slice(
    config,
    from: "enum SettingsPageSection",
    to: "struct ConfigTabView"
)
let selectedContent = slice(
    config,
    from: "private var selectedSettingsContent",
    to: "private func settingsScroll"
)
let sidebarGroups = slice(
    shell,
    from: "private let groups",
    to: "private var filteredGroups"
)

require(
    !settingsSectionEnum.contains("case apiKey") &&
        !selectedContent.contains("case .apiKey") &&
        !sidebarGroups.contains(".apiKey"),
    "Settings should not expose API Key as a separate page; credentials belong in Providers."
)

require(
    settingsSectionEnum.contains("case .provider: return \"Providers\"") &&
        sidebarGroups.contains("(\"settings.group.configuration\", [.gateway, .provider, .budget])"),
    "Provider settings should be presented as Providers in the page title and sidebar."
)

let providersLocalization = slice(
    localization,
    from: "\"Providers\" : {",
    to: "\"Quick Select\" : {"
)
require(
    providersLocalization.contains("\"zh-Hans\"") &&
        providersLocalization.contains("\"value\" : \"服务提供商\"") &&
        providersLocalization.contains("\"zh-Hant\"") &&
        providersLocalization.contains("\"value\" : \"服務供應商\""),
    "Providers must be localized so Chinese Settings sidebar does not fall back to English."
)

require(
    settingsSectionEnum.contains("case .preferences: return \"paintbrush.pointed\"") &&
        config.contains("SettingsCard(title: localizedString(\"Preferences\"), systemImage: \"paintbrush.pointed\")"),
    "Preferences should use a visual preferences icon instead of the generic slider icon."
)

require(
    selectedContent.contains("ProviderSettingsIntro()") &&
        selectedContent.contains("GetClawHubServiceSection(viewModel: viewModel)") &&
        selectedContent.contains("CustomProviderListSection(viewModel: viewModel)") &&
        !selectedContent.contains("HStack(alignment: .top, spacing: 16)"),
    "Providers page should be the single vertical provider-management surface."
)

print("Provider settings consolidation verification passed")
