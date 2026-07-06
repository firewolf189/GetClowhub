#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

let channelsView = try read("OpenClawInstaller/Features/Channels/Views/ChannelsTabView.swift")
let pluginViewModel = try read("OpenClawInstaller/Features/Plugins/ViewModels/PluginListViewModel.swift")
let pluginFacade = try read("OpenClawInstaller/Features/Plugins/PluginManagement.swift")
let pluginParser = try read("OpenClawInstaller/Features/Plugins/Services/PluginListParser.swift")
let pluginInfo = try read("OpenClawInstaller/Features/Plugins/Models/PluginInfo.swift")

require(
    pluginInfo.contains("var channelIds: [String] = []"),
    "PluginInfo should carry OpenClaw channelIds from structured plugin metadata."
)
require(
    pluginParser.contains("parseJSON(output: output)") &&
        pluginParser.contains("let channelIds: [String]?") &&
        pluginParser.contains("channelIds: plugin.channelIds ?? []"),
    "PluginListParser should parse structured JSON plugin output and preserve channelIds."
)
require(
    pluginViewModel.contains("openclaw plugins list --json"),
    "Plugin loading should prefer structured OpenClaw JSON output."
)
require(
    pluginViewModel.contains("func installPluginAndReturnSuccess") &&
        pluginFacade.contains("func installPluginAndReturnSuccess"),
    "Channel setup should have a reusable install path that reports success."
)
require(
    channelsView.contains("case \"dingtalk\": return \"@openclaw-china/dingtalk\""),
    "DingTalk channel setup should know the npm package needed to install its plugin."
)
require(
    channelsView.contains("missingPluginPrompt") &&
        channelsView.contains("installRequiredPlugin()"),
    "Add Channel sheet should provide an install action when a required plugin is missing."
)
require(
    channelsView.contains("([plugin.pluginId, plugin.channel] + plugin.channelIds)") ||
        channelsView.contains("[plugin.pluginId, plugin.channel] + plugin.channelIds"),
    "Channel plugin matching should include plugin.channelIds, not only display name and id."
)
require(
    channelsView.contains("ShimmeringStatusText("),
    "Required plugin install progress should use the shared shimmer status component."
)

print("Channel required plugin install flow verification passed")
