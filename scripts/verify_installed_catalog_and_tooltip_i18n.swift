#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
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

func slice(_ source: String, from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start) else {
        fputs("FAIL: missing slice start: \(start)\n", stderr)
        exit(1)
    }
    let tail = source[startRange.lowerBound...]
    guard let endRange = tail.range(of: end) else {
        fputs("FAIL: missing slice end: \(end)\n", stderr)
        exit(1)
    }
    return String(tail[..<endRange.lowerBound])
}

func jsonObject(_ path: String) -> [String: String] {
    let data = Data(read(path).utf8)
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
        fputs("FAIL: invalid JSON string object in \(path)\n", stderr)
        exit(1)
    }
    return json
}

let i18n = read("OpenClawInstaller/Localization/I18nService.swift")
require(i18n.contains("static func installedSkillDisplay"), "I18n should expose installedSkillDisplay")
require(i18n.contains("static func installedPluginDisplay"), "I18n should expose installedPluginDisplay")
require(i18n.contains("skills.installed."), "installed skill fallback keys should live under skills.installed")
require(i18n.contains("plugins.installed."), "installed plugin fallback keys should live under plugins.installed")

let skillsView = read("OpenClawInstaller/Features/Skills/Views/SkillsTabView.swift")
let installedSkillRow = slice(
    skillsView,
    from: "private struct InstalledSkillListRow: View",
    to: "private struct InstalledStatusMark: View"
)
let skillPresentation = slice(
    skillsView,
    from: "static func fromInstalled(_ skill: SkillInfo",
    to: "struct SkillsTabView: View"
)
require(installedSkillRow.contains("I18n.installedSkillDisplay"), "InstalledSkillListRow should use unified installed skill display")
require(skillPresentation.contains("I18n.installedSkillDisplay"), "Skill detail presentation should use unified installed skill display")
require(!installedSkillRow.contains("skill.description.nilIfBlank"), "Installed skill row should not render raw skill.description fallback directly")

let pluginsView = read("OpenClawInstaller/Features/Plugins/Views/PluginsTabView.swift")
let installedPluginRow = slice(
    pluginsView,
    from: "private struct InstalledPluginListRow: View",
    to: "private struct InstalledPluginFallbackDisplay"
)
let fallbackDisplay = slice(
    pluginsView,
    from: "private struct InstalledPluginFallbackDisplay",
    to: "private struct PluginStatusMark: View"
)
let pluginPresentation = slice(
    pluginsView,
    from: "static func fromInstalled(_ plugin: PluginInfo",
    to: "struct PluginsTabView: View"
)
require(installedPluginRow.contains("I18n.installedPluginDisplay"), "InstalledPluginListRow should use unified installed plugin display")
require(pluginPresentation.contains("I18n.installedPluginDisplay"), "Plugin detail presentation should use unified installed plugin display")
for forbidden in [
    "Model provider for connecting OpenClaw",
    "Browser automation capability",
    "Speech capability",
    "Memory storage capability",
    "Proxy capability",
    "Core runtime capability",
    "**Plugin ID:**",
    "**Status:**",
    "**Version:**"
] {
    require(!fallbackDisplay.contains(forbidden), "InstalledPluginFallbackDisplay should not hardcode English fallback text: \(forbidden)")
}

let dashboard = read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
for forbidden in [
    #"UnifiedTooltipContent(title: "Choose model""#,
    #"UnifiedTooltipContent(title: "Remove attachment""#,
    #"UnifiedTooltipContent(title: "Refresh""#,
    #"UnifiedTooltipContent(title: "Open Outputs Folder""#,
    #"UnifiedTooltipContent(title: "Clear Conversation""#,
    #"UnifiedTooltipContent(title: "Edit agent""#,
    #"UnifiedTooltipContent(title: expanded ? "Collapse session details" : "Expand session details")"#
] {
    require(!dashboard.contains(forbidden), "Dashboard tooltip should use I18n instead of hardcoded text: \(forbidden)")
}
require(dashboard.contains("I18n.t(\"dashboard.tooltip.chooseModel\""), "Choose model tooltip should use I18n")
require(dashboard.contains("I18n.t(\"dashboard.tooltip.removeAttachment\""), "Remove attachment tooltip should use I18n")
require(dashboard.contains("I18n.t(\"dashboard.tooltip.openOutputsFolder\""), "Open outputs folder tooltip should use I18n")

let zhCommon = jsonObject("OpenClawInstaller/Resources/I18n/zh-Hans/common.json")
let zhPlugins = jsonObject("OpenClawInstaller/Resources/I18n/zh-Hans/plugins.json")
let zhSkills = jsonObject("OpenClawInstaller/Resources/I18n/zh-Hans/skills.json")
for key in [
    "dashboard.tooltip.chooseModel",
    "dashboard.tooltip.removeAttachment",
    "dashboard.tooltip.openOutputsFolder",
    "dashboard.tooltip.clearConversation",
    "dashboard.tooltip.collapseSessionDetails",
    "dashboard.tooltip.expandSessionDetails",
    "dashboard.tooltip.editAgent"
] {
    require(zhCommon[key]?.isEmpty == false, "zh-Hans common.json missing \(key)")
}
for key in [
    "plugins.installed.family.provider.description",
    "plugins.installed.family.browser.description",
    "plugins.installed.detail.pluginId",
    "plugins.installed.detail.status",
    "plugins.installed.detail.version"
] {
    require(zhPlugins[key]?.isEmpty == false, "zh-Hans plugins.json missing \(key)")
}
for key in [
    "skills.installed.fallback.description",
    "skills.installed.fallback.content"
] {
    require(zhSkills[key]?.isEmpty == false, "zh-Hans skills.json missing \(key)")
}

print("Installed catalog fallback and tooltip i18n verified")
