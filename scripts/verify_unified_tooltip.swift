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

func jsonObject(_ path: String) -> [String: String] {
    let data = Data(read(path).utf8)
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
        fatalError("Invalid JSON string object in \(path)")
    }
    return json
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let tooltip = read("OpenClawInstaller/DesignSystem/Components/UnifiedTooltip.swift")
let dashboard = read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let workspaceInspector = read("OpenClawInstaller/Features/Workspace/Views/Inspector/WorkspaceInspectorPane.swift")
let rightInspectorTitlebarAccessory = read("OpenClawInstaller/Features/Workspace/Views/Inspector/RightInspectorTitlebarAccessory.swift")
let skills = read("OpenClawInstaller/Features/Skills/Views/SkillsTabView.swift")
let plugins = read("OpenClawInstaller/Features/Plugins/Views/PluginsTabView.swift")
let logs = read("OpenClawInstaller/Features/Status/Views/LogsTabView.swift")
let models = read("OpenClawInstaller/Features/Settings/ProviderModels/ModelsTabView.swift")
let helpAssistant = read("OpenClawInstaller/Features/Help/Views/HelpAssistantWindow.swift")
let cron = read("OpenClawInstaller/Features/Cron/Views/CronTabView.swift")
let budget = read("OpenClawInstaller/Features/Budget/Views/BudgetTabView.swift")
let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")
let zhHansCommon = jsonObject("OpenClawInstaller/Resources/I18n/zh-Hans/common.json")
let zhHantCommon = jsonObject("OpenClawInstaller/Resources/I18n/zh-Hant/common.json")
let enCommon = jsonObject("OpenClawInstaller/Resources/I18n/en/common.json")
let zhHansSettings = jsonObject("OpenClawInstaller/Resources/I18n/zh-Hans/settings.json")
let zhHantSettings = jsonObject("OpenClawInstaller/Resources/I18n/zh-Hant/settings.json")

