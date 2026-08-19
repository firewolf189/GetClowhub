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
private enum SafeGatewayRepairTests {
    static func main() async throws {
        try recognisesTheBundledSafeRestartCapability()
        try requiresUpgradeWhenIndefiniteDeferralIsUnavailable()
        try parsesScheduledRestart()
        try parsesDeferredRestartAndOfficialActiveCount()
        try parsesCoalescedRestart()
        try rejectsUnknownRestartResults()
        try parsesShellExitMarkerWithoutLeakingIt()
        try recognisesVerifiedConfigValues()
        try commandPlanNeverForcesAHealthyGateway()
        try await repairsAndVerifiesConfigBeforeSchedulingRestart()
        try await returnsImmediatelyWhenRestartIsDeferred()
        try await oldCoreStopsBeforeAnyConfigurationChange()
        try await configWriteFailureStopsBeforeRestart()
        try await failedSafeRestartRequiresExplicitEmergencyChoice()
        try sessionIsolationConfigWritesMissingKeysOnly()
        try sessionIsolationDetectsEitherDingTalkId()
        try await sessionIsolationBootstrapSkipsRestartWhenAlreadyCorrect()
        try await sessionIsolationBootstrapWritesWithoutRestartWhenNoDingTalk()

        print("PASS: safe gateway repair")
    }

    private static func recognisesTheBundledSafeRestartCapability() throws {
        let help = """
        Usage: openclaw gateway restart [options]
          --json
          --safe Request an OpenClaw-aware restart after active work drains
                 gateway.reload.deferralTimeoutMs=0 for indefinite wait
        """
        let state = SafeGatewayRepairCapability.evaluate(
            versionOutput: "OpenClaw 2026.7.1-2 (0790d9f)",
            restartHelpOutput: help
        )
        try expect(
            state == .supported(installedVersion: "2026.7.1-2"),
            "the bundled core already has every capability needed by the client"
        )
    }

    private static func requiresUpgradeWhenIndefiniteDeferralIsUnavailable() throws {
        let state = SafeGatewayRepairCapability.evaluate(
            versionOutput: "OpenClaw 2026.3.2",
            restartHelpOutput: "Usage: openclaw gateway restart"
        )
        try expect(
            state == .upgradeRequired(
                installedVersion: "2026.3.2",
                minimumVersion: SafeGatewayRepairCapability.minimumCoreVersion
            ),
            "an old core must be upgraded, not patched or force-restarted"
        )

        let incomplete = SafeGatewayRepairCapability.evaluate(
            versionOutput: "OpenClaw 2026.7.1",
            restartHelpOutput: "--safe --json"
        )
        try expect(
            incomplete.isUpgradeRequired,
            "--safe without the indefinite deferral setting cannot guarantee task safety"
        )
    }

    private static func parsesScheduledRestart() throws {
        let output = """
        {
          "ok": true,
          "result": "scheduled",
          "message": "safe restart requested",
          "preflight": {
            "safe": true,
            "counts": {
              "queueSize": 0,
              "pendingReplies": 0,
              "embeddedRuns": 0,
              "cronRuns": 0,
              "activeTasks": 0,
              "totalActive": 0
            },
            "blockers": [],
            "summary": "safe to restart now"
          }
        }
        """
        let response = try GatewaySafeRestartResponse.decodeCLIOutput(output)
        try expect(response.disposition == .scheduled, "scheduled result was not preserved")
        try expect(response.activeCount == 0, "an idle preflight must report zero active work")
    }

    private static func parsesDeferredRestartAndOfficialActiveCount() throws {
        let output = """
        OpenClaw diagnostic banner
        {
          "ok": true,
          "result": "deferred",
          "preflight": {
            "safe": false,
            "counts": {
              "queueSize": 1,
              "pendingReplies": 1,
              "embeddedRuns": 1,
              "cronRuns": 0,
              "activeTasks": 2,
              "totalActive": 5
            },
            "blockers": [],
            "summary": "restart deferred"
          }
        }
        """
        let response = try GatewaySafeRestartResponse.decodeCLIOutput(output)
        try expect(response.disposition == .deferred, "deferred result was not preserved")
        try expect(
            response.activeCount == 5,
            "the UI must use OpenClaw's global total instead of inferring from local chat state"
        )
    }

