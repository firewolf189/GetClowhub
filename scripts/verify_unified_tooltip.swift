#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let tooltip = read("OpenClawInstaller/Views/Shared/UnifiedTooltip.swift")
let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let workspaceInspector = read("OpenClawInstaller/Views/Dashboard/Inspector/WorkspaceInspectorPane.swift")
let skills = read("OpenClawInstaller/Views/Dashboard/Skills/SkillsTabView.swift")
let plugins = read("OpenClawInstaller/Views/Dashboard/Plugins/PluginsTabView.swift")
let logs = read("OpenClawInstaller/Views/Dashboard/LogsTabView.swift")
let models = read("OpenClawInstaller/Views/Dashboard/ModelsTabView.swift")
let helpAssistant = read("OpenClawInstaller/Views/Dashboard/HelpAssistantWindow.swift")
let cron = read("OpenClawInstaller/Views/Dashboard/CronTabView.swift")
let budget = read("OpenClawInstaller/Views/Dashboard/BudgetTabView.swift")
let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")

require(
    tooltip.contains("struct UnifiedTooltipContent") &&
        tooltip.contains("struct UnifiedTooltipModifier") &&
        tooltip.contains("func unifiedTooltip(") &&
        tooltip.contains("func unifiedIconTooltip("),
    "UnifiedTooltip.swift should own the reusable tooltip data model, modifier, and icon-button helpers."
)
require(
    tooltip.contains("NSViewRepresentable") &&
        tooltip.contains("NSPanel(") &&
        tooltip.contains("orderFrontRegardless()") &&
        tooltip.contains("parent window clipping") &&
        tooltip.contains(".onHover { hovering in") &&
        tooltip.contains("DispatchQueue.main.async(execute: work)"),
    "Unified tooltip should render in a small AppKit panel outside parent window clipping and present immediately."
)
require(
    tooltip.contains(".accessibilityLabel(self.content.title)") &&
        tooltip.contains(".background(Color.white)") &&
        tooltip.contains(".font(.system(size: 13, weight: .regular))") &&
        tooltip.contains(".padding(.horizontal, 9)") &&
        !tooltip.contains(".shadow(") &&
        !tooltip.contains("withAnimation(") &&
        !tooltip.contains(".transition(") &&
        !tooltip.contains(".ultraThinMaterial"),
    "Unified tooltip should preserve accessibility, use compact white styling, and avoid shadows, animations, or material backgrounds."
)
require(
    project.contains("UnifiedTooltip.swift in Sources") &&
        project.contains("UnifiedTooltip.swift"),
    "Xcode project should include UnifiedTooltip.swift in the Shared group and app target sources."
)

let inspectorToolbar = slice(
    dashboard,
    from: "private struct RightOutputsTitlebarAccessory: View",
    to: "struct SidebarView: View"
)
require(
    inspectorToolbar.contains("unifiedIconTooltip(") &&
        inspectorToolbar.contains(#"title: isTerminalOpen ? "Hide Terminal" : "Show Terminal""#) &&
        inspectorToolbar.contains(#"title: isExpanded ? "Hide Outputs" : "Show Outputs""#),
    "Inspector toolbar terminal and outputs buttons should use unified icon tooltips."
)

let sidebar = slice(
    dashboard,
    from: "struct SidebarView: View",
    to: "struct SidebarCollapsibleRow"
)
let agentSection = slice(
    dashboard,
    from: "private var agentSectionContent: some View",
    to: "// MARK: - Sidebar Bottom Bar"
)
require(
    sidebar.contains(".unifiedTooltip(UnifiedTooltipContent(") &&
        sidebar.contains(#"title: String(localized: "New Agent""#) &&
        sidebar.contains("dashboard.agent.addWorkFolder") &&
        sidebar.contains(#"title: String(localized: "New chat""#),
    "Sidebar agent controls should use unified tooltip content."
)
require(
    !agentSection.contains(#"String(localized: "Show agents""#) &&
        !agentSection.contains(#"String(localized: "Hide agents""#) &&
        agentSection.contains(#"title: String(localized: "New Agent""#),
    "Agent section header should not show a tooltip; only the explicit New Agent button should keep one."
)

let composerSelector = slice(
    dashboard,
    from: "struct ComposerModelSelector: View",
    to: "private struct ComposerModelPanel: View"
)
require(
    composerSelector.contains(".unifiedTooltip(UnifiedTooltipContent(") &&
        composerSelector.contains(#"title: "Choose model""#),
    "Composer model selector should use the unified tooltip modifier."
)

let hoverActionButton = slice(
    dashboard,
    from: "struct MessageActionIcon: View",
    to: "struct ChatBubble: View"
)
require(
    hoverActionButton.contains("UnifiedTooltipContent(title: help)") &&
        hoverActionButton.contains(".unifiedTooltip(") &&
        !hoverActionButton.contains("tooltipTask") &&
        !hoverActionButton.contains("showTooltip"),
    "Chat hover action buttons should delegate tooltip rendering to UnifiedTooltip instead of owning local tooltip state."
)

let attachments = slice(
    dashboard,
    from: "struct AttachmentPreview: View",
    to: "struct SuccessToast: View"
)
require(
    attachments.contains(#"title: "Remove attachment""#) &&
        attachments.contains(".unifiedTooltip("),
    "Attachment remove buttons should use unified tooltips."
)

require(
    workspaceInspector.contains("WorkspaceHeaderIconButton(action: openFolder") &&
        workspaceInspector.contains(".unifiedTooltip(") &&
        workspaceInspector.contains("workspace.files.decreaseFont") &&
        workspaceInspector.contains("workspace.files.enableWordWrap") &&
        workspaceInspector.contains("workspace.files.copyPathHelp"),
    "Workspace inspector icon controls should use unified tooltip styling."
)

require(
    skills.contains(".unifiedTooltip(UnifiedTooltipContent(title: I18n.t(\"skills.help.refresh\")))") &&
        skills.contains(".unifiedTooltip(UnifiedTooltipContent(title: I18n.t(\"catalog.action.install\")))") &&
        skills.contains(".unifiedTooltip(UnifiedTooltipContent(title: I18n.t(\"catalog.action.close\")))"),
    "Skills icon controls should use unified tooltip styling."
)
require(
    plugins.contains(".unifiedTooltip(UnifiedTooltipContent(title: I18n.t(\"plugins.help.updateInstalled\")))") &&
        plugins.contains(".unifiedTooltip(UnifiedTooltipContent(title: I18n.t(\"plugins.help.installCustom\")))") &&
        plugins.contains(".unifiedTooltip(UnifiedTooltipContent(title: I18n.t(\"plugins.help.refresh\")))") &&
        plugins.contains(".unifiedTooltip(UnifiedTooltipContent(title: I18n.t(\"catalog.action.install\")))"),
    "Plugins icon controls should use unified tooltip styling."
)
require(
    logs.contains(#"title: I18n.t("common.action.clear", fallback: "Clear")"#) &&
        models.contains(#"title: I18n.t("dashboard.models.action.remove", fallback: "Remove model")"#) &&
        helpAssistant.contains(#"title: I18n.t("common.action.send")"#) &&
        cron.contains(".unifiedTooltip(UnifiedTooltipContent(title: job.enabled ? I18n.t(\"catalog.action.disable\") : I18n.t(\"catalog.action.enable\")))") &&
        budget.contains(".unifiedTooltip(UnifiedTooltipContent(title: String(localized: \"Refresh\", bundle: LanguageManager.shared.localizedBundle)))"),
    "Secondary tab icon controls should use unified tooltip styling."
)

print("Unified tooltip verification passed")
