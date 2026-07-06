#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let pluginsViewPath = root.appendingPathComponent("OpenClawInstaller/Features/Plugins/Views/PluginsTabView.swift")
let pluginsView = try String(contentsOf: pluginsViewPath, encoding: .utf8)
let i18nServicePath = root.appendingPathComponent("OpenClawInstaller/Localization/I18nService.swift")
let i18nService = try String(contentsOf: i18nServicePath, encoding: .utf8)

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
    installedRow.contains("I18n.installedPluginDisplay(for: plugin, catalogItem: catalogItem)") &&
        installedRow.contains("display.displayName") &&
        installedRow.contains("display.description"),
    "Installed plugin rows should render unified localized fallback names and descriptions instead of raw ids."
)
require(
    !installedRow.contains("?? plugin.pluginId"),
    "Installed plugin rows should not show pluginId as the description fallback."
)
require(
    presentationItem.contains("I18n.installedPluginDisplay(for: plugin, catalogItem: catalogItem)") &&
        presentationItem.contains("display.description") &&
        presentationItem.contains("display.longDescription"),
    "Installed plugin detail should use unified localized fallback documentation when catalog metadata is missing."
)
require(
    !presentationItem.contains("**Source:**"),
    "Installed plugin detail fallback should not expose the raw Source field."
)
require(
    i18nService.contains("case provider") &&
        i18nService.contains("case browser") &&
        i18nService.contains("case speech") &&
        i18nService.contains("case memory") &&
        i18nService.contains("case proxy"),
    "Unified I18n fallback display should classify common built-in plugin families."
)
require(
    i18nService.contains("installedPluginBaseNameCandidate") &&
        i18nService.contains("looksLikeRawPluginIdentifier") &&
        i18nService.contains("plugin.channel.contains(\"/\")") &&
        i18nService.contains("normalized.hasPrefix(\"@\")"),
    "Installed plugin fallback should sanitize scoped package names such as @openclaw/ollama-provider."
)
require(
    i18nService.contains("case \"openai\": return \"OpenAI\"") &&
        i18nService.contains("case \"tts\": return \"TTS\"") &&
        i18nService.contains("case \"sglang\": return \"SGLang\""),
    "Installed plugin fallback should humanize common provider and CLI acronyms."
)
require(
    fallbackDisplay.contains("I18n.installedPluginDisplay(for: plugin, catalogItem: nil)") &&
        !fallbackDisplay.contains("Model provider") &&
        !fallbackDisplay.contains("Browser automation") &&
        !fallbackDisplay.contains("Speech capability") &&
        !fallbackDisplay.contains("Memory storage"),
    "Fallback display should delegate user-facing descriptions to unified I18n resources."
)

print("Installed plugin fallback display verification passed")