    private static func parsesCoalescedRestart() throws {
        let output = """
        {"ok":true,"result":"coalesced","preflight":{"safe":false,"counts":{"queueSize":1,"pendingReplies":0,"embeddedRuns":0,"cronRuns":0,"activeTasks":0,"totalActive":1},"blockers":[],"summary":"restart deferred"}}
        """
        let response = try GatewaySafeRestartResponse.decodeCLIOutput(output)
        try expect(response.disposition == .coalesced, "an existing restart request must not be duplicated")
        try expect(response.activeCount == 1, "coalesced result should retain its preflight count")
    }

    private static func rejectsUnknownRestartResults() throws {
        let output = """
        {"ok":true,"result":"forced","preflight":{"safe":true,"counts":{"queueSize":0,"pendingReplies":0,"embeddedRuns":0,"cronRuns":0,"activeTasks":0,"totalActive":0},"blockers":[],"summary":"unexpected"}}
        """
        do {
            _ = try GatewaySafeRestartResponse.decodeCLIOutput(output)
            throw TestFailure.assertion("an unknown result must fail closed")
        } catch is DecodingError {
            // Expected.
        }
    }

    private static func parsesShellExitMarkerWithoutLeakingIt() throws {
        let parsed = SafeGatewayShellResult.decode(
            "Updated session.dmScope\n\(SafeGatewayShellResult.marker)0"
        )
        try expect(parsed?.exitCode == 0, "exit code marker was not parsed")
        try expect(parsed?.output == "Updated session.dmScope", "internal marker leaked into user-visible output")
        try expect(
            SafeGatewayShellResult.decode("command timed out") == nil,
            "missing exit marker must be treated as an unknown command result"
        )
    }

