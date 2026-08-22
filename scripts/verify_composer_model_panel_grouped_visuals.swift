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
    guard condition else { fatalError(message) }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let dashboard = ["OpenClawInstaller/Features/Dashboard/DashboardTypography.swift", "OpenClawInstaller/Features/Dashboard/DashboardView.swift", "OpenClawInstaller/Features/Dashboard/Sidebar/DashboardSidebar.swift", "OpenClawInstaller/Features/Chat/Views/ChatView.swift", "OpenClawInstaller/Features/Chat/Views/ComposerChrome.swift", "OpenClawInstaller/Features/Chat/Views/ChatBubbleViews.swift", "OpenClawInstaller/Features/Agents/Views/AgentSettingsPanel.swift", "OpenClawInstaller/Features/Dashboard/TerminalPanel.swift", "OpenClawInstaller/Features/Sessions/Views/SessionDetailsPanel.swift"].map(read).joined(separator: "\n")
let panel = slice(
    dashboard,
    from: "struct ComposerModelPanel: View",
    to: "private extension View"
)

require(
    !panel.contains("Default (") && !panel.contains(#"subtitle: "Inherit""#),
    "composer model panel must not render a Default/Inherit row"
)
require(
    panel.contains("effectiveSelectedModel"),
    "composer model panel must compute an effective selected model from current model or default model"
)
require(
    panel.contains("selected: model.runtimeId == effectiveSelectedModel"),
    "composer model rows must show the default model as selected when the agent inherits it"
)
require(
    !panel.contains("resetToDefault") && !panel.contains(#"Image(systemName: "arrow.counterclockwise")"#),
    "composer model panel must not expose reset-to-empty/default controls"
)
require(
    !panel.contains(#".help("Use Default")"#),
    "composer model panel must not expose Use Default affordances"
)
require(
    !panel.contains("providerSubtitle("),
    "Custom group rows must not show underlying provider-key subtitles"
)
require(
    panel.contains("sectionHeader(for: group)"),
    "composer model panel must render stronger provider headers without card containers"
)
require(
    panel.contains("Divider()"),
    "provider groups should be visually separated by lightweight dividers"
)

print("Composer model panel grouped visual verification passed")
