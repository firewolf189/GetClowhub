#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fputs("FAIL: could not read \(path)\n", stderr)
        exit(1)
    }
    return text
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
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

let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")
let config = read("OpenClawInstaller/Features/Settings/Views/ConfigTabView.swift")
let collapsible = read("OpenClawInstaller/Features/Settings/Views/SettingsCollapsibleContent.swift")

let customProviderList = slice(
    config,
    from: "struct CustomProviderListSection: View",
    to: "private struct AddCustomProviderSheet: View"
)
let customProviderDetails = slice(
    config,
    from: "private struct CustomProviderDetailsSection: View",
    to: "private struct AddProviderModelSheet"
)

require(
    project.contains("SettingsCollapsibleContent.swift in Sources"),
    "Settings collapsible content should live in the Settings module and be compiled as a reusable component."
)
require(
    collapsible.contains("struct SettingsCollapsibleContent<Content: View>: View") &&
        collapsible.contains("private static var expansionAnimation: Animation") &&
        collapsible.contains(".asymmetric(insertion: .opacity, removal: .identity)") &&
        collapsible.contains(".transition(Self.contentTransition)") &&
        collapsible.contains(".clipped()"),
    "SettingsCollapsibleContent should own clipped expansion with identity removal to avoid collapse ghosting."
)
require(
    !config.contains(".transition(.opacity.combined(with: .move(edge: .top)))") &&
        !config.contains(".transition(.move(edge: .top).combined(with: .opacity))"),
    "Settings provider collapse must not use moving removal transitions that leave ghosted content."
)
require(
    customProviderList.contains("SettingsCollapsibleContent(") &&
        customProviderList.contains("isExpanded: expandedProviderKey == provider.key") &&
        customProviderList.contains("CustomProviderDetailsSection(viewModel: viewModel, provider: provider)") &&
        !customProviderList.contains("isCurrentProvider(provider)") &&
        !customProviderList.contains("ModelConfigSection(viewModel: viewModel)"),
    "Custom provider editor should collapse through SettingsCollapsibleContent instead of inline transition blocks."
)
require(
    customProviderDetails.contains("SettingsCollapsibleContent(isExpanded: areModelsExpanded)") &&
        customProviderDetails.contains("LazyVStack(alignment: .leading, spacing: 6)"),
    "Custom provider model lists should share the Settings collapsible container."
)

print("Settings collapse no-ghosting verification passed")
