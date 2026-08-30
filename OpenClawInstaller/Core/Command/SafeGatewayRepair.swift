import Foundation

enum SafeGatewayRepairCapabilityState: Equatable {
    case supported(installedVersion: String?)
    case upgradeRequired(installedVersion: String?, minimumVersion: String)

    var isUpgradeRequired: Bool {
        if case .upgradeRequired = self { return true }
        return false
    }
}

enum SafeGatewayRepairCapability {
    /// First bundled core that exposes both official safe restart and indefinite
    /// active-work deferral. Older cores are upgraded; they are never patched by
    /// the client.
    static let minimumCoreVersion = "2026.7.1-2"

    static func evaluate(
        versionOutput: String?,
        restartHelpOutput: String?
    ) -> SafeGatewayRepairCapabilityState {
        let version = extractVersion(from: versionOutput)
        let help = restartHelpOutput ?? ""
        let supportsSafeRestart = help.contains("--safe")
            && help.contains("--json")
            && help.contains("gateway.reload.deferralTimeoutMs")
            && help.localizedCaseInsensitiveContains("indefinite")

        if supportsSafeRestart {
            return .supported(installedVersion: version)
        }
        return .upgradeRequired(
            installedVersion: version,
            minimumVersion: minimumCoreVersion
        )
    }

    private static func extractVersion(from output: String?) -> String? {
        guard let output else { return nil }
        let pattern = #"\d+(?:\.\d+){1,3}(?:-\d+)?"#
        guard let range = output.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(output[range])
    }
}

enum GatewaySafeRestartDisposition: String, Decodable, Equatable {
    case scheduled
    case deferred
    case coalesced
}

struct GatewaySafeRestartResponse: Decodable, Equatable {
    struct Preflight: Decodable, Equatable {
        struct Counts: Decodable, Equatable {
            let queueSize: Int?
            let pendingReplies: Int?
            let embeddedRuns: Int?
            let cronRuns: Int?
            let activeTasks: Int?
            let totalActive: Int?
        }

        let safe: Bool
        let counts: Counts
        let summary: String?
    }

    let ok: Bool
    let disposition: GatewaySafeRestartDisposition
    let message: String?
    let preflight: Preflight

    private enum CodingKeys: String, CodingKey {
        case ok
        case disposition = "result"
        case message
        case preflight
    }

    var activeCount: Int {
        if let total = preflight.counts.totalActive {
            return max(0, total)
        }
        return [
            preflight.counts.queueSize,
            preflight.counts.pendingReplies,
            preflight.counts.embeddedRuns,
            preflight.counts.cronRuns,
            preflight.counts.activeTasks,
        ]
        .compactMap { $0 }
        .reduce(0) { $0 + max(0, $1) }
    }

    static func decodeCLIOutput(_ output: String) throws -> GatewaySafeRestartResponse {
        guard let start = output.firstIndex(of: "{"),
              let end = output.lastIndex(of: "}"),
              start <= end else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Safe restart did not return JSON"
            ))
        }
        let json = String(output[start...end])
        let response = try JSONDecoder().decode(
            GatewaySafeRestartResponse.self,
            from: Data(json.utf8)
        )
        guard response.ok else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Safe restart was not accepted"
            ))
        }
        return response
    }
}

struct SafeGatewayShellResult: Equatable {
    static let marker = "__GETCLAWHUB_SAFE_REPAIR_EXIT__="

    let output: String
    let exitCode: Int32

    var succeeded: Bool { exitCode == 0 }