    private static func recognisesVerifiedConfigValues() throws {
        try expect(
            SafeGatewayConfigVerification.isExpectedDMScope(#""per-channel-peer""#),
            "JSON string output should verify dmScope"
        )
        try expect(
            !SafeGatewayConfigVerification.isExpectedDMScope(#""main""#),
            "the unsafe shared scope must not verify"
        )
        try expect(
            SafeGatewayConfigVerification.isExpectedDeferralTimeout("0"),
            "numeric zero should verify indefinite deferral"
        )
        try expect(
            !SafeGatewayConfigVerification.isExpectedDeferralTimeout("30000"),
            "a bounded timeout may force restart and must not verify"
        )
    }

    private static func commandPlanNeverForcesAHealthyGateway() throws {
        try expect(
            SafeGatewayRepairCommands.safeRestart.contains("gateway restart --safe --json"),
            "safe repair must call the official safe restart command"
        )
        try expect(
            !SafeGatewayRepairCommands.safeRestart.contains("--force"),
            "safe repair must never force the gateway"
        )
        try expect(
            SafeGatewayRepairCommands.setDMScope.contains("session.dmScope")
                && SafeGatewayRepairCommands.setDMScope.contains("per-channel-peer")
                && SafeGatewayRepairCommands.setDMScope.contains("--strict-json"),
            "dmScope must be written through the validated official config command"
        )
        try expect(
            SafeGatewayRepairCommands.setDeferralTimeout.contains("gateway.reload.deferralTimeoutMs")
                && SafeGatewayRepairCommands.setDeferralTimeout.contains(" 0 ")
                && SafeGatewayRepairCommands.setDeferralTimeout.contains("--strict-json"),
            "safe repair must configure indefinite deferral before requesting restart"
        )
    }

    private static func repairsAndVerifiesConfigBeforeSchedulingRestart() async throws {
        let help = "--safe --json gateway.reload.deferralTimeoutMs indefinite"
        let scheduled = """
        {"ok":true,"result":"scheduled","preflight":{"safe":true,"counts":{"queueSize":0,"pendingReplies":0,"embeddedRuns":0,"cronRuns":0,"activeTasks":0,"totalActive":0},"summary":"safe"}}
        """
        let expectedCommands = [
            SafeGatewayRepairCommands.version,
            SafeGatewayRepairCommands.restartHelp,
            SafeGatewayRepairCommands.reportingExitStatus(SafeGatewayRepairCommands.getDeferralTimeout),
            SafeGatewayRepairCommands.reportingExitStatus(SafeGatewayRepairCommands.setDeferralTimeout),
            SafeGatewayRepairCommands.reportingExitStatus(SafeGatewayRepairCommands.getDeferralTimeout),
            SafeGatewayRepairCommands.reportingExitStatus(SafeGatewayRepairCommands.getDMScope),
            SafeGatewayRepairCommands.reportingExitStatus(SafeGatewayRepairCommands.setDMScope),
            SafeGatewayRepairCommands.reportingExitStatus(SafeGatewayRepairCommands.getDMScope),
            SafeGatewayRepairCommands.reportingExitStatus(SafeGatewayRepairCommands.safeRestart),
            SafeGatewayRepairCommands.reportingExitStatus(SafeGatewayRepairCommands.getDeferralTimeout),
            SafeGatewayRepairCommands.reportingExitStatus(SafeGatewayRepairCommands.getDMScope),
            SafeGatewayRepairCommands.channelStatus,
        ]
        let responses: [String?] = [
            "OpenClaw 2026.7.1-2",
            help,
            shellResult("missing", exitCode: 1),
            shellResult("updated"),
            shellResult("0"),
            shellResult(#""main""#),
            shellResult("updated"),
            shellResult(#""per-channel-peer""#),
            shellResult(scheduled),
            shellResult("0"),
            shellResult(#""per-channel-peer""#),
            "- DingTalk default: enabled, configured",
        ]
        let runner = ScriptedRunner(responses: responses)
        var recoveryChecks = 0
        let coordinator = SafeGatewayRepairCoordinator(
            runCommand: { command, _ in await runner.run(command) },
            waitForRecovery: {
                recoveryChecks += 1
                return true
            }
        )

        let outcome = await coordinator.repair()
        try expect(
            outcome == .scheduled(dingtalkReady: true),
            "idle repair should verify recovery and DingTalk, got \(outcome)"
        )
        let scheduledCommands = await runner.commands
        try expect(scheduledCommands == expectedCommands, "safe repair command order changed")
        try expect(recoveryChecks == 1, "scheduled restart must wait for gateway recovery once")
    }

    private static func returnsImmediatelyWhenRestartIsDeferred() async throws {
        let deferred = """
        {"ok":true,"result":"deferred","preflight":{"safe":false,"counts":{"queueSize":1,"pendingReplies":1,"embeddedRuns":0,"cronRuns":0,"activeTasks":1,"totalActive":3},"summary":"waiting"}}
        """
        let responses: [String?] = [
            "OpenClaw 2026.7.1-2",
            "--safe --json gateway.reload.deferralTimeoutMs indefinite",
            shellResult("0"),
            shellResult(#""per-channel-peer""#),
            shellResult(deferred),
        ]
        let runner = ScriptedRunner(responses: responses)
        var recoveryChecks = 0
        let coordinator = SafeGatewayRepairCoordinator(
            runCommand: { command, _ in await runner.run(command) },
            waitForRecovery: {
                recoveryChecks += 1
                return true
            }
        )

        let outcome = await coordinator.repair()
        try expect(
            outcome == .deferred(activeCount: 3),
            "active work should be left to OpenClaw's official deferral, got \(outcome)"
        )
        try expect(recoveryChecks == 0, "a deferred restart must not block the client waiting for recovery")
        let deferredCommands = await runner.commands
        try expect(
            !deferredCommands.contains(where: { $0.contains("pkill") || $0.contains("--force") }),
            "safe repair must not fall through to destructive process cleanup"
        )
    }

    private static func oldCoreStopsBeforeAnyConfigurationChange() async throws {
        let runner = ScriptedRunner(responses: [
            "OpenClaw 2026.3.2",
            "Usage: openclaw gateway restart",
        ])
        let coordinator = SafeGatewayRepairCoordinator(
            runCommand: { command, _ in await runner.run(command) },
            waitForRecovery: { true }
        )

        let outcome = await coordinator.repair()
        try expect(
            outcome == .upgradeRequired(
                installedVersion: "2026.3.2",
                minimumVersion: "2026.7.1-2"
            ),
            "an unsupported core must return an upgrade result"
        )
        let commands = await runner.commands
        try expect(commands.count == 2, "old core check must stop before touching config")
        try expect(
            !commands.contains(where: { $0.contains("config set") || $0.contains("gateway restart") && $0.contains("--safe") }),
            "the client must not emulate missing core behavior"
        )
    }

    private static func failedSafeRestartRequiresExplicitEmergencyChoice() async throws {
        let runner = ScriptedRunner(responses: [
            "OpenClaw 2026.7.1-2",
            "--safe --json gateway.reload.deferralTimeoutMs indefinite",
            shellResult("0"),
            shellResult(#""per-channel-peer""#),
            shellResult("gateway unreachable", exitCode: 1),
        ])
        let coordinator = SafeGatewayRepairCoordinator(
            runCommand: { command, _ in await runner.run(command) },
            waitForRecovery: { true }
        )

        let outcome = await coordinator.repair()
        try expect(outcome == .safeRestartFailed, "unreachable gateway must fail the safe request")
        try expect(
            outcome.requiresEmergencyConfirmation,
            "destructive fallback must require the UI's separate confirmation"
        )
        let commands = await runner.commands
        try expect(
            !commands.contains(where: { $0.contains("pkill") || $0.contains("kill -9") }),
            "safe failure must not automatically fall through to process cleanup"
        )
    }

    private static func configWriteFailureStopsBeforeRestart() async throws {
        let runner = ScriptedRunner(responses: [
            "OpenClaw 2026.7.1-2",
            "--safe --json gateway.reload.deferralTimeoutMs indefinite",
            shellResult("missing", exitCode: 1),
            shellResult("invalid config", exitCode: 1),
        ])
        let coordinator = SafeGatewayRepairCoordinator(
            runCommand: { command, _ in await runner.run(command) },
            waitForRecovery: { true }
        )

        let outcome = await coordinator.repair()
        try expect(
            outcome == .configurationFailed(step: .writeDeferralTimeout),
            "failed validated config write must return its structured step"
        )
        let commands = await runner.commands
        try expect(
            !commands.contains(where: { $0.contains("gateway restart --safe --json") }),
            "failed config verification must stop before restart"
        )
    }

    private static func shellResult(_ output: String, exitCode: Int32 = 0) -> String {
        "\(output)\n\(SafeGatewayShellResult.marker)\(exitCode)"
    }

    private static func sessionIsolationConfigWritesMissingKeysOnly() throws {
        var dict: [String: Any] = [
            "gateway": ["mode": "local"],
            "session": ["scope": "per-peer"],
        ]
        try expect(SessionIsolationConfig.apply(to: &dict), "missing isolation keys must be written")
        try expect(SessionIsolationConfig.isSatisfied(dict), "apply must leave the document satisfied")
        try expect(dict["session"] as? [String: String] != nil || (dict["session"] as? [String: Any])?["scope"] as? String == "per-peer", "unrelated session keys stay")
        try expect(!SessionIsolationConfig.apply(to: &dict), "a second apply must be a no-op")
    }

    private static func sessionIsolationDetectsEitherDingTalkId() throws {
        try expect(
            SessionIsolationConfig.hasDingTalk(["channels": ["dingtalk": ["enabled": true]]]),
            "Mac historical id is DingTalk"
        )
        try expect(
            SessionIsolationConfig.hasDingTalk(["channels": ["dingtalk-connector": [:]]]),
            "Windows plugin id is DingTalk"
        )
        try expect(
            !SessionIsolationConfig.hasDingTalk(["channels": ["feishu": [:]]]),
            "Feishu is not DingTalk"
        )
    }

    private static func sessionIsolationBootstrapSkipsRestartWhenAlreadyCorrect() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gch-isolation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("openclaw.json")
        var dict: [String: Any] = ["gateway": ["mode": "local"]]
        _ = SessionIsolationConfig.apply(to: &dict)
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
        try data.write(to: url)

        var ran = false
        let outcome = await SessionIsolationBootstrap.applyIfNeeded(
            configURL: url,
            runCommand: { _, _ in
                ran = true
                return nil
            },
            waitForRecovery: { true }
        )
        try expect(outcome == .alreadyCorrect, "satisfied config must not restart, got \(outcome)")
        try expect(!ran, "already-correct bootstrap must not spawn CLI")
    }

    private static func sessionIsolationBootstrapWritesWithoutRestartWhenNoDingTalk() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gch-isolation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("openclaw.json")
        let data = try JSONSerialization.data(withJSONObject: ["gateway": ["mode": "local"]], options: [])
        try data.write(to: url)

        var ran = false
        let outcome = await SessionIsolationBootstrap.applyIfNeeded(
            configURL: url,
            runCommand: { _, _ in
                ran = true
                return nil
            },
            waitForRecovery: { true }
        )
        try expect(outcome == .wroteConfigOnly, "no DingTalk means write-only, got \(outcome)")
        try expect(!ran, "write-only path must not call gateway restart")
        let written = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        try expect(SessionIsolationConfig.isSatisfied(written ?? [:]), "file must contain isolation keys")
    }
}

private actor ScriptedRunner {
    private(set) var commands: [String] = []
    private var responses: [String?]

    init(responses: [String?]) {
        self.responses = responses
    }

    func run(_ command: String) -> String? {
        commands.append(command)
        guard !responses.isEmpty else { return nil }
        return responses.removeFirst()
    }
}
