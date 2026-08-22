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
private enum ThinkingEffortTests {
    static func main() throws {
        try testWireAndSessionVocabulariesDoNotMix()
        try testGatewayRejectionRequiresThinkingAndRefusal()
        print("PASS: thinking effort")
    }

    private static func testWireAndSessionVocabulariesDoNotMix() throws {
        try expect(ThinkingEffort.off.wireValue == "none", "chat.send closes thinking with none")
        try expect(ThinkingEffort.off.sessionLevelValue == "off", "sessions.patch closes thinking with off")
        try expect(ThinkingEffort.auto.wireValue == nil, "auto omits chat.send thinking")
        try expect(ThinkingEffort.auto.sessionLevelValue == nil, "auto clears the session override")
        try expect(ThinkingEffort.medium.wireValue == "medium", "explicit tiers pass through on send")
        try expect(ThinkingEffort.medium.sessionLevelValue == "medium", "explicit tiers pass through on patch")
    }

    private static func testGatewayRejectionRequiresThinkingAndRefusal() throws {
        let positives = [
            "at /thinking: must be string",
            "invalid thinkingLevel: \"off\"",
            "unsupported thinking level: high",
            "model does not support reasoning effort",
            "thinking is not allowed for this model",
            "unknown thinking value",
        ]
        for message in positives {
            try expect(
                ThinkingEffort.isGatewayRejection(message),
                "should treat as thinking rejection: \(message)"
            )
        }

        let negatives: [String?] = [
            nil,
            "",
            "I thought about it and failed",
            "does not support this attachment type",
            "LLM request timed out",
            "effort limit exceeded",
            "thought process interrupted",
            "Gateway is not connected",
        ]
        for message in negatives {
            try expect(
                !ThinkingEffort.isGatewayRejection(message),
                "must not treat as thinking rejection: \(message ?? "nil")"
            )
        }
    }
}
