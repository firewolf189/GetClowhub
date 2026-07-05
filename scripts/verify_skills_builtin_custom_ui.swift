#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let skillsViewPath = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("Skills")
    .appendingPathComponent("SkillsTabView.swift")

let text = try String(contentsOf: skillsViewPath, encoding: .utf8)

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

expect(text.contains("filteredCustomInstalledSkills"), "All view should include installed custom skills from CLI output")
// The Built-in/Custom SkillLibrarySection grouping was replaced by the
// catalog section model (recommended / all / installed) in the skills-tab
// refactor; guard the new sections instead.
expect(text.contains(#"SkillSectionHeader(title: I18n.t("catalog.section.all")"#), "All view should render a section header")
expect(text.contains(#"SkillSectionHeader(title: I18n.t("catalog.section.installed")"#), "Installed view should render a section header")
expect(text.contains("filteredRecommendedCatalogItems"), "Catalog should surface a recommended subsection")
expect(!text.contains("SkillLibrarySection"), "The removed SkillLibrarySection grouping should not come back piecemeal")
expect(!text.contains(#"(.trusted, "Trusted")"#), "Installed grouping should not expose the old Trusted section")
expect(!text.contains(#"(.external, "External")"#), "Installed grouping should not expose the old External section")

print("OK: Skills UI uses the catalog section grouping")