    static func decode(_ raw: String?) -> SafeGatewayShellResult? {
        guard let raw,
              let markerRange = raw.range(of: marker, options: .backwards) else {
            return nil
        }
        let codeText = raw[markerRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first ?? ""
        guard let code = Int32(codeText) else { return nil }
        let output = raw[..<markerRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SafeGatewayShellResult(output: output, exitCode: code)
    }
}

enum SafeGatewayConfigVerification {
    static func isExpectedDMScope(_ output: String) -> Bool {
        if let data = output.data(using: .utf8),
           let value = try? JSONDecoder().decode(String.self, from: data) {
            return value == "per-channel-peer"
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "per-channel-peer"
    }

    static func isExpectedDeferralTimeout(_ output: String) -> Bool {
        if let data = output.data(using: .utf8),
           let value = try? JSONDecoder().decode(Int.self, from: data) {
            return value == 0
        }
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) == 0
    }
}

enum SafeGatewayRepairCommands {
    static let version = "openclaw --version 2>&1"
    static let restartHelp = "openclaw gateway restart --help 2>&1"

    static let getDMScope = "openclaw config get session.dmScope --json 2>&1"
    static let setDMScope =
        #"openclaw config set session.dmScope '"per-channel-peer"' --strict-json 2>&1"#

    static let getDeferralTimeout =
        "openclaw config get gateway.reload.deferralTimeoutMs --json 2>&1"
    static let setDeferralTimeout =
        "openclaw config set gateway.reload.deferralTimeoutMs 0 --strict-json 2>&1"

    static let safeRestart = "openclaw gateway restart --safe --json 2>&1"
    static let channelStatus =
        #"openclaw channels status 2>&1 | sed 's/\x1b\[[0-9;]*m//g'"#

    static func reportingExitStatus(_ command: String) -> String {
        "\(command); getclawhub_safe_repair_status=$?; "
            + "printf '\\n\(SafeGatewayShellResult.marker)%s\\n' "
            + "\"$getclawhub_safe_repair_status\""
    }
}

enum SafeGatewayConfigurationStep: Equatable {
    case writeDeferralTimeout
    case verifyDeferralTimeout
    case writeDMScope
    case verifyDMScope
}

enum SafeGatewayRepairOutcome: Equatable {
    case scheduled(dingtalkReady: Bool)
    case deferred(activeCount: Int)
    case coalesced(activeCount: Int)
    case upgradeRequired(installedVersion: String?, minimumVersion: String)
    case configurationFailed(step: SafeGatewayConfigurationStep)
    case safeRestartFailed
    case recoveryVerificationFailed

    var requiresEmergencyConfirmation: Bool {
        switch self {
        case .configurationFailed, .safeRestartFailed, .recoveryVerificationFailed:
            return true
        case .scheduled, .deferred, .coalesced, .upgradeRequired:
            return false
        }
    }
}

struct SafeGatewayRepairCoordinator {
    typealias CommandRunner = (_ command: String, _ timeout: TimeInterval) async -> String?
    typealias RecoveryWaiter = () async -> Bool

    private let runCommand: CommandRunner
    private let waitForRecovery: RecoveryWaiter

    init(
        runCommand: @escaping CommandRunner,
        waitForRecovery: @escaping RecoveryWaiter
    ) {
        self.runCommand = runCommand
        self.waitForRecovery = waitForRecovery
    }

    func repair() async -> SafeGatewayRepairOutcome {
        let version = await runCommand(SafeGatewayRepairCommands.version, 15)
        let restartHelp = await runCommand(SafeGatewayRepairCommands.restartHelp, 15)
        let capability = SafeGatewayRepairCapability.evaluate(
            versionOutput: version,
            restartHelpOutput: restartHelp
        )
        if case .upgradeRequired(let installed, let minimum) = capability {
            return .upgradeRequired(installedVersion: installed, minimumVersion: minimum)
        }

        if let failure = await ensureDeferralTimeout() {
            return .configurationFailed(step: failure)
        }
        if let failure = await ensureDMScope() {
            return .configurationFailed(step: failure)
        }

        guard let commandResult = await checked(
            SafeGatewayRepairCommands.safeRestart,
            timeout: 20
        ),
        commandResult.succeeded,
        let restart = try? GatewaySafeRestartResponse.decodeCLIOutput(commandResult.output) else {
            return .safeRestartFailed
        }

        switch restart.disposition {
        case .deferred:
            return .deferred(activeCount: restart.activeCount)
        case .coalesced:
            return .coalesced(activeCount: restart.activeCount)
        case .scheduled:
            guard await waitForRecovery(),
                  await currentConfigurationIsVerified() else {
                return .recoveryVerificationFailed
            }
            let channelOutput = await runCommand(SafeGatewayRepairCommands.channelStatus, 20)
            return .scheduled(
                dingtalkReady: SafeGatewayChannelVerification.isDingTalkReady(channelOutput)
            )
        }
    }

    private func ensureDeferralTimeout() async -> SafeGatewayConfigurationStep? {
        if await configValueMatches(
            command: SafeGatewayRepairCommands.getDeferralTimeout,
            predicate: SafeGatewayConfigVerification.isExpectedDeferralTimeout
        ) {
            return nil
        }
        guard await checked(SafeGatewayRepairCommands.setDeferralTimeout)?.succeeded == true else {
            return .writeDeferralTimeout
        }
        guard await configValueMatches(
            command: SafeGatewayRepairCommands.getDeferralTimeout,
            predicate: SafeGatewayConfigVerification.isExpectedDeferralTimeout
        ) else {
            return .verifyDeferralTimeout
        }
        return nil
    }

    private func ensureDMScope() async -> SafeGatewayConfigurationStep? {
        if await configValueMatches(
            command: SafeGatewayRepairCommands.getDMScope,
            predicate: SafeGatewayConfigVerification.isExpectedDMScope
        ) {
            return nil
        }
        guard await checked(SafeGatewayRepairCommands.setDMScope)?.succeeded == true else {
            return .writeDMScope
        }
        guard await configValueMatches(
            command: SafeGatewayRepairCommands.getDMScope,
            predicate: SafeGatewayConfigVerification.isExpectedDMScope
        ) else {
            return .verifyDMScope
        }
        return nil
    }

    private func currentConfigurationIsVerified() async -> Bool {
        guard await configValueMatches(
            command: SafeGatewayRepairCommands.getDeferralTimeout,
            predicate: SafeGatewayConfigVerification.isExpectedDeferralTimeout
        ) else {
            return false
        }
        return await configValueMatches(
            command: SafeGatewayRepairCommands.getDMScope,
            predicate: SafeGatewayConfigVerification.isExpectedDMScope
        )
    }

    private func configValueMatches(
        command: String,
        predicate: (String) -> Bool
    ) async -> Bool {
        guard let result = await checked(command), result.succeeded else {
            return false
        }
        return predicate(result.output)
    }

    private func checked(
        _ command: String,
        timeout: TimeInterval = 30
    ) async -> SafeGatewayShellResult? {
        let raw = await runCommand(
            SafeGatewayRepairCommands.reportingExitStatus(command),
            timeout
        )
        return SafeGatewayShellResult.decode(raw)
    }
}

/// JSON-level isolation defaults. Used on launch so existing installs pick up
/// `per-channel-peer` without waiting for the user to click Safe Repair.
enum SessionIsolationConfig {
    static let dmScope = "per-channel-peer"
    static let deferralTimeoutMs = 0
    static let dingtalkKeys = ["dingtalk", "dingtalk-connector"]
    /// OpenClaw has no `reset: off`. Default `daily` at 04:00 (and short idle)
    /// wipes the gateway transcript while the UI still shows the thread.
    /// Ten years of idle is "never forget because you stopped talking";
    /// `/new` and deleting a session still clear context. Compaction still
    /// shrinks long threads without changing session identity.
    static let sessionResetMode = "idle"
    static let sessionIdleMinutes = 5_256_000

    static func isSatisfied(_ dict: [String: Any]) -> Bool {
        let session = dict["session"] as? [String: Any]
        let gateway = dict["gateway"] as? [String: Any]
        let reload = gateway?["reload"] as? [String: Any]
        let deferral = reload?["deferralTimeoutMs"]
        let deferralOK: Bool
        if let n = deferral as? Int {
            deferralOK = n == deferralTimeoutMs
        } else if let n = deferral as? NSNumber {
            deferralOK = n.intValue == deferralTimeoutMs
        } else {
            deferralOK = false
        }
        return session?["dmScope"] as? String == dmScope
            && deferralOK
            && globalResetIsIdle(session)
            && channelOverridesAllowLongIdle(session)
    }

    @discardableResult
    static func apply(to dict: inout [String: Any]) -> Bool {
        let before = isSatisfied(dict)
        var session = dict["session"] as? [String: Any] ?? [:]
        session["dmScope"] = dmScope
        if !globalResetIsIdle(session) {
            var reset = session["reset"] as? [String: Any] ?? [:]
            reset["mode"] = sessionResetMode
            let minutes = idleMinutes(from: reset) ?? 0
            if minutes < sessionIdleMinutes {
                reset["idleMinutes"] = sessionIdleMinutes
            }
            session["reset"] = reset
        }
        session = upgradedChannelOverrides(session)
        dict["session"] = session

        var gateway = dict["gateway"] as? [String: Any] ?? [:]
        var reload = gateway["reload"] as? [String: Any] ?? [:]
        reload["deferralTimeoutMs"] = deferralTimeoutMs
        gateway["reload"] = reload
        dict["gateway"] = gateway
        return !before
    }

    /// True when inactivity will not archive the transcript. Windows longer
    /// than `sessionIdleMinutes` are left alone; shorter or daily policies
    /// are upgraded.
    static func globalResetIsIdle(_ session: [String: Any]?) -> Bool {
        let reset = session?["reset"] as? [String: Any]
        guard (reset?["mode"] as? String) == sessionResetMode else { return false }
        return (idleMinutes(from: reset) ?? 0) >= sessionIdleMinutes
    }

    static func idleMinutes(from reset: [String: Any]?) -> Int? {
        if let n = reset?["idleMinutes"] as? Int { return n }
        if let n = reset?["idleMinutes"] as? NSNumber { return n.intValue }
        return nil
    }

    /// Channel overrides win over `session.reset`. A leftover 7-day webchat
    /// policy would keep wiping Mac UI threads even after the global idle
    /// window is raised.
    static func channelOverridesAllowLongIdle(_ session: [String: Any]?) -> Bool {
        let byChannel = session?["resetByChannel"] as? [String: Any] ?? [:]
        for (_, raw) in byChannel {
            guard let policy = raw as? [String: Any] else { continue }
            let mode = policy["mode"] as? String
            if mode == "daily" { return false }
            if mode == sessionResetMode, (idleMinutes(from: policy) ?? 0) < sessionIdleMinutes {
                return false
            }
        }
        return true
    }

    static func upgradedChannelOverrides(_ session: [String: Any]) -> [String: Any] {
        guard let byChannel = session["resetByChannel"] as? [String: Any], !byChannel.isEmpty else {
            return session
        }
        var next = byChannel
        var changed = false
        for (channel, raw) in byChannel {
            guard var policy = raw as? [String: Any] else { continue }
            if (policy["mode"] as? String) == "daily" {
                policy["mode"] = sessionResetMode
                policy["idleMinutes"] = sessionIdleMinutes
                next[channel] = policy
                changed = true
                continue
            }
            if (policy["mode"] as? String) == sessionResetMode,
               (idleMinutes(from: policy) ?? 0) < sessionIdleMinutes {
                policy["idleMinutes"] = sessionIdleMinutes
                next[channel] = policy
                changed = true
            }
        }
        guard changed else { return session }
        var updated = session
        updated["resetByChannel"] = next
        return updated
    }

    static func hasDingTalk(_ dict: [String: Any]) -> Bool {
        let channels = dict["channels"] as? [String: Any] ?? [:]
        let plugins = ((dict["plugins"] as? [String: Any])?["entries"] as? [String: Any]) ?? [:]
        return dingtalkKeys.contains { channels[$0] != nil || plugins[$0] != nil }
    }
}

enum SessionIsolationBootstrapOutcome: Equatable {
    case alreadyCorrect
    case wroteConfigOnly
    case scheduled
    case deferred(activeCount: Int)
    case coalesced(activeCount: Int)
}

enum SessionIsolationBootstrap {
    static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw/openclaw.json")
    }

    /// One-shot per launch: write the isolation keys if needed. Restarts only
    /// via official `gateway restart --safe` when DingTalk is configured and
    /// the core supports it. Never force-kills a process.
    static func applyIfNeeded(
        configURL: URL = defaultConfigURL,
        runCommand: @escaping SafeGatewayRepairCoordinator.CommandRunner,
        waitForRecovery: @escaping SafeGatewayRepairCoordinator.RecoveryWaiter
    ) async -> SessionIsolationBootstrapOutcome {
        var dict: [String: Any] = [:]
        if let data = try? Data(contentsOf: configURL) {
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                // Unparseable config is not ours to rewrite; force-repair handles it.
                return .alreadyCorrect
            }
            dict = parsed
        } else {
            return .alreadyCorrect
        }

        let changed = SessionIsolationConfig.apply(to: &dict)
        if changed {
            if let data = try? JSONSerialization.data(
                withJSONObject: dict,
                options: [.prettyPrinted, .sortedKeys]
            ) {
                try? data.write(to: configURL, options: .atomic)
            }
        } else {
            return .alreadyCorrect
        }

        guard SessionIsolationConfig.hasDingTalk(dict) else {
            return .wroteConfigOnly
        }

        let version = await runCommand(SafeGatewayRepairCommands.version, 15)
        let restartHelp = await runCommand(SafeGatewayRepairCommands.restartHelp, 15)
        let capability = SafeGatewayRepairCapability.evaluate(
            versionOutput: version,
            restartHelpOutput: restartHelp
        )
        if case .upgradeRequired = capability {
            return .wroteConfigOnly
        }

        let coordinator = SafeGatewayRepairCoordinator(
            runCommand: runCommand,
            waitForRecovery: waitForRecovery
        )
        switch await coordinator.repair() {
        case .scheduled:
            return .scheduled
        case .deferred(let count):
            return .deferred(activeCount: count)
        case .coalesced(let count):
            return .coalesced(activeCount: count)
        case .upgradeRequired:
            return .wroteConfigOnly
        case .configurationFailed, .safeRestartFailed, .recoveryVerificationFailed:
            return .wroteConfigOnly
        }
    }
}

enum SafeGatewayChannelVerification {
    static func isDingTalkReady(_ output: String?) -> Bool {
        guard let output else { return false }
        for line in output.components(separatedBy: .newlines) {
            let normalized = line
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard normalized.hasPrefix("- dingtalk ")
                || normalized.hasPrefix("- dingtalk-connector ") else { continue }
            return normalized.contains("enabled")
                && normalized.contains("configured")
                && !normalized.contains("not configured")
                && !normalized.contains("not linked")
                && !normalized.contains("disconnected")
                && !normalized.contains("error:")
        }
        return false
    }
}
