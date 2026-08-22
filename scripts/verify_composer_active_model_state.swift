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
let viewModel = read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")
let helpers = read("OpenClawInstaller/Features/Chat/ChatHelpers.swift")
let gateway = read("OpenClawInstaller/Core/Gateway/GatewayClient.swift")
let agentSettings = read("OpenClawInstaller/Features/Agents/Core/AgentSettings.swift")
let providerSettings = read("OpenClawInstaller/Features/Settings/ProviderModels/ProviderModelSettings.swift")

let composerOverlay = slice(
    dashboard,
    from: "ComposerModelPanel(",
    to: "                    .fixedSize(horizontal: true, vertical: false)"
)
let selectorButton = slice(
    dashboard,
    from: "struct ComposerModelSelector: View",
    to: "struct ComposerModelPanel: View"
)
let selectorPanel = slice(
    dashboard,
    from: "struct ComposerModelPanel: View",
    to: "private extension View"
)
let chatSendMethod = slice(
    gateway,
    from: "func chatSend(",
    to: "    /// Subscribe to one run's chat events plus shared transport lifecycle."
)
let sendChatMessage = slice(
    helpers,
    from: "func sendChatMessage(_ text: String, attachments: [URL] = []) async",
    to: "    /// Move a foreground task to background"
)
let updateAgentModel = slice(
    agentSettings,
    from: "func updateAgentModel(model: String)",
    to: "    /// Binding for editing a persona file"
)
let switchSession = slice(
    viewModel,
    from: "func switchSession(to sessionId: UUID)",
    to: "    func switchSession(to sessionId: UUID, inAgent agentId: String)"
)
let switchSessionGlobally = slice(
    viewModel,
    from: "func switchSessionGlobally(to sessionId: UUID)",
    to: "    func switchSession(to sessionId: UUID, inAgent agentId: String)"
)

require(
    viewModel.contains("var activeComposerModel: String") &&
        viewModel.contains("modelSettingsViewModel.activeComposerModel"),
    "DashboardViewModel must own an app-level activeComposerModel for composer selection"
)
require(
    viewModel.contains("func selectComposerModel(_ model: String)") ||
        providerSettings.contains("func selectComposerModel(_ model: String)"),
    "DashboardViewModel must expose a composer-only model selection method"
)
require(
    !slice(
        providerSettings,
        from: "func selectComposerModel(_ model: String)",
        to: "    private func modelOptions("
    ).contains("patchAgentModel"),
    "selectComposerModel must not write agent model configuration"
)
require(
    updateAgentModel.contains("patchAgentModel"),
    "updateAgentModel must remain the agent-settings JSON writer"
)
require(
    composerOverlay.contains("currentModel: viewModel.activeComposerModel"),
    "composer panel must read the active composer model, not the selected agent model"
)
require(
    composerOverlay.contains("onSelectModel: viewModel.selectComposerModel"),
    "composer panel must write through selectComposerModel, not updateAgentModel"
)
require(
    selectorButton.contains("viewModel.activeComposerModel"),
    "composer selector button must display the active composer model"
)
require(
    !selectorButton.contains("currentAgent?.model"),
    "composer selector button must not read the current agent model"
)
require(
    !dashboard.contains("private var composerCurrentModel"),
    "DashboardView must not keep a composerCurrentModel computed from selected agent"
)
require(
    !selectorPanel.contains(#"Image(systemName: "arrow.counterclockwise")"#) &&
        !selectorPanel.contains("resetToDefault") &&
        !selectorPanel.contains(#".help("Use Default")"#),
    "composer model panel must not expose a reset-to-empty/default action"
)
require(
    gateway.contains("func patchSessionModel(sessionKey: String, model: String) async -> Bool"),
    "GatewayClient must patch a session-only model override before chat.send"
)
require(
    gateway.contains(#""method": "sessions.patch""#) &&
        gateway.contains(#""key": sessionKey"#) &&
        gateway.contains(#""model": trimmedModel"#),
    "GatewayClient.patchSessionModel must call sessions.patch with key and model"
)
require(
    !chatSendMethod.contains(#"params["model"]"#) &&
        !chatSendMethod.contains(#"params["modelId"]"#) &&
        !chatSendMethod.contains(#"params["provider"]"#),
    "GatewayClient must not send unsupported model fields through chat.send params"
)
require(
    sendChatMessage.contains("let composerModelOverride = activeComposerModel.trimmingCharacters(in: .whitespacesAndNewlines)") &&
        sendChatMessage.contains("gatewayClient.patchSessionModel(sessionKey: sessionKey, model: composerModelOverride)"),
    "sendChatMessage must apply activeComposerModel through sessions.patch before chat.send"
)
require(
    !switchSession.contains("activeComposerModel") && !switchSessionGlobally.contains("activeComposerModel"),
    "session switching must not reset or rewrite the active composer model"
)

print("Composer active model state verification passed")
