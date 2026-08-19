import Foundation

/// DingTalk account payload that current OpenClaw plugin schemas accept.
/// Root-level `enableAICard`, `requireMention`, and `robotCode` fail
/// `config validate` (`additional properties`) and make `channels status`
/// print no channel rows, so the Channels tab looks empty after add.
enum DingTalkChannelConfig {
    static let channelIds = ["dingtalk", "dingtalk-connector"]
    static let rejectedAccountKeys = ["enableAICard", "requireMention", "robotCode"]

    static func defaultAccountConfig(
        clientId: String,
        clientSecret: String,
        displayName: String = ""
    ) -> [String: Any] {
        var config: [String: Any] = [
            "allowFrom": ["*"],
            "clientId": clientId,
            "clientSecret": clientSecret,
            "dmPolicy": "open",
            "enabled": true,
            "groupPolicy": "open",
            "messageType": "markdown"
        ]
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            config["name"] = name
        }
        return config
    }

    static func isDingTalkChannel(_ channelType: String) -> Bool {
        channelIds.contains(channelType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    @discardableResult
    static func stripRejectedKeys(from root: inout [String: Any]) -> Bool {
        guard var channels = root["channels"] as? [String: Any] else { return false }
        var changed = false
        for id in channelIds {
            guard var channel = channels[id] as? [String: Any] else { continue }
            if stripRejectedKeys(inChannel: &channel) {
                channels[id] = channel
                changed = true
            }
        }
        if changed {
            root["channels"] = channels
        }
        return changed
    }

    @discardableResult
    static func stripRejectedKeys(inChannel channel: inout [String: Any]) -> Bool {
        var changed = stripRejectedAccountKeys(from: &channel)
        if var accounts = channel["accounts"] as? [String: Any] {
            var accountsChanged = false
            for (accountId, value) in accounts {
                guard var account = value as? [String: Any] else { continue }
                if stripRejectedAccountKeys(from: &account) {
                    accounts[accountId] = account
                    accountsChanged = true
                }
            }
            if accountsChanged {
                channel["accounts"] = accounts
                changed = true
            }
        }
        return changed
    }

    @discardableResult
    static func stripRejectedAccountKeys(from config: inout [String: Any]) -> Bool {
        var changed = false
        for key in rejectedAccountKeys where config.removeValue(forKey: key) != nil {
            changed = true
        }
        return changed
    }

    static func statusLoadError(from output: String?) -> String? {
        guard let output, !output.isEmpty else { return nil }
        let lower = output.lowercased()
        guard lower.contains("config is invalid")
            || lower.contains("must not have additional properties") else {
            return nil
        }
        var fallback: String?
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let compact = trimmed.replacingOccurrences(of: "│", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let compactLower = compact.lowercased()
            let useful = compact.hasPrefix("- ") ? String(compact.dropFirst(2)) : compact
            if compactLower.contains("must not have additional properties")
                || compactLower.contains("invalid config for plugin") {
                return useful
            }
            if fallback == nil, compactLower.contains("channels.dingtalk")
                || compactLower.contains("openclaw config is invalid") {
                fallback = useful
            }
        }
        return fallback ?? "OpenClaw config is invalid"
    }
}
