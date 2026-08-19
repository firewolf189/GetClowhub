import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case assertion(String)
    var description: String {
        switch self {
        case .assertion(let message): message
        }
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure.assertion(message) }
}

@main
private enum DingTalkChannelConfigTests {
    static func main() throws {
        try testDefaultAccountOmitsRejectedKeys()
        try testStripRejectedKeysFromRootAndAccounts()
        try testStatusLoadErrorDetectsInvalidConfig()
        print("PASS: DingTalk channel config")
    }

    private static func testDefaultAccountOmitsRejectedKeys() throws {
        let config = DingTalkChannelConfig.defaultAccountConfig(
            clientId: "app-key",
            clientSecret: "app-secret",
            displayName: "Sales"
        )
        try expect(config["enableAICard"] == nil, "new DingTalk accounts must not write enableAICard")
        try expect(config["requireMention"] == nil, "new DingTalk accounts must not write root requireMention")
        try expect(config["robotCode"] == nil, "new DingTalk accounts must not write robotCode")
        try expect(config["clientId"] as? String == "app-key", "clientId should be preserved")
        try expect(config["clientSecret"] as? String == "app-secret", "clientSecret should be preserved")
        try expect(config["dmPolicy"] as? String == "open", "dmPolicy default is open")
        try expect(config["groupPolicy"] as? String == "open", "groupPolicy default is open")
        try expect(config["messageType"] as? String == "markdown", "messageType default is markdown")
        try expect(config["name"] as? String == "Sales", "display name should be stored as name")
        try expect(config["enabled"] as? Bool == true, "new accounts start enabled")
    }

    private static func testStripRejectedKeysFromRootAndAccounts() throws {
        var root: [String: Any] = [
            "channels": [
                "dingtalk": [
                    "clientId": "keep-me",
                    "enableAICard": false,
                    "requireMention": true,
                    "robotCode": "abc",
                    "accounts": [
                        "sales": [
                            "clientId": "sales-id",
                            "enableAICard": true,
                            "groups": ["*": ["requireMention": true]]
                        ]
                    ]
                ],
                "feishu": [
                    "requireMention": false
                ]
            ]
        ]
        try expect(DingTalkChannelConfig.stripRejectedKeys(from: &root), "should report a change")
        let dingtalk = root["channels"].flatMap { $0 as? [String: Any] }?["dingtalk"] as? [String: Any]
        try expect(dingtalk?["clientId"] as? String == "keep-me", "allowed keys stay")
        try expect(dingtalk?["enableAICard"] == nil, "root enableAICard stripped")
        try expect(dingtalk?["requireMention"] == nil, "root requireMention stripped")
        try expect(dingtalk?["robotCode"] == nil, "root robotCode stripped")
        let sales = (dingtalk?["accounts"] as? [String: Any])?["sales"] as? [String: Any]
        try expect(sales?["enableAICard"] == nil, "account enableAICard stripped")
        try expect(sales?["clientId"] as? String == "sales-id", "account clientId stays")
        let groups = sales?["groups"] as? [String: Any]
        let wildcard = groups?["*"] as? [String: Any]
        try expect(wildcard?["requireMention"] as? Bool == true, "groups.*.requireMention stays")
        let feishu = root["channels"].flatMap { $0 as? [String: Any] }?["feishu"] as? [String: Any]
        try expect(feishu?["requireMention"] as? Bool == false, "non-DingTalk channels are left alone")
    }

    private static func testStatusLoadErrorDetectsInvalidConfig() throws {
        let output = """
        OpenClaw config is invalid
        File: ~/.openclaw/openclaw.json
        Problem:
          - channels.dingtalk: invalid config for plugin dingtalk: must not have additional properties: "enableAICard", "requireMention"
        """
        let message = DingTalkChannelConfig.statusLoadError(from: output)
        try expect(message?.contains("enableAICard") == true, "validator detail should surface, got \(message ?? "nil")")
        try expect(
            DingTalkChannelConfig.statusLoadError(from: "- DingTalk default: enabled, configured") == nil,
            "healthy status has no load error"
        )
    }
}