require(
    tooltip.contains("struct UnifiedTooltipContent") &&
        tooltip.contains("enum UnifiedTooltipPlacement") &&
        tooltip.contains("struct UnifiedTooltipModifier") &&
        tooltip.contains("func unifiedTooltip(") &&
        tooltip.contains("func unifiedIconTooltip(") &&
        tooltip.contains("func unifiedTitlebarTooltip("),
    "UnifiedTooltip.swift should own the reusable tooltip data model, modifier, and icon-button helpers."
)
require(
    tooltip.contains("private final class UnifiedTooltipPresenter") &&
        tooltip.contains("static let shared = UnifiedTooltipPresenter()") &&
        tooltip.contains("private struct UnifiedTooltipAnchor: NSViewRepresentable") &&
        tooltip.contains("private final class UnifiedTooltipAnchorView: NSView") &&
        tooltip.contains("private var panel: NSPanel?") &&
        tooltip.contains("private var hostingController: NSHostingController<UnifiedTooltipBubble>?") &&
        tooltip.contains("UnifiedTooltipPresenter.shared.show(") &&
        tooltip.contains("UnifiedTooltipPresenter.shared.hide("),
    "Unified tooltip should centralize panel ownership in one presenter and keep per-control SwiftUI attachments as lightweight anchors."
)
let modifierSection = slice(
    tooltip,
    from: "struct UnifiedTooltipModifier: ViewModifier",
    to: "private struct UnifiedTooltipAnchor"
)
require(
    modifierSection.contains(".accessibilityLabel(self.content.title)") &&
        modifierSection.contains("UnifiedTooltipAnchor(content: self.content, placement: placement)") &&
        !modifierSection.contains("@State") &&
        !modifierSection.contains(".onHover") &&
        !modifierSection.contains("UnifiedTooltipHost"),
    "UnifiedTooltipModifier should not keep local hover state or mount a per-button AppKit tooltip host in hot render paths."
)
let anchorSection = slice(
    tooltip,
    from: "private struct UnifiedTooltipAnchor",
    to: "private final class UnifiedTooltipPresenter"
)
require(
    anchorSection.contains("NSViewRepresentable") &&
        anchorSection.contains("configure(content: content, placement: placement)") &&
        anchorSection.contains("detach()") &&
        !anchorSection.contains("NSPanel") &&
        !anchorSection.contains("NSHostingController") &&
        !anchorSection.contains("layoutSubtreeIfNeeded()"),
    "The per-control anchor representable should only report hover/source-view changes and must not own panel, hosting, or layout measurement."
)
let presenterSection = slice(
    tooltip,
    from: "private final class UnifiedTooltipPresenter",
    to: "private struct UnifiedTooltipBubble"
)
require(
    presenterSection.contains("private var activeID: UUID?") &&
        presenterSection.contains("private weak var activeSourceView: NSView?") &&
        presenterSection.contains("private var activePlacement: UnifiedTooltipPlacement?") &&
        presenterSection.contains("guard activeID != id || activeContent != content") &&
        presenterSection.contains("cachedSize") &&
        presenterSection.contains("layoutSubtreeIfNeeded()") &&
        presenterSection.contains("orderFrontRegardless()") &&
        presenterSection.contains("parent window clipping"),
    "The centralized presenter should gate duplicate hover updates, cache size measurement, and be the only place that performs AppKit panel layout."
)
require(
    tooltip.contains(".accessibilityLabel(self.content.title)") &&
        tooltip.contains(".background(Color.white)") &&
        tooltip.contains("Color.black.opacity(0.86)") &&
        tooltip.contains("Color.black.opacity(0.58)") &&
        tooltip.contains(".font(.system(size: 13, weight: .regular))") &&
        tooltip.contains(".padding(.horizontal, 9)") &&
        !tooltip.contains(".foregroundStyle(.primary)") &&
        !tooltip.contains(".shadow(") &&
        !tooltip.contains("withAnimation(") &&
        !tooltip.contains(".transition(") &&
        !tooltip.contains(".ultraThinMaterial"),
    "Unified tooltip should preserve accessibility, use compact white styling with fixed dark text, and avoid shadows, animations, or material backgrounds."
)
require(
        tooltip.contains("sourceRectOnScreen(for sourceView: NSView)") &&
        tooltip.contains("containerFrame(for sourceView: NSView)") &&
        tooltip.contains("titlebarSafeY(for: sourceView, sourceFrame: sourceFrame, tooltipSize: size, containerFrame: screenFrame)") &&
        tooltip.contains("let titlebarReservedHeight: CGFloat = 64") &&
        tooltip.contains("let topReservedY = containerFrame.maxY - titlebarReservedHeight - size.height") &&
        tooltip.contains("let belowSourceY = sourceFrame.minY - size.height - margin") &&
        tooltip.contains("min(topReservedY, belowSourceY)") &&
        tooltip.contains("window.contentLayoutRect") &&
        tooltip.contains("clampTooltipY") &&
        tooltip.contains("clampedX") &&
        tooltip.contains("placement == .titlebar") &&
        !tooltip.contains("sourceFrame.minY - size.height - titlebarGap") &&
        tooltip.contains("window.frame.intersection(screenFrame)") &&
        tooltip.contains("sourceView.superview ?? sourceView"),
    "Unified tooltip positioning should use the real control bounds, pin titlebar tooltips below the titlebar/content boundary, and clamp the panel inside the current window/screen."
)
let titlebarTooltipSection = slice(
    tooltip,
    from: "func unifiedTitlebarTooltip(",
    to: "func unifiedIconTooltip("
)
require(
    titlebarTooltipSection.contains("UnifiedTooltipContent(title: title)") &&
        titlebarTooltipSection.contains("placement: .titlebar") &&
        !titlebarTooltipSection.contains(".help(title)"),
    "Titlebar tooltip API should use the shared custom presenter with an explicit titlebar placement."
)
require(
    project.contains("UnifiedTooltip.swift in Sources") &&
        project.contains("UnifiedTooltip.swift"),
    "Xcode project should include UnifiedTooltip.swift in the Shared group and app target sources."
)

