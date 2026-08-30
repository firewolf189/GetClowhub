#!/usr/bin/env swift

import Foundation

/// Locks the four hot-path contracts from the 2026-08 Mac client analysis:
/// 1. chat.send delivery is not gateway-runId == client idempotency key
/// 2. ack timeout does not reconnect; transport write failure still may
/// 3. status-poll connect() only from disconnected / recoveryExhausted
/// 4. confirmed chat.abort waits for state:aborted (or flush timeout)
/// plus DingTalk write-key reuse.

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

func read(_ path: String) -> String {
    let url = repoRoot.appendingPathComponent(path)
    guard let value = try? String(contentsOf: url, encoding: .utf8) else {
        fail("could not read \(path)")
    }
    return value
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fail(message) }
}

func slice(_ source: String, from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        fail("could not slice between \(start) and \(end)")
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

@discardableResult
func run(_ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    do { try process.run() } catch {
        fail("could not launch \(arguments[0]): \(error)")
    }
    process.waitUntilExit()
    return process.terminationStatus
}

func compileAndRun(sources: [String], label: String) {
    let fm = FileManager.default
    let workDir = fm.temporaryDirectory.appendingPathComponent("verify-hotpath-\(UUID().uuidString)")
    try! fm.createDirectory(at: workDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: workDir) }
    let binary = workDir.appendingPathComponent("verify")
    var args = ["swiftc"]
    args += sources.map { repoRoot.appendingPathComponent($0).path }
    args += ["-o", binary.path]
    if run(args) != 0 {
        fail("\(label) failed to compile")
    }
    if run([binary.path]) != 0 {
        fail("\(label) failed")
    }
}

let gateway = read("OpenClawInstaller/Core/Gateway/GatewayClient.swift")
let connection = read("OpenClawInstaller/Core/Gateway/GatewayConnectionState.swift")
let snapshot = read("OpenClawInstaller/Core/Gateway/GatewayChatRecoverySnapshot.swift")
let dashboard = read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")
let helpers = read("OpenClawInstaller/Features/Chat/ChatHelpers.swift")
let policy = read("OpenClawInstaller/Features/Chat/State/ChatRunReconciliationPolicy.swift")
let dingtalk = read("OpenClawInstaller/Features/Channels/Models/DingTalkChannelConfig.swift")
let channels = read("OpenClawInstaller/Features/Channels/Core/ChannelManagement.swift")

require(
    snapshot.contains("enum GatewayChatSendDeliveryMatcher") &&
        snapshot.contains("class GatewayChatSendRequestRegistry") &&
        snapshot.contains("matchesSessionFallback") &&
        gateway.contains("chatSendRequestRegistry.recordDelivery") &&
        gateway.contains("idempotencyKey: payload[\"idempotencyKey\"] as? String"),
    "chat.send delivery must match idempotency/session, not gateway runId == client key"
)

let sendError = slice(
    gateway,
    from: "chatSend: WebSocket send error",
    to: "transport-write-failed"
)
require(
    sendError.contains("self.scheduleReconnect()"),
    "a failed WebSocket write may reconnect when no run event has proved delivery"
)

let ackTimeout = slice(
    gateway,
    from: "Timeout after 10 seconds for the send acknowledgement",
    to: "ack-timeout-does-not-reconnect"
)
require(
    !ackTimeout.contains("scheduleReconnect()"),
    "a late chat.send acknowledgement must not tear down a live socket"
)

require(
    connection.contains("var needsConnect: Bool") &&
        dashboard.contains("connectionState.needsConnect") &&
        gateway.contains("connect() ignored: socket already in flight") &&
        gateway.contains("connect() ignored: reconnect already scheduled"),
    "status polls must not restart an in-flight gateway handshake"
)

require(
    helpers.contains("waitForAbortedStreamEvent") &&
        helpers.contains("phase=chat_abort_acked_waiting_event") &&
        helpers.contains("ChatAbortFlushPolicy.eventWaitNanoseconds") &&
        policy.contains("enum ChatAbortFlushPolicy"),
    "confirmed chat.abort must wait for state:aborted (or the flush timeout)"
)

let abortRegistry = read("OpenClawInstaller/Core/Gateway/GatewayChatAbortRequestRegistry.swift")
let identity = read("OpenClawInstaller/Core/Gateway/GatewayProcessIdentity.swift")
require(
    abortRegistry.contains("guard let expectedRunId else { return .confirmed(runIds: runIds) }") &&
        abortRegistry.contains("static func parse(fromRPC json: [String: Any])") &&
        gateway.contains("GatewayChatAbortResponse.parse(fromRPC: json)") &&
        dashboard.contains("abortChat(sessionKey: sessionKey)"),
    "session-level chat.abort without runId must confirm aborted=true; rewind uses that path"
)
require(
    identity.contains("struct GatewayProcessIdentity") &&
        identity.contains("hello-ok.snapshot.uptimeMs") &&
        identity.contains("startEstimateTolerance") &&
        identity.contains("allowsIdempotencyProbe") &&
        identity.contains("enum GatewayChatSendProbePolicy") &&
        identity.contains("case recoveryProbe(originatingEpoch:") &&
        gateway.contains("processIdentity.applyHello(payload:") &&
        gateway.contains("GatewayInboundJSON.object(from:") &&
        gateway.contains("func allowsChatSendProbe(originatingEpoch:") &&
        gateway.contains("mode: GatewayChatSendMode = .initial") &&
        helpers.contains("allowsChatSendProbe(originatingEpoch:") &&
        helpers.contains("mode: .recoveryProbe(originatingEpoch:") &&
        helpers.contains("processEpoch: gatewayClient.capturedProcessEpoch()"),
    "hello-ok must update a process fingerprint; reconnect chat.send probes only the same known process"
)

