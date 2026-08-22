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
private enum ChatMessageGatewayIdentityTests {
    static func main() throws {
        try testOldSessionsDecodeWithoutGatewayIdentity()
        try testStatusCopyPreservesGatewayIdentity()
        try testBinderFillsMissingIdentityFromHistory()
        try testBinderDoesNotClobberSendStampedKey()
        try testBinderMatchesGatewayUserSuffixAndFollowingAssistant()
        print("PASS: ChatMessage gateway identity")
    }

    private static func testOldSessionsDecodeWithoutGatewayIdentity() throws {
        let payload = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "role": "user",
          "content": "hello"
        }
        """
        let message = try JSONDecoder().decode(ChatMessage.self, from: Data(payload.utf8))
        try expect(message.gatewayEntryId == nil, "legacy sessions must decode with a nil gateway entry id")
        try expect(message.idempotencyKey == nil, "legacy sessions must decode with a nil idempotency key")
    }

    private static func testStatusCopyPreservesGatewayIdentity() throws {
        let original = ChatMessage(
            role: .assistant,
            content: "",
            taskStatus: .loading,
            gatewayEntryId: "entry-1",
            idempotencyKey: "key-1"
        )
        let copied = original.withTaskStatus(.completed, content: "done")
        try expect(copied.gatewayEntryId == "entry-1", "withTaskStatus must keep gatewayEntryId")
        try expect(copied.idempotencyKey == "key-1", "withTaskStatus must keep idempotencyKey")
        try expect(copied.content == "done", "withTaskStatus must still replace content")
    }

    private static func testBinderFillsMissingIdentityFromHistory() throws {
        let user = ChatMessage(role: .user, content: "hi", idempotencyKey: "abc")
        let assistant = ChatMessage(role: .assistant, content: "", idempotencyKey: "abc")
        let history = [
            ChatGatewayMessageIdentity(role: "user", entryId: "user-1", idempotencyKey: "abc:user"),
            ChatGatewayMessageIdentity(role: "assistant", entryId: "asst-1", idempotencyKey: nil),
        ]
        let updated = ChatMessageGatewayIdentityBinder.applying([user, assistant], history: history)
        try expect(updated[0].gatewayEntryId == "user-1", "user rows should backfill the history entry id")
        try expect(updated[0].idempotencyKey == "abc", "user rows should keep the client idempotency key")
        try expect(updated[1].gatewayEntryId == "asst-1", "assistant rows should take the following history entry id")
        try expect(updated[1].idempotencyKey == "abc", "assistant rows should keep the send key")
    }

    private static func testBinderDoesNotClobberSendStampedKey() throws {
        let user = ChatMessage(
            role: .user,
            content: "hi",
            gatewayEntryId: "local-entry",
            idempotencyKey: "abc"
        )
        let history = [
            ChatGatewayMessageIdentity(role: "user", entryId: "other-entry", idempotencyKey: "abc:user"),
        ]
        let updated = ChatMessageGatewayIdentityBinder.applying([user], history: history)
        try expect(updated[0].gatewayEntryId == "local-entry", "binder must not overwrite an existing entry id")
        try expect(updated[0].idempotencyKey == "abc", "binder must not overwrite an existing idempotency key")
    }

    private static func testBinderMatchesGatewayUserSuffixAndFollowingAssistant() throws {
        try expect(
            ChatMessageGatewayIdentityBinder.keysMatch("abc:user", "abc"),
            "history user keys use the :user suffix"
        )
        try expect(
            ChatMessageGatewayIdentityBinder.keysMatch("abc", "abc"),
            "exact keys must match"
        )
        try expect(
            !ChatMessageGatewayIdentityBinder.keysMatch("other", "abc"),
            "unrelated keys must not match"
        )
    }
}
