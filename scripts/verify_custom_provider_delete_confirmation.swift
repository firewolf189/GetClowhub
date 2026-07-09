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

let customProviderList = slice(
    config,
    from: "struct CustomProviderListSection: View",
    to: "private struct AddCustomProviderSheet: View"
)
let customProviderCard = slice(
    config,
    from: "private struct CustomProviderCard: View",
    to: "private struct EmptyCustomProvidersView"
)

require(
    customProviderList.contains("@State private var pendingDeleteProviderKey: String?") &&
        customProviderList.contains("isDeleteArmed: pendingDeleteProviderKey == provider.key") &&
        customProviderList.contains("confirmOrArmProviderDelete(provider)") &&
        customProviderList.contains("pendingDeleteProviderKey = provider.key") &&
        customProviderList.contains("await viewModel.deleteCustomProviderAndPersist(provider)") &&
        customProviderList.contains("pendingDeleteProviderKey = nil"),
    "Custom provider delete should be a row-scoped two-click confirmation before mutating provider state."
)

require(
    customProviderList.contains("clearPendingProviderDelete()") &&
        customProviderList.contains("activateProviderCard(_ provider: ConfiguredCustomProvider)") &&
        customProviderList.contains("toggleProviderExpansion(_ provider: ConfiguredCustomProvider)") &&
        customProviderList.contains("isShowingAddProviderSheet = true"),
    "Provider selection, expansion, and add actions should clear stale delete confirmation."
)

require(
    customProviderCard.contains("let isDeleteArmed: Bool") &&
        customProviderCard.contains("let onDeleteTap: () -> Void") &&
        customProviderCard.contains("onDeleteTap()") &&
        customProviderCard.contains("isDeleteArmed ? \"trash.fill\" : \"trash\"") &&
        customProviderCard.contains("isDeleteArmed ? Color.red : Color.secondary") &&
        customProviderCard.contains("Color.red.opacity(isDeleteArmed ? 0.14 : 0)") &&
        customProviderCard.contains("settings.provider.custom.confirmDelete") &&
        !customProviderCard.contains("Button(role: .destructive"),
    "Custom provider card delete button should turn red after the first click and delete only on the second click."
)

print("Custom provider delete confirmation verification passed")
