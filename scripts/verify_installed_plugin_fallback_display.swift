#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let pluginsViewPath = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/Plugins/PluginsTabView.swift")
let pluginsView = try String(contentsOf: pluginsViewPath, encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(_ source: String, from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source[startRange.upperBound...].range(of: end) else {
        fputs("FAIL: could not slice source between \(start) and \(end)\n", stderr)
        exit(1)
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

let presentationItem = slice(
    pluginsView,
    from: "struct PluginDetailPresentationItem: Identifiable",
    to: "struct PluginsTabView: View"
)
let installedRow = slice(
    pluginsView,
    from: "private struct InstalledPluginListRow: View",
    to: "private struct PluginStatusMark: View"
)
let fallbackDisplay = slice(
    pluginsView,
    from: "private struct InstalledPluginFallbackDisplay",
    to: "private struct PluginStatusMark: View"
)

require(
    pluginsView.contains("private struct InstalledPluginFallbackDisplay"),
    "Installed plugins without catalog metadata should use a dedicated readable fallback display model."
)
require(
    installedRow.contains("InstalledPluginFallbackDisplay(plugin: plugin)") &&
        installedRow.contains("fallback.displayName") &&
        installedRow.contains("fallback.description"),
    "Installed plugin rows should render readable fallback names and descriptions instead of raw ids."
)
require(
    !installedRow.contains("?? plugin.pluginId"),
    "Installed plugin rows should not show pluginId as the description fallback."
)
require(
    presentationItem.contains("InstalledPluginFallbackDisplay(plugin: plugin)") &&
        presentationItem.contains("fallback.description") &&
        presentationItem.contains("fallback.documentationMarkdown"),
    "Installed plugin detail should use readable fallback documentation when catalog metadata is missing."
)
require(
    !presentationItem.contains("**Source:**"),
    "Installed plugin detail fallback should not expose the raw Source field."
)
require(
    fallbackDisplay.contains(".provider") &&
        fallbackDisplay.contains(".browser") &&
        fallbackDisplay.contains(".speech") &&
        fallbackDisplay.contains(".memory") &&
        fallbackDisplay.contains(".proxy"),
    "Fallback display should classify common built-in plugin families."
)
require(
    fallbackDisplay.contains("Model provider") &&
        fallbackDisplay.contains("Browser automation") &&
        fallbackDisplay.contains("Speech capability") &&
        fallbackDisplay.contains("Memory storage"),
    "Fallback display should include user-facing descriptions for common built-in plugin families."
)

print("Installed plugin fallback display verification passed")
