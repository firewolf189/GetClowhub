import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func require(_ condition: Bool, _ message: String) {
    guard condition else {
        fatalError(message)
    }
}

let chatHelpers = read("OpenClawInstaller/Features/Chat/ChatHelpers.swift")
let gateway = read("OpenClawInstaller/Core/Gateway/GatewayClient.swift")

require(
    chatHelpers.contains("let chatSendStart = ContinuousClock.now"),
    "sendChatMessage should record the local send start time"
)
require(
    chatHelpers.contains(#"phase=chat_send_start"#),
    "sendChatMessage should log chat_send_start"
)
require(
    chatHelpers.contains(#"phase=chat_send_ack"#),
    "sendChatMessage should log chat_send_ack after runId is received"
)
require(
    chatHelpers.contains(#"phase=chat_first_event"#),
    "sendChatMessage should log the first gateway event after ack"
)
require(
    chatHelpers.contains(#"phase=chat_first_delta"#),
    "sendChatMessage should log the first text delta"
)
require(
    chatHelpers.contains(#"phase=chat_final"#),
    "sendChatMessage should log final event timing"
)
require(
    chatHelpers.contains(#"phase=chat_error"#),
    "sendChatMessage should log error event timing"
)
require(
    gateway.contains("let startedAt: ContinuousClock.Instant") &&
        gateway.contains("startedAt: chatSendStartedAt"),
    "GatewayClient should retain each chat.send start time in its typed pending request"
)
require(
    gateway.contains(#"phase=chat_send_ws_send"#),
    "GatewayClient should log when the WebSocket send callback succeeds"
)
require(
    gateway.contains(#"phase=chat_send_ack"#),
    "GatewayClient should log when the gateway ack returns a runId"
)
require(
    gateway.contains(#"phase=chat_send_ack_timeout"#),
    "GatewayClient should log chat.send ack timeout"
)

print("Chat latency instrumentation checks passed")