require(
    dingtalk.contains("static let preferredWriteKey = \"dingtalk\"") &&
        dingtalk.contains("static func resolvedConfigKey") &&
        channels.contains("DingTalkChannelConfig.resolvedConfigKey(in: channels)") &&
        channels.contains("resolvedChannelWriteKey"),
    "DingTalk writes must reuse an existing dingtalk / dingtalk-connector object"
)

let thinking = read("OpenClawInstaller/Features/Chat/Models/ThinkingEffort.swift")
require(
    thinking.contains("static func isGatewayRejection") &&
        thinking.contains("mentionsThinking") &&
        thinking.contains("looksRejected") &&
        helpers.contains("ThinkingEffort.isGatewayRejection(message)") &&
        helpers.contains("var sendThinking = composerEffort.wireValue") &&
        helpers.contains("thinking: sendThinking"),
    "thinking rejection must require both a thinking token and a refusal; reconnect retries must keep the chosen thinking"
)
require(
    !helpers.contains("needles = [\"thinking\", \"reasoning\", \"effort\", \"thought\", \"not support\"]"),
    "the wide thinking-rejection needle list must not return"
)

compileAndRun(
    sources: [
        "OpenClawInstaller/Core/Gateway/GatewayChatRecoverySnapshot.swift",
        "Tests/GatewayChatSendRequestRegistryTests.swift",
    ],
    label: "GatewayChatSendRequestRegistry tests"
)
compileAndRun(
    sources: [
        "OpenClawInstaller/Core/Gateway/GatewayChatRecoverySnapshot.swift",
        "Tests/GatewayChatRecoverySnapshotTests.swift",
    ],
    label: "GatewayChatRecoverySnapshot tests"
)
compileAndRun(
    sources: [
        "OpenClawInstaller/Core/Gateway/GatewayConnectionState.swift",
        "Tests/GatewayReconnectPolicyTests.swift",
    ],
    label: "GatewayReconnectPolicy tests"
)
compileAndRun(
    sources: [
        "OpenClawInstaller/Features/Chat/State/ChatRunReconciliationPolicy.swift",
        "Tests/ChatRunReconciliationPolicyTests.swift",
    ],
    label: "ChatRunReconciliationPolicy tests"
)
compileAndRun(
    sources: [
        "OpenClawInstaller/Features/Chat/Models/ThinkingEffort.swift",
        "Tests/ThinkingEffortTests.swift",
    ],
    label: "ThinkingEffort tests"
)
compileAndRun(
    sources: [
        "OpenClawInstaller/Core/Gateway/GatewayChatAbortRequestRegistry.swift",
        "Tests/GatewayChatAbortRequestRegistryTests.swift",
    ],
    label: "GatewayChatAbortRequestRegistry tests"
)
compileAndRun(
    sources: [
        "OpenClawInstaller/Core/Gateway/GatewayProcessIdentity.swift",
        "Tests/GatewayProcessIdentityTests.swift",
    ],
    label: "GatewayProcessIdentity tests"
)
compileAndRun(
    sources: [
        "OpenClawInstaller/Features/Chat/Models/ChatRunState.swift",
        "Tests/ChatRunStateTests.swift",
    ],
    label: "ChatRunState tests"
)
compileAndRun(
    sources: [
        "OpenClawInstaller/Features/Chat/State/StoppedRunTranscriptIsolation.swift",
        "Tests/StoppedRunTranscriptIsolationTests.swift",
    ],
    label: "StoppedRunTranscriptIsolation tests"
)
compileAndRun(
    sources: [
        "OpenClawInstaller/Features/Chat/State/GatewayTranscriptRehydrate.swift",
        "Tests/GatewayTranscriptRehydrateTests.swift",
    ],
    label: "GatewayTranscriptRehydrate tests"
)
compileAndRun(
    sources: [
        "OpenClawInstaller/Core/Gateway/GatewayProcessIdentity.swift",
        "OpenClawInstaller/Core/Gateway/GatewayChatAbortRequestRegistry.swift",
        "Tests/GatewayFakeWebSocketTests.swift",
    ],
    label: "Gateway fake WebSocket tests"
)

print("PASS: hot-path contracts verified")
