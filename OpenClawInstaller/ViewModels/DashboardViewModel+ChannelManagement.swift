//
//  DashboardViewModel+ChannelManagement.swift
//  Channel management extracted from DashboardViewModel.
//  P1 refactor: file split only, no behavior change.
//

import Foundation

extension DashboardViewModel {

    // MARK: - Channel Management

    /// Available channel types for adding
    static let availableChannelTypes = [
        "telegram", "whatsapp", "discord", "irc", "googlechat", "slack",
        "signal", "imessage", "feishu", "nostr", "msteams", "mattermost",
        "nextcloud-talk", "matrix", "dingtalk", "bluebubbles", "line",
        "zalo", "synology-chat", "tlon", "weixin"
    ]
    private nonisolated static let defaultChannelAccountId = "default"

    /// Load channels by running `openclaw channels status`
    func loadChannels() async {
        isLoadingChannels = true
        let output = await openclawService.runCommand(
            "openclaw channels status 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        channels = Self.parseChannelStatus(output: output)
            .filter { $0.enabled }
            .sorted { a, b in
                let aPriority = a.configured && a.linked ? 0 : a.configured ? 1 : 2
                let bPriority = b.configured && b.linked ? 0 : b.configured ? 1 : 2
                if aPriority != bPriority { return aPriority < bPriority }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        isLoadingChannels = false
    }

    /// Parse `openclaw channels status` output.
    /// Lines like: `- WhatsApp default: enabled, configured, not linked, stopped, disconnected, dm:pairing, error:not linked`
    /// or: `- DingTalk default: enabled, configured`
    /// Stops at "Warnings:" or "Tip:" sections to avoid parsing non-channel lines.
    static func parseChannelStatus(output: String?) -> [ChannelInfo] {
        guard let output = output else { return [] }

        var results: [ChannelInfo] = []

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Stop parsing at non-channel sections
            let lower = trimmed.lowercased()
            if lower.hasPrefix("warnings:") || lower.hasPrefix("tip:") || lower.hasPrefix("docs:") || lower.hasPrefix("usage:") {
                break
            }

            // Match lines starting with "- ChannelName accountId: status1, status2, ..."
            guard trimmed.hasPrefix("- ") else { continue }
            let content = String(trimmed.dropFirst(2))

            // Split at first ":"
            guard let colonIdx = content.firstIndex(of: ":") else { continue }
            let nameAndAccount = content[content.startIndex..<colonIdx]
                .trimmingCharacters(in: .whitespaces)
            let statusPart = content[content.index(after: colonIdx)...]
                .trimmingCharacters(in: .whitespaces)

            // The status part must contain "enabled" or "disabled" to be a channel line
            let statusLower = statusPart.lowercased()
            guard statusLower.contains("enabled") || statusLower.contains("disabled") else { continue }

            // Split name and account: "WhatsApp default" -> name="WhatsApp", account="default"
            let nameParts = nameAndAccount.components(separatedBy: " ")
            let channelName: String
            let account: String
            if nameParts.count >= 2 {
                channelName = nameParts.dropLast().joined(separator: " ")
                account = nameParts.last!
            } else {
                channelName = nameAndAccount
                account = "default"
            }

            // Parse status tags
            let tags = statusPart.components(separatedBy: ",").map {
                $0.trimmingCharacters(in: .whitespaces).lowercased()
            }

            let enabled = tags.contains("enabled")
            let configured = tags.contains("configured")
            let notConfigured = tags.contains("not configured")
            let linked = tags.contains("linked")
            let notLinked = tags.contains("not linked")

            // Extract error message if present
            var errorMsg: String?
            for tag in tags {
                if tag.hasPrefix("error:") {
                    errorMsg = String(tag.dropFirst(6))
                }
            }

            results.append(ChannelInfo(
                name: channelName,
                account: account,
                enabled: enabled,
                configured: configured && !notConfigured,
                linked: notLinked ? false : (linked || configured),
                error: errorMsg,
                statusTags: tags
            ))
        }

        return results
    }

    /// Add a channel with token
    func addChannel(channelType: String, token: String, accountId: String = "default", displayName: String = "") async {
        isPerformingAction = true
        let normalizedAccountId = Self.normalizedChannelAccountId(accountId)
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        var command = "openclaw channels add --channel \(Self.shellQuote(channelType)) --token \(Self.shellQuote(token)) --account \(Self.shellQuote(normalizedAccountId))"
        if !trimmedDisplayName.isEmpty {
            command += " --name \(Self.shellQuote(trimmedDisplayName))"
        }
        command += " 2>&1"
        let output = await openclawService.runCommand(
            command
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage(I18n.format("dashboard.channels.toast.addFailed", channelType, normalizedAccountId, output))
        } else {
            showSuccessMessage(I18n.format("dashboard.channels.toast.added", channelType, normalizedAccountId))
        }
        await loadChannels()
        isPerformingAction = false
    }

    func addChannel(
        channelType: String,
        appKey: String,
        appSecret: String,
        accountId: String = "default",
        displayName: String = ""
    ) async {
        isPerformingAction = true
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(homeDir)/.openclaw/openclaw.json"
        let fm = FileManager.default
        let normalizedAccountId = Self.normalizedChannelAccountId(accountId)
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            guard let data = fm.contents(atPath: configPath),
                  var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                showErrorMessage(I18n.t("dashboard.channels.toast.readConfigFailed"))
                isPerformingAction = false
                return
            }

            var channels = root["channels"] as? [String: Any] ?? [:]
            var channelConfig: [String: Any]
            if channelType == "feishu" {
                channelConfig = [
                    "connectionMode": "websocket",
                    "appId": appKey,
                    "appSecret": appSecret,
                    "dmPolicy": "open",
                    "enabled": true,
                    "groupPolicy": "open",
                    "requireMention": false
                ]
            } else {
                channelConfig = [
                    "allowFrom": ["*"],
                    "clientId": appKey,
                    "clientSecret": appSecret,
                    "dmPolicy": "open",
                    "enableAICard": false,
                    "enabled": true,
                    "groupPolicy": "open",
                    "requireMention": true
                ]
            }
            if !trimmedDisplayName.isEmpty {
                channelConfig["name"] = trimmedDisplayName
            }

            let channelRoot = channels[channelType] as? [String: Any] ?? [:]
            if normalizedAccountId == Self.defaultChannelAccountId {
                var mergedConfig = channelRoot
                let existingAccounts = channelRoot["accounts"]
                for (key, value) in channelConfig {
                    mergedConfig[key] = value
                }
                if let existingAccounts {
                    mergedConfig["accounts"] = existingAccounts
                }
                channels[channelType] = mergedConfig
            } else {
                let defaultSeed = Self.channelDefaultConfig(from: channelRoot)
                var accounts = channelRoot["accounts"] as? [String: Any] ?? [:]
                accounts[normalizedAccountId] = channelConfig
                var mergedRoot = defaultSeed
                mergedRoot["enabled"] = true
                mergedRoot["accounts"] = accounts
                channels[channelType] = mergedRoot
            }
            root["channels"] = channels

            let updatedData = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            try updatedData.write(to: URL(fileURLWithPath: configPath))
            showSuccessMessage(I18n.format("dashboard.channels.toast.added", channelType, normalizedAccountId))
        } catch {
            showErrorMessage(I18n.format("dashboard.channels.toast.addFailed", channelType, normalizedAccountId, error.localizedDescription))
        }

