#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let pluginsPath = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/Plugins/PluginsTabView.swift")
let skillsPath = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/Skills/SkillsTabView.swift")
let plugins = try String(contentsOf: pluginsPath, encoding: .utf8)
let skills = try String(contentsOf: skillsPath, encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(_ source: String, from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source[startRange.upperBound...].range(of: end) else {
        fputs("FAIL: could not slice source between \(start) and \(end)\n", stderr)
        exit(1)
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

func countOccurrences(_ source: String, of needle: String) -> Int {
    source.components(separatedBy: needle).count - 1
}

let pluginsContent = slice(
    plugins,
    from: "@ViewBuilder\n    private var content: some View",
    to: "@ViewBuilder\n    private func recommendedPluginsContent"
)
let recommendedPluginsContent = slice(
    plugins,
    from: "@ViewBuilder\n    private func recommendedPluginsContent",
    to: "@ViewBuilder\n    private func allPluginsContent"
)
let allPluginsContent = slice(
    plugins,
    from: "@ViewBuilder\n    private func allPluginsContent",
    to: "@ViewBuilder\n    private func installedPluginsContent"
)
let installedPluginsContent = slice(
    plugins,
    from: "@ViewBuilder\n    private func installedPluginsContent",
    to: "private func installedPluginSection"
)
let installedPluginSection = slice(
    plugins,
    from: "private func installedPluginSection",
    to: "private func allPluginSection"
)
let allPluginSection = slice(
    plugins,
    from: "private func allPluginSection",
    to: "private func catalogSection"
)
let catalogPluginSection = slice(
    plugins,
    from: "private func catalogSection",
    to: "private func matchesSearch"
)
let catalogRow = slice(
    plugins,
    from: "private struct CatalogPluginListRow: View",
    to: "private struct InstalledPluginListRow: View"
)
let installedRow = slice(
    plugins,
    from: "private struct InstalledPluginListRow: View",
    to: "private struct PluginStatusMark: View"
)
let skillsContent = slice(
    skills,
    from: "@ViewBuilder\n    private var content: some View",
    to: "@ViewBuilder\n    private var recommendedSkillsContent"
)
let recommendedSkillsContent = slice(
    skills,
    from: "@ViewBuilder\n    private var recommendedSkillsContent",
    to: "@ViewBuilder\n    private var allSkillsContent"
)
let allSkillsContent = slice(
    skills,
    from: "@ViewBuilder\n    private var allSkillsContent",
    to: "private var manualInstallOverlay"
)
let allSkillSection = slice(
    skills,
    from: "private func allSkillSection",
    to: "private func catalogSkillSection"
)
let catalogSkillSection = slice(
    skills,
    from: "private func catalogSkillSection",
    to: "@ViewBuilder\n    private var installedSkillsContent"
)
let installedSkillsContent = slice(
    skills,
    from: "@ViewBuilder\n    private var installedSkillsContent",
    to: "private func matchesSearch"
)

require(
    pluginsContent.contains("switch displayMode"),
    "Plugins content should branch before doing mode-specific filtering."
)
require(
    !pluginsContent.contains("let installedPlugins = filteredInstalledPlugins(using: lookup)\n        let customPlugins"),
    "Plugins content should not compute installed/custom/sections before knowing the active mode."
)
require(
    pluginsContent.contains("case .recommend:") &&
        pluginsContent.contains("let recommendedItems = filteredCatalogItems.filter(\\.isRecommended)") &&
        recommendedPluginsContent.contains("catalogSection("),
    "Recommend mode should only compute the catalog list it renders."
)
require(
    countOccurrences(catalogPluginSection, of: "LazyVStack") == 1,
    "Plugins Recommend should render through one catalog LazyVStack because it is a single section."
)
require(
    pluginsContent.contains("case .all:") &&
        pluginsContent.contains("let catalogItems = filteredCatalogItems") &&
        pluginsContent.contains("let customPlugins = customInstalledPlugins"),
    "All mode should compute custom installed plugins only inside the all branch."
)
require(
    allPluginsContent.contains("allPluginSection("),
    "All mode should render through one continuous allPluginSection instead of multiple lazy section stacks."
)
require(
    !allPluginsContent.contains("catalogSection(") &&
        !allPluginsContent.contains("installedSection("),
    "All mode should not call nested LazyVStack section helpers; nested lazy stacks can destabilize scrolling near Custom."
)
require(
    countOccurrences(allPluginSection, of: "LazyVStack") == 1,
    "All plugin section should contain exactly one LazyVStack for Recommend, Built-in, and Custom rows."
)
require(
    allPluginSection.contains("ForEach(Array(recommendedItems.enumerated())") &&
        allPluginSection.contains("ForEach(Array(builtInItems.enumerated())") &&
        allPluginSection.contains("ForEach(Array(customPlugins.enumerated())"),
    "All plugin section should render Recommend, Built-in, and Custom rows inside the same lazy list."
)
require(
    pluginsContent.contains("case .installed:") &&
        pluginsContent.contains("let sections = installedSections"),
    "Installed mode should compute installed sections only inside the installed branch."
)
require(
    installedPluginsContent.contains("installedPluginSection(sections: sections, lookup: lookup)") &&
        !installedPluginsContent.contains("installedSection("),
    "Plugins Installed should render through one continuous section instead of multiple section LazyVStacks."
)
require(
    !plugins.contains("private func installedSection("),
    "Plugins should not keep the old installedSection helper because it reintroduces section-level nested LazyVStacks."
)
require(
    countOccurrences(installedPluginSection, of: "LazyVStack") == 1 &&
        installedPluginSection.contains("ForEach(Array(sections.enumerated())") &&
        installedPluginSection.contains("ForEach(Array(section.items.enumerated())"),
    "Plugins Installed should keep Recommend, Built-in, and Custom groups inside one LazyVStack."
)
require(
    !catalogRow.contains(".clipShape(RoundedRectangle(cornerRadius: 8))") &&
        !installedRow.contains(".clipShape(RoundedRectangle(cornerRadius: 8))"),
    "Plugin rows should avoid per-row clipShape during scroll; rounded backgrounds are enough and match the lighter Skills row path."
)
require(
    skillsContent.contains("switch displayMode") &&
        skillsContent.contains("case .recommend:") &&
        skillsContent.contains("case .all:") &&
        skillsContent.contains("case .installed:"),
    "Skills content should keep the same three-tab branching contract."
)
require(
    recommendedSkillsContent.contains("catalogSkillSection(") &&
        countOccurrences(catalogSkillSection, of: "LazyVStack") == 1,
    "Skills Recommend should remain a single section with one LazyVStack."
)
require(
    allSkillsContent.contains("allSkillSection(") &&
        countOccurrences(allSkillSection, of: "LazyVStack") == 1 &&
        allSkillSection.contains("ForEach(Array(catalogItems.enumerated())") &&
        allSkillSection.contains("ForEach(Array(customSkills.enumerated())"),
    "Skills All should render catalog and custom rows inside one LazyVStack."
)
require(
    countOccurrences(installedSkillsContent, of: "LazyVStack") == 1 &&
        !installedSkillsContent.contains("installedSections") &&
        installedSkillsContent.contains("ForEach(Array(filteredInstalledSkills.enumerated())"),
    "Skills Installed should stay as one installed list instead of multiple lazy sections."
)

print("Marketplace tab scroll structure verification passed")