let inspectorToolbar = rightInspectorTitlebarAccessory
require(
    inspectorToolbar.contains("unifiedTitlebarTooltip(") &&
        inspectorToolbar.contains(#"title: isTerminalOpen ? I18n.t("dashboard.tooltip.hideTerminal") : I18n.t("dashboard.tooltip.showTerminal")"#) &&
        inspectorToolbar.contains(#"title: isExpanded ? I18n.t("dashboard.tooltip.hideOutputs") : I18n.t("dashboard.tooltip.showOutputs")"#) &&
        !inspectorToolbar.contains("unifiedIconTooltip(") &&
        !inspectorToolbar.contains(#""Hide Terminal""#) &&
        !inspectorToolbar.contains(#""Show Terminal""#) &&
        !inspectorToolbar.contains(#""Hide Outputs""#) &&
        !inspectorToolbar.contains(#""Show Outputs""#),
    "Inspector titlebar terminal and outputs buttons should use unified native titlebar tooltips."
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
        sidebar.contains(#"title: I18n.t("subAgents.action.new")"#) &&
        sidebar.contains("dashboard.agent.addWorkFolder") &&
        sidebar.contains(#"title: I18n.t("dashboard.session.newChat")"#),
    "Sidebar agent controls should use unified tooltip content."
)
require(
    !agentSection.contains(#"String(localized: "Show agents""#) &&
        !agentSection.contains(#"String(localized: "Hide agents""#) &&
        agentSection.contains(#"title: I18n.t("subAgents.action.new")"#),
    "Agent section header should not show a tooltip; only the explicit New Agent button should keep one."
)

let composerSelector = slice(
    dashboard,
    from: "struct ComposerModelSelector: View",
    to: "private struct ComposerModelPanel: View"
)
require(
    composerSelector.contains(".unifiedTooltip(UnifiedTooltipContent(") &&
        composerSelector.contains(#"title: I18n.t("dashboard.tooltip.chooseModel")"#),
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
    attachments.contains(#"title: I18n.t("dashboard.tooltip.removeAttachment")"#) &&
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
        budget.contains(".unifiedTooltip(UnifiedTooltipContent(title: I18n.t(\"common.action.refresh\", fallback: \"Refresh\")))") &&
        budget.contains(".unifiedTooltip(UnifiedTooltipContent(title: I18n.t(\"budget.action.resetAgentSession\", fallback: \"Reset agent session\")))") &&
        budget.contains(".unifiedTooltip(UnifiedTooltipContent(title: rule.enabled ? I18n.t(\"catalog.action.disable\") : I18n.t(\"catalog.action.enable\")))") &&
        budget.contains(".unifiedTooltip(UnifiedTooltipContent(title: I18n.t(\"common.action.edit\")))") &&
        budget.contains(".unifiedTooltip(UnifiedTooltipContent(title: I18n.t(\"common.action.delete\")))") &&
        !budget.contains("UnifiedTooltipContent(title: String(localized:"),
    "Secondary tab icon controls should use unified tooltip styling."
)

let chatComposer = read("OpenClawInstaller/Features/Chat/Views/ChatComposerView.swift")
let billing = read("OpenClawInstaller/Features/Settings/Account/BillingTabView.swift")
require(
    chatComposer.contains(#"title: I18n.t("dashboard.tooltip.attachFile", fallback: "Attach File")"#) &&
        !chatComposer.contains(#"UnifiedTooltipContent(title: String(localized: "Attach File""#),
    "Chat composer attachment tooltip should use unified i18n."
)
require(
    billing.contains(#".help(I18n.t("billing.refresh", fallback: "Refresh Billing"))"#) &&
        !billing.contains(#".help(String(localized: "billing.refresh""#),
    "Billing refresh help should use unified i18n."
)
for forbidden in [
    #"unifiedIconTooltip(title: isTerminalOpen ? "Hide Terminal" : "Show Terminal")"#,
    #"unifiedIconTooltip(title: isExpanded ? "Hide Outputs" : "Show Outputs")"#,
    #"UnifiedTooltipContent(title: String(localized: "New Agent""#,
    #"UnifiedTooltipContent(title: String(localized: "New chat""#,
    #"UnifiedTooltipContent(title: String(localized: "Refresh""#,
    #"UnifiedTooltipContent(title: String(localized: "Reset agent session""#,
    #"UnifiedTooltipContent(title: String(localized: "Edit""#,
    #"UnifiedTooltipContent(title: String(localized: "Delete""#
] {
    require(!dashboard.contains(forbidden) && !budget.contains(forbidden), "Tooltip should not bypass I18nService: \(forbidden)")
}

let shortTooltipKeys = [
    "dashboard.tooltip.attachFile",
    "dashboard.tooltip.searchChats",
    "dashboard.tooltip.taskRunning",
    "dashboard.tooltip.hideTerminal",
    "dashboard.tooltip.showTerminal",
    "dashboard.tooltip.hideOutputs",
    "dashboard.tooltip.showOutputs"
]
for key in shortTooltipKeys {
    require(enCommon[key]?.isEmpty == false, "en common.json missing \(key)")
    require(zhHansCommon[key]?.isEmpty == false, "zh-Hans common.json missing \(key)")
    require(zhHantCommon[key]?.isEmpty == false, "zh-Hant common.json missing \(key)")
    require((zhHansCommon[key] ?? "").count <= 12, "zh-Hans tooltip should stay a short label: \(key)")
    require((zhHantCommon[key] ?? "").count <= 12, "zh-Hant tooltip should stay a short label: \(key)")
}
for forbiddenFragment in ["Terminal", "Outputs", "助手：", "面向", "支持", "支援"] {
    require(!shortTooltipKeys.contains { (zhHansCommon[$0] ?? "").contains(forbiddenFragment) }, "zh-Hans tooltip should not contain fallback fragment \(forbiddenFragment)")
    require(!shortTooltipKeys.contains { (zhHantCommon[$0] ?? "").contains(forbiddenFragment) }, "zh-Hant tooltip should not contain fallback fragment \(forbiddenFragment)")
}
require(zhHansSettings["budget.action.resetAgentSession"] == "重置 Agent 会话", "zh-Hans budget reset tooltip should use the reviewed short label")
require(zhHantSettings["budget.action.resetAgentSession"] == "重置 Agent 會話", "zh-Hant budget reset tooltip should use the reviewed short label")

print("Unified tooltip verification passed")
