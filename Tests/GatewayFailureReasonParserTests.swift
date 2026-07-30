import Foundation

// When the gateway will not boot, the UI has exactly one job: say why. The
// reported failure — "upgrade succeeded, gateway will not start, it needs a
// newer Node" — produced no reason at all, because the core's Node guard writes
//
//     openclaw: Node.js >=22.22.3 <23, >=24.15.0 <25, or >=25.9.0 is required (current: v25.3.0).
//
// and none of the parser's markers matched that sentence. These cases pin the
// causes the parser must recognise.

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
private enum GatewayFailureReasonParserTests {
    static func main() throws {
        try recognisesTheNodeVersionGuard()
        try recognisesUnsupportedRuntimeComplaints()
        try stillRecognisesConfigFailures()
        try prefersTheMostRecentCause()
        try stripsTimestampsAndCollapsesEscapedNewlines()
        try truncatesRunawayLines()
        try returnsNilWhenNothingExplainsAnything()
        try readsTheRuntimeGuardOutOfLauncherOutput()

        print("PASS: gateway failure reason parser")
    }

    // MARK: - The reported failure

    private static func recognisesTheNodeVersionGuard() throws {
        let log = """
        [2026-07-30T09:12:04.001Z] loading configuration…
        openclaw: Node.js >=22.22.3 <23, >=24.15.0 <25, or >=25.9.0 is required (current: v25.3.0).
        """

        let reason = GatewayFailureReasonParser.firstCause(inLogText: log)
        try expect(reason != nil, "the Node version guard is the whole reason the gateway exited; it must be reported")
        try expect(
            reason?.contains("Node.js") == true && reason?.contains("v25.3.0") == true,
            "the reason must name both the requirement and the Node actually installed, got: \(reason ?? "nil")"
        )
    }

    private static func recognisesUnsupportedRuntimeComplaints() throws {
        // The same guard, other branches of it.
        let bun = "openclaw: the Bun runtime is unsupported because OpenClaw requires node:sqlite."
        try expect(
            GatewayFailureReasonParser.firstCause(inLogText: bun) != nil,
            "an unsupported runtime must be reported, not swallowed"
        )

        let nvmHint = """
        openclaw: Node.js >=24.15.0 <25 is required (current: v24.14.0).
        If you use nvm, run:
          nvm install 24
        """
        let reason = GatewayFailureReasonParser.firstCause(inLogText: nvmHint)
        try expect(
            reason?.contains("is required") == true,
            "the requirement sentence must win over the nvm instructions that follow it, got: \(reason ?? "nil")"
        )
    }

    // MARK: - Existing behaviour must not regress

    private static func stillRecognisesConfigFailures() throws {
        let cases = [
            "[2026-07-27T10:00:00.000Z] Invalid config at plugins.local: entry escapes package directory",
            "Refusing to install or rewrite the gateway service because this OpenClaw binary is older",
            "failed to bind port 18789",
            "Reason: address already in use",
        ]
        for line in cases {
            try expect(
                GatewayFailureReasonParser.firstCause(inLogText: line) != nil,
                "previously recognised cause stopped being recognised: \(line)"
            )
        }
    }

    private static func prefersTheMostRecentCause() throws {
        let log = """
        Invalid config at plugins.old: stale complaint from an earlier boot
        loading configuration…
        openclaw: Node.js >=24.15.0 <25 is required (current: v25.4.0).
        """
        let reason = GatewayFailureReasonParser.firstCause(inLogText: log)
        try expect(
            reason?.contains("Node.js") == true,
            "the newest cause describes why the gateway is down NOW, got: \(reason ?? "nil")"
        )
    }

    // MARK: - Formatting

    private static func stripsTimestampsAndCollapsesEscapedNewlines() throws {
        let log = #"[2026-07-30T09:12:04.001Z] Invalid config\nat gateway.port\nexpected number"#
        let reason = GatewayFailureReasonParser.firstCause(inLogText: log)
        try expect(
            reason?.hasPrefix("Invalid config") == true,
            "the ISO timestamp must be stripped, got: \(reason ?? "nil")"
        )
        try expect(
            reason?.contains("\\n") == false,
            "escaped newlines must collapse into one readable sentence, got: \(reason ?? "nil")"
        )
    }

    private static func truncatesRunawayLines() throws {
        let long = "Invalid config " + String(repeating: "x", count: 5_000)
        let reason = GatewayFailureReasonParser.firstCause(inLogText: long)
        try expect(reason != nil, "a long cause is still a cause")
        try expect(
            (reason?.count ?? 0) <= 301,
            "a chatty log must not become a wall of UI text, got \(reason?.count ?? 0) characters"
        )
    }

    // MARK: - Asking the launcher directly

    private static func readsTheRuntimeGuardOutOfLauncherOutput() throws {
        // The guard fires before argument handling, so even `--version` trips it.
        let refused = """
        openclaw: Node.js >=22.22.3 <23, >=24.15.0 <25, or >=25.9.0 is required (current: v25.3.0).
        If you use nvm, run:
          nvm install 24
        """
        let cause = GatewayFailureReasonParser.unsupportedRuntimeCause(inOutput: refused)
        try expect(cause != nil, "a launcher that refuses the installed Node must yield a reportable cause")
        try expect(
            cause?.contains("v25.3.0") == true,
            "the cause must name the Node actually installed so the user can act, got: \(cause ?? "nil")"
        )

        // A healthy launcher just prints its version — that is NOT a failure.
        try expect(
            GatewayFailureReasonParser.unsupportedRuntimeCause(inOutput: "2026.7.1-2") == nil,
            "a launcher that runs fine must not be reported as a runtime failure"
        )
        try expect(
            GatewayFailureReasonParser.unsupportedRuntimeCause(inOutput: "") == nil,
            "no output is not evidence of a runtime failure"
        )
        // Config complaints belong to the config probe, not this one.
        try expect(
            GatewayFailureReasonParser.unsupportedRuntimeCause(inOutput: "Invalid config at gateway.port") == nil,
            "a config complaint must not be misreported as an unsupported runtime"
        )
    }

    private static func returnsNilWhenNothingExplainsAnything() throws {
        let log = """
        [2026-07-30T09:12:04.001Z] loading configuration…
        [2026-07-30T09:12:05.001Z] gateway listening on 18789
        """
        try expect(
            GatewayFailureReasonParser.firstCause(inLogText: log) == nil,
            "a healthy log must not be mined for a fake reason"
        )
        try expect(
            GatewayFailureReasonParser.firstCause(inLogText: "") == nil,
            "an empty log has no cause"
        )
    }
}
