#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboardURL = root.appendingPathComponent("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let dashboard = try String(contentsOf: dashboardURL, encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

func slice(_ source: String, from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        return ""
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

let chatView = slice(
    dashboard,
    from: "struct ChatView: View",
    to: "// MARK: - Typewriter Text for Streaming"
)
let chatBody = slice(
    chatView,
    from: "var body: some View",
    to: ".background(Color(NSColor.windowBackgroundColor))"
)
let composerArea = slice(
    dashboard,
    from: "private func composerArea(maxWidth: CGFloat, horizontalPadding: CGFloat, bottomPadding: CGFloat) -> some View",
    to: "private var composerFloatingPanels: some View"
)
let suggestionOverlay = slice(
    dashboard,
    from: "private func composerSuggestionOverlay(anchor: Anchor<CGRect>?) -> some View",
    to: "private func composerSelectorOverlay(anchor: Anchor<CGRect>?) -> some View"
)
let composerFloatingPanels = slice(
    dashboard,
    from: "private var composerFloatingPanels: some View",
    to: "@ViewBuilder\n    private var composerSuggestionPanels: some View"
)
let slashCommandPanel = slice(
    dashboard,
    from: "private var slashCommandPanel: some View",
    to: "private var skillsPanel: some View"
)
let skillsPanel = slice(
    dashboard,
    from: "private var skillsPanel: some View",
    to: "private var agentMentionPanel: some View"
)
let agentMentionPanel = slice(
    dashboard,
    from: "private var agentMentionPanel: some View",
    to: "private var composerInputCard: some View"
)

require(dashboard.contains(#"SlashCommand(id: "/help""#), "slash commands should still include /help")
require(dashboard.contains("private var showSlashPanel: Bool"), "chat view should still compute slash panel visibility")
require(dashboard.contains("private var showSkillsPanel: Bool"), "chat view should still compute skills panel visibility")
require(dashboard.contains("private var showAgentPanel: Bool"), "chat view should still compute agent mention panel visibility")

require(dashboard.contains("private struct ComposerInputCardBoundsKey: PreferenceKey"), "composer suggestions need a root-level input-card anchor")
require(chatBody.contains(".overlayPreferenceValue(ComposerInputCardBoundsKey.self)"), "chat root should render composer suggestions from an overlay preference")
require(chatBody.contains("composerSuggestionOverlay(anchor: anchor)"), "chat root should call composerSuggestionOverlay")
require(composerArea.contains(".anchorPreference(key: ComposerInputCardBoundsKey.self, value: .bounds)"), "composer input card should publish its bounds for suggestion positioning")
require(!composerArea.contains("composerFloatingPanels"), "composer input card should not own suggestion panels locally")

require(suggestionOverlay.contains("if let anchor, showComposerSuggestions"), "suggestion overlay should render only when slash/skills/agent panels are visible")
require(suggestionOverlay.contains("let inputFrame = proxy[anchor]"), "suggestion overlay should position from the composer input frame")
require(suggestionOverlay.contains("composerFloatingPanels"), "suggestion overlay should render the existing slash/skills/agent panels")
require(suggestionOverlay.contains("let panelTopOffset = max(12, inputFrame.minY - composerSuggestionPanelMaxHeight - 8)"), "suggestion overlay should sit just above the composer input")
require(suggestionOverlay.contains("ZStack(alignment: .topLeading)"), "suggestion overlay should position from the top-leading coordinate space")
require(suggestionOverlay.contains(".frame(width: inputFrame.width)"), "suggestion overlay should align to the composer input width")
require(suggestionOverlay.contains(".offset(x: inputFrame.minX, y: panelTopOffset)"), "suggestion overlay should align to the composer input left edge")
require(!suggestionOverlay.contains("trailingOffset"), "suggestion overlay should not use right-edge offset positioning")
require(!suggestionOverlay.contains("bottomOffset"), "suggestion overlay should not use bottom-edge offset positioning")
require(dashboard.contains("private let composerSuggestionPanelMaxHeight: CGFloat = 184"), "composer suggestions should have a compact max height near the input")
require(suggestionOverlay.contains("maxHeight: composerSuggestionPanelMaxHeight"), "suggestion overlay should constrain panel height near the composer")
require(slashCommandPanel.contains(".frame(maxHeight: composerSuggestionPanelMaxHeight)"), "slash command panel should use the compact suggestion height")
require(skillsPanel.contains(".frame(maxHeight: composerSuggestionPanelMaxHeight)"), "skills panel should use the compact suggestion height")
require(agentMentionPanel.contains(".frame(maxHeight: composerSuggestionPanelMaxHeight)"), "agent mention panel should use the compact suggestion height")
require(!chatView.contains(".frame(maxHeight: 280)"), "composer suggestion panels should no longer jump high with a 280-point max height")
require(dashboard.contains("private var composerSuggestionSelectedBackground: SwiftUI.Color"), "composer suggestions should share a gray selected-row background")
require(slashCommandPanel.contains("composerSuggestionSelectedBackground"), "slash command selection should use the shared gray background")
require(skillsPanel.contains("composerSuggestionSelectedBackground"), "skills selection should use the shared gray background")
require(agentMentionPanel.contains("composerSuggestionSelectedBackground"), "agent mention selection should use the shared gray background")
require(!slashCommandPanel.contains("Color.accentColor"), "slash command selection should not use blue accent color")
require(!skillsPanel.contains("Color.accentColor"), "skills selection should not use blue accent color")
require(!agentMentionPanel.contains("Color.accentColor"), "agent mention selection should not use blue accent color")
require(!slashCommandPanel.contains("? .white"), "slash command selected text should not turn white")
require(!skillsPanel.contains("? .white"), "skills selected text should not turn white")
require(!agentMentionPanel.contains("? .white"), "agent mention selected text should not turn white")

require(composerFloatingPanels.contains("showSlashPanel || showSkillsPanel || showAgentPanel"), "floating panels should still be hit-test gated by visibility")

print("PASS: composer slash, skills, and agent suggestions render from root overlay")
