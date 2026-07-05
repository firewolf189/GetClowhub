#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let pluginsPath = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/Plugins/PluginsTabView.swift")
let channelsPath = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/ChannelsTabView.swift")
let plugins = try String(contentsOf: pluginsPath, encoding: .utf8)
let channels = try String(contentsOf: channelsPath, encoding: .utf8)

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

let channelMatcher = slice(
    channels,
    from: "private static func pluginMatchesChannel",
    to: "private static func normalizedPluginLookupText"
)
let addChannelAliases = slice(
    channels,
    from: "private var expectedPluginAliases",
    to: "/// Check if the plugin for the selected channel is installed"
)
let presetMatcher = slice(
    plugins,
    from: "private var isPresetAlreadyInstalled",
    to: "private var canInstall"
)
let presetKeywords = slice(
    plugins,
    from: "var matchKeywords: [String]",
    to: "struct InstallPluginSheet"
)

require(
    !channelMatcher.contains("plugin.source"),
    "Add Channel plugin matching must not inspect plugin.source."
)
require(
    !presetMatcher.contains("plugin.source") &&
        !presetMatcher.contains("source.contains"),
    "Install preset matching must not inspect plugin.source."
)
require(
    addChannelAliases.contains("case \"dingtalk\": return [\"dingtalk\"]") &&
        addChannelAliases.contains("case \"weixin\": return [\"weixin\", \"openclaw-weixin\"]"),
    "Channel aliases should use normalized plugin/channel ids, not scoped source package strings."
)
require(
    presetKeywords.contains("case .dingtalk: return [\"dingtalk\"]") &&
        presetKeywords.contains("case .weixin: return [\"weixin\", \"openclaw-weixin\"]"),
    "Preset matching keywords should use normalized plugin/channel ids, not scoped source package strings."
)
require(
    !addChannelAliases.contains("@openclaw-china/") &&
        !addChannelAliases.contains("@tencent-weixin/") &&
        !presetKeywords.contains("@openclaw-china/") &&
        !presetKeywords.contains("@tencent-weixin/"),
    "Plugin matching aliases must not retain scoped package prefixes."
)

print("Plugin matching ignores source verification passed")
