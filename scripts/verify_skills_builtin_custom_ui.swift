#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let skillsViewPath = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("SkillsTabView.swift")

let text = try String(contentsOf: skillsViewPath, encoding: .utf8)

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

expect(text.contains("customInstalledSkills"), "All view should include installed custom skills from CLI output")
expect(text.contains("SkillLibrarySection.allCases"), "Installed view should group with SkillLibrarySection")
expect(text.contains("SkillLibrarySection.builtIn.title"), "All view should render a Built-in section")
expect(text.contains("SkillLibrarySection.custom.title"), "All view should render a Custom section")
expect(!text.contains(#"(.trusted, "Trusted")"#), "Installed grouping should not expose the old Trusted section")
expect(!text.contains(#"(.external, "External")"#), "Installed grouping should not expose the old External section")

print("OK: Skills UI uses Built-in and Custom grouping")
