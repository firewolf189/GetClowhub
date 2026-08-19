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
private enum CronConversationBindingTests {
    static func main() throws {
        let sessionId = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let target = CronConversationBinding.dedicatedTarget(agentId: "Main", sessionId: sessionId)
        try expect(
            target == "session:agent:main:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            "dedicated target must match Windows managed-cron session:<agent-session-key>, got \(target)"
        )

        let parsed = CronConversationBinding.parse(target)
        try expect(parsed?.agentId == "main", "agent id should be lowercased")
        try expect(parsed?.sessionId == sessionId, "uuid must round-trip")

        try expect(CronConversationBinding.parse("isolated") == nil, "isolated is not a conversation")
        try expect(CronConversationBinding.parse("main") == nil, "main is not a conversation")
        try expect(CronConversationBinding.parse("") == nil, "blank is not a conversation")

        print("PASS: cron conversation binding")
    }
}
