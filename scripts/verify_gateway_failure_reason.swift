import Foundation

// A gateway that will not serve must say WHY.
//
// Until 2026-07-28 the UI said "not running" and nothing else, so a config the
// core rejects (field, 2026-07-27: a locally path-installed plugin whose entry
// "escapes package directory") looked like a silent restart loop and took three
// log files to diagnose. Everything asserted here was learned by reproducing
// that failure, not by reading the code:
//
//   * The gateway's fatal reason is usually NOWHERE. The LaunchAgent installed
//     by current cores sets StandardErrorPath to /dev/null — measured on two
//     machines — so stdout only ever shows "loading configuration…" on repeat.
//     Hence the live `config validate` fallback: ask, do not search.
//   * A crash-looping gateway is mostly sampled as STOPPED, not as error, so
//     attaching the reason only to the "PID but no port" path missed it.
//   * `checkStatus` cleared `lastError` for every status that was not `.error`,
//     wiping the explanation moments after it was set.

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
        fputs("FAIL: could not read \(path)\n", stderr)
        exit(1)
    }
    return text
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let service = read("OpenClawInstaller/Core/Command/OpenClawService.swift")
let dashboard = ["OpenClawInstaller/Features/Dashboard/DashboardTypography.swift", "OpenClawInstaller/Features/Dashboard/DashboardView.swift", "OpenClawInstaller/Features/Dashboard/Sidebar/DashboardSidebar.swift", "OpenClawInstaller/Features/Chat/Views/ChatView.swift", "OpenClawInstaller/Features/Chat/Views/ComposerChrome.swift", "OpenClawInstaller/Features/Chat/Views/ChatBubbleViews.swift", "OpenClawInstaller/Features/Agents/Views/AgentSettingsPanel.swift", "OpenClawInstaller/Features/Dashboard/TerminalPanel.swift", "OpenClawInstaller/Features/Sessions/Views/SessionDetailsPanel.swift"].map(read).joined(separator: "\n")

// --- The reason has three sources, in order ---
require(
    service.contains("static func lastGatewayFailureReason() -> String?"),
    "the service should be able to explain a gateway that is not serving"
)
require(
    service.contains("StandardErrorPath") && service.contains("StandardOutPath"),
    "log locations must come from the LaunchAgent plist — cores disagree about where they write"
)
require(
    service.contains("value != \"/dev/null\""),
    "a /dev/null redirect is not a log file and must be skipped"
)
require(
    service.contains("private static func configValidationComplaint"),
    "with stderr discarded the reason exists nowhere, so the config must be validated live rather than searched for"
)
require(
    service.contains("config validate 2>&1 || true"),
    "the validator's verdict is in its output; it exits non-zero exactly when the config is invalid"
)

// --- Attached on the path a crash loop is actually sampled on ---
require(
    service.contains("if Self.isLaunchAgentInstalled() {"),
    "a gateway that SHOULD be running (agent installed) but is stopped must carry a reason"
)
require(
    service.contains("lastError = Self.lastGatewayFailureReason()"),
    "the stopped path must populate the reason"
)

// --- And not wiped again on the way out ---
guard let clearRange = service.range(of: "lastError = nil") else {
    fputs("FAIL: could not find where lastError is cleared\n", stderr)
    exit(1)
}
let clearContext = String(service[..<clearRange.lowerBound].suffix(220))
require(
    clearContext.contains("if status == .running"),
    "only a healthy gateway clears the reason — clearing on every non-.error status wiped it moments after it was set"
)

// --- And it reaches the user ---
require(
    dashboard.contains("var failureReason: String? = nil"),
    "the status badge should be able to show the reason"
)
require(
    dashboard.contains("failureReason: state.serviceFailureReason"),
    "the sidebar must pass the reason into the badge"
)
require(
    dashboard.contains("viewModel.openclawService.status == .running")
        && dashboard.contains("viewModel.openclawService.lastError"),
    "the reason is shown only while the gateway is unhealthy"
)

print("gateway failure-reason guards hold")
