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

func slice(_ source: String, from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        FileHandle.standardError.write(Data("FAIL: could not slice source from \(start) to \(end)\n".utf8))
        exit(1)
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

let channelsView = try read("OpenClawInstaller/Features/Channels/Views/ChannelsTabView.swift")
let dashboardVM = try read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")
let channelManagement = try read("OpenClawInstaller/Features/Channels/Core/ChannelManagement.swift")

let addChannelSheet = slice(
    channelsView,
    from: "struct AddChannelSheet: View",
    to: "#Preview"
)
let appKeyAdd = slice(
    channelManagement,
    from: "func addChannel(\n        channelType: String,\n        appKey: String,\n        appSecret: String",
    to: "/// Remove a channel"
)
let removeChannel = slice(
    channelManagement,
    from: "func removeChannel(_ channel: ChannelInfo) async",
    to: "/// Set enabled=false"
)
let disableChannel = slice(
    channelManagement,
    from: "private func disableChannelInConfig",
    to: "private nonisolated static func normalizedChannelAccountId"
)

require(
    addChannelSheet.contains("@State private var accountId") &&
        addChannelSheet.contains("@State private var displayName"),
    "AddChannelSheet should collect account id and display name."
)
require(
    addChannelSheet.contains("dashboard.channels.sheet.accountId") &&
        addChannelSheet.contains("dashboard.channels.sheet.displayName") &&
        addChannelSheet.contains("dashboard.channels.sheet.accountHelp") &&
        addChannelSheet.contains("default"),
    "AddChannelSheet should expose localized account id/display name fields and explain the default account."
)
require(
    addChannelSheet.contains("accountId: accountId") &&
        addChannelSheet.contains("displayName: displayName"),
    "AddChannelSheet should pass account id and display name into addChannel."
)
require(
    channelManagement.contains("private nonisolated static let defaultChannelAccountId = \"default\""),
    "DashboardViewModel should centralize the default channel account id."
)
require(
    appKeyAdd.contains("accountId: String") &&
        appKeyAdd.contains("displayName: String"),
    "App-key channel add should accept account id and display name."
)
require(
    appKeyAdd.contains("\"accounts\"") &&
        appKeyAdd.contains("accounts[normalizedAccountId]") &&
        appKeyAdd.contains("normalizedAccountId == Self.defaultChannelAccountId"),
    "App-key channel add should write non-default accounts under channel.accounts without replacing the whole channel."
)
require(
    !appKeyAdd.contains("channels[channelType] = channelConfig\n"),
    "App-key channel add should not overwrite the entire channel by channel type."
)
require(
    removeChannel.contains("disableChannelInConfig(channelType, accountId: channel.account)"),
    "Remove channel should disable the selected account, not just the channel type."
)
require(
    disableChannel.contains("accountId: String") &&
        disableChannel.contains("accounts[accountId]") &&
        disableChannel.contains("channels[channelType] = chConfig"),
    "disableChannelInConfig should handle account-specific channel entries."
)

print("DingTalk multi-account channel verification passed")
