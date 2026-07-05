#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let channelsPath = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/ChannelsTabView.swift")
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

let addChannelSheet = slice(
    channels,
    from: "struct AddChannelSheet: View",
    to: "#Preview"
)

require(
    addChannelSheet.contains("private var expectedPluginAliases: [String]"),
    "AddChannelSheet should map each channel to all known plugin aliases."
)
require(
    addChannelSheet.contains("case \"dingtalk\": return [\"dingtalk\"]"),
    "DingTalk should only match the normalized channel/plugin id."
)
require(
    !addChannelSheet.contains("@openclaw-china/dingtalk"),
    "DingTalk detection should not depend on the scoped npm package alias."
)
require(
    addChannelSheet.contains("case \"weixin\": return [\"weixin\", \"openclaw-weixin\"]"),
    "Weixin should match normalized channel/plugin ids without source package aliases."
)
require(
    !addChannelSheet.contains("@tencent-weixin/openclaw-weixin"),
    "Weixin detection should not depend on the scoped npm package alias."
)
require(
    addChannelSheet.contains("private static func pluginMatchesChannel"),
    "Channel plugin detection should use a shared field matcher."
)
require(
    addChannelSheet.contains("plugin.pluginId") &&
        addChannelSheet.contains("plugin.channel"),
    "Channel plugin detection should inspect plugin id and display/channel name."
)
require(
    !addChannelSheet.contains("plugin.source"),
    "Channel plugin detection should not inspect plugin source."
)
require(
    !addChannelSheet.contains("plugin.pluginId.lowercased() == target"),
    "Channel plugin detection must not rely on pluginId exact equality only."
)
require(
    addChannelSheet.contains(".task {\n            await viewModel.loadPlugins()\n            pluginsLoaded = true\n        }"),
    "AddChannelSheet should refresh installed plugins whenever it opens instead of trusting a stale non-empty cache."
)

print("Channel plugin alias matching verification passed")