        await loadChannels()
        isPerformingAction = false
    }

    /// Remove a channel
    func removeChannel(_ channel: ChannelInfo) async {
        isPerformingAction = true
        let channelType = channel.name.lowercased()
        let output = await openclawService.runCommand(
            "openclaw channels remove --channel \(Self.shellQuote(channelType)) --account \(Self.shellQuote(channel.account)) --delete 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage(I18n.format("dashboard.channels.toast.removeFailed", channel.name, output))
        } else {
            // Also disable the channel so it won't reappear in status list
            disableChannelInConfig(channelType, accountId: channel.account)
            showSuccessMessage(I18n.format("dashboard.channels.toast.removed", channel.name))
        }
        await loadChannels()
        isPerformingAction = false
    }

    /// Set enabled=false for a channel in openclaw.json
    private func disableChannelInConfig(_ channelType: String, accountId: String) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(homeDir)/.openclaw/openclaw.json"
        let fm = FileManager.default
        guard let data = fm.contents(atPath: configPath),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        var channels = root["channels"] as? [String: Any] ?? [:]
        var chConfig = channels[channelType] as? [String: Any] ?? [:]
        if accountId == Self.defaultChannelAccountId {
            chConfig["enabled"] = false
        } else {
            var accounts = chConfig["accounts"] as? [String: Any] ?? [:]
            var accountConfig = accounts[accountId] as? [String: Any] ?? [:]
            accountConfig["enabled"] = false
            accounts[accountId] = accountConfig
            chConfig["accounts"] = accounts
        }
        channels[channelType] = chConfig
        root["channels"] = channels
        if let updatedData = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? updatedData.write(to: URL(fileURLWithPath: configPath))
        }
    }

    private nonisolated static func normalizedChannelAccountId(_ accountId: String) -> String {
        let trimmed = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultChannelAccountId : trimmed
    }

    private nonisolated static func channelDefaultConfig(from channelRoot: [String: Any]) -> [String: Any] {
        var defaultConfig = channelRoot
        defaultConfig.removeValue(forKey: "accounts")
        return defaultConfig
    }

}
