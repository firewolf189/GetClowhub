#!/usr/bin/env swift

import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) throws -> String {
    let url = root.appendingPathComponent(path)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CheckFailure(description: "Missing expected file: \(path)")
    }
    return try String(contentsOf: url, encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure(description: message) }
}

func slice(_ source: String, from start: String, to end: String) throws -> String {
    guard let startRange = source.range(of: start) else {
        throw CheckFailure(description: "Could not find slice start: \(start)")
    }
    guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        throw CheckFailure(description: "Could not find slice end: \(end)")
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

let gateway = try read("OpenClawInstaller/Core/Gateway/GatewayClient.swift")
let connectionModel = try read("OpenClawInstaller/Core/Gateway/GatewayConnectionState.swift")
let eventHub = try read("OpenClawInstaller/Core/Gateway/GatewayChatEvent.swift")
let reconnect = try slice(
    gateway,
    from: "private func scheduleReconnect()",
    to: "// MARK: - Heartbeat"
)
let heartbeat = try slice(
    gateway,
    from: "private func heartbeatTick()",
    to: "// MARK: - Chat Event Helpers"
)

try require(
    connectionModel.contains("struct GatewayReconnectPolicy") &&
        connectionModel.contains("maximumAttempts: Int = 5"),
    "Gateway reconnect policy must cap automatic recovery at five attempts."
)
try require(
    gateway.contains("@Published private(set) var connectionState: GatewayConnectionState"),
    "GatewayClient must publish a typed canonical connection lifecycle."
)
try require(
    eventHub.contains("case transport(GatewayConnectionState)"),
    "Chat subscribers must receive transport lifecycle transitions independently of chat terminal events."
)
try require(
    gateway.contains("private let reconnectPolicy = GatewayReconnectPolicy()"),
    "GatewayClient must use the tested reconnect policy instead of duplicating retry constants."
)
try require(
    !reconnect.contains("eventContinuations.removeAll()") &&
        !reconnect.contains("continuation.finish()"),
    "A transient transport failure must not terminate active chat event streams."
)
try require(
    reconnect.contains("delayBeforeAttempt") &&
        reconnect.contains("canScheduleAttempt"),
    "Reconnect scheduling must delegate attempt bounds and backoff to GatewayReconnectPolicy."
)
try require(
    reconnect.contains(".reconnecting(attempt:") &&
        reconnect.contains(".recoveryExhausted(attempts:"),
    "GatewayClient must distinguish retrying from exhausted recovery."
)
try require(
    reconnect.contains("broadcastEvent(.transport("),
    "Every active chat consumer must observe reconnect and exhaustion transitions."
)
try require(
    reconnect.contains("scheduledGeneration == self.connectionGeneration"),
    "A user-initiated connection must invalidate any older delayed reconnect timer."
)
try require(
    gateway.contains("broadcastEvent(.transport(.connected))"),
    "A successful reconnect must wake active runs so they can reconcile with chat.history."
)
try require(
    gateway.contains("private let eventHub = GatewayChatEventHub()") &&
        eventHub.contains("nonisolated final class GatewayChatEventHub: @unchecked Sendable") &&
        eventHub.contains("bufferingPolicy: .bufferingNewest(Self.bufferLimit)") &&
        eventHub.contains("subscription.runIds.contains(routedEvent.runId)") &&
        eventHub.contains("if routedEvent?.isTerminal == true") &&
        !eventHub.contains("DispatchQueue.global().async"),
    "A lock-owned event hub must route by run, bound buffering, and preserve terminal delivery without global-queue reordering."
)
try require(
    gateway.contains("private func currentWebSocketTask() -> URLSessionWebSocketTask?") &&
        gateway.components(separatedBy: "guard let ws = currentWebSocketTask()").count >= 6,
    "Public RPCs must snapshot the current socket through the serialized connection owner."
)
try require(
    gateway.contains("recordPendingChatSendDelivery(runId: runId)") &&
        gateway.contains("delivery_observed=") &&
        gateway.contains("if !pending.deliveryObserved") &&
        gateway.contains("self.scheduleReconnect()"),
    "A missing chat.send acknowledgement may reconnect only when no run event has already proved delivery."
)
try require(
    gateway.contains("private var pendingConnectRequestId: String?") &&
        gateway.contains("pendingConnectRequestId = requestId") &&
        gateway.contains("guard id == pendingConnectRequestId else"),
    "Only the response matching the active connect request may complete the gateway handshake."
)
try require(
    gateway.contains("pendingConnectRequestId = nil") &&
        !gateway.contains("No pending response matched — treat as connect ack or connect error"),
    "Unmatched or late RPC responses must be ignored instead of being mistaken for a connect acknowledgement."
)
try require(
    gateway.contains("private var pendingHandshakeGeneration: UInt64?") &&
        gateway.contains("scheduleHandshakeTimeout(for:") &&
        gateway.contains("pendingHandshakeGeneration == generation") &&
        gateway.contains("connectionGeneration == generation"),
    "The full gateway handshake, including challenge/ack, must have a generation-bound timeout."
)
try require(
    heartbeat.contains("let generation = connectionGeneration") &&
        heartbeat.contains("generation == self.connectionGeneration") &&
        heartbeat.contains("self.webSocketTask === ws"),
    "A late heartbeat callback from an old socket must not tear down a recovered connection."
)

print("PASS: gateway chat reconnection architecture verified")
