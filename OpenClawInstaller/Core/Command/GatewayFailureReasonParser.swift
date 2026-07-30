import Foundation

/// Turns gateway log text into the one sentence that explains why it is down.
///
/// Extracted from `OpenClawService` so the marker set can be tested directly. It
/// earned its own tests after a real failure: a gateway killed by the core's Node
/// version guard produced NO user-visible reason, because the guard writes
///
///     openclaw: Node.js >=22.22.3 <23, >=24.15.0 <25, or >=25.9.0 is required (current: v25.3.0).
///
/// and every marker in the original set ("Invalid config", "Reason:", "refusing",
/// "failed to") missed it. The user saw only "网关启动失败".
enum GatewayFailureReasonParser {
    /// Substrings that mark a line as stating a cause. Ordering does not matter;
    /// the scan runs newest-line-first regardless.
    static let causeMarkers = [
        // Config and service refusals.
        "Invalid config",
        "Reason:",
        "refusing",
        "Refusing",
        "not allowed",
        "failed to",
        "Failed to",
        // The core's runtime guard (openclaw.mjs: ensureSupportedRuntimeVersion).
        // It exits(1) before the port is bound, so it is a leading cause of a
        // gateway that "starts" and immediately disappears.
        "is required (current:",
        "Node.js",
        "runtime is unsupported",
    ]

    /// The newest line that states a cause, cleaned up for display.
    /// `nil` when nothing in the text explains a failure.
    static func firstCause(inLogText text: String) -> String? {
        let candidate = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .reversed()
            .first { line in causeMarkers.contains { line.contains($0) } }
        guard let candidate else { return nil }
        return present(String(candidate))
    }

    /// Markers unique to the core's runtime guard. Narrower than `causeMarkers`
    /// on purpose: this is applied to the output of a command we ran ourselves, so
    /// it must only fire on a genuine runtime refusal and leave config complaints
    /// to the config probe.
    private static let runtimeRefusalMarkers = [
        "is required (current:",
        "runtime is unsupported",
    ]

    /// The runtime refusal in `output`, if the launcher refused to run at all.
    /// `nil` when the launcher ran fine or failed for some other reason.
    static func unsupportedRuntimeCause(inOutput output: String) -> String? {
        let candidate = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first { line in runtimeRefusalMarkers.contains { line.contains($0) } }
        guard let candidate else { return nil }
        return present(String(candidate))
    }

    /// Strip the leading ISO timestamp, collapse the escaped newlines the gateway
    /// writes, and cap the length so a chatty log does not become a wall of UI text.
    private static func present(_ raw: String) -> String {
        var reason = raw
        if let range = reason.range(of: "] ") {
            reason = String(reason[range.upperBound...])
        }
        reason = reason
            .replacingOccurrences(of: "\\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.count > 300 ? String(reason.prefix(300)) + "…" : reason
    }
}
