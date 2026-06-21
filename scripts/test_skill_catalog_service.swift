import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum SkillCatalogServiceTests {
    static func main() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skill-catalog-service-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let skillRoot = root
            .appendingPathComponent("skills")
            .appendingPathComponent("built-in")
            .appendingPathComponent("demo-skill")
        let assetsRoot = skillRoot.appendingPathComponent("assets")
        let nestedAssetsRoot = assetsRoot.appendingPathComponent("icons")
        try FileManager.default.createDirectory(at: nestedAssetsRoot, withIntermediateDirectories: true)
        try Data("png".utf8).write(to: nestedAssetsRoot.appendingPathComponent("brand.png"))
        try Data("svg".utf8).write(to: assetsRoot.appendingPathComponent("icon.svg"))
        try """
        ---
        name: "demo-skill"
        description: "A demo skill used to verify catalog parsing."
        ---

        # Demo Skill

        Use this skill when testing catalog parsing.

        ## Workflow

        - Read SKILL.md
        - Render Markdown
        """.write(to: skillRoot.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let items = try SkillCatalogService.parseCatalog(rootURL: root)
        expect(items.count == 1, "expected one parsed catalog item")

        let item = try XCTUnwrap(items.first, "expected first catalog item")
        expect(item.id == "demo-skill", "skill id should use frontmatter name")
        expect(item.category == .builtIn, "skill category should come from built-in folder")
        expect(item.relativePath == "skills/built-in/demo-skill", "relative path should use flat built-in layout")
        expect(item.description == "A demo skill used to verify catalog parsing.", "description should parse frontmatter")
        expect(item.documentationMarkdown.contains("# Demo Skill"), "documentation markdown should keep body headings")
        expect(item.documentationMarkdown.contains("## Workflow"), "documentation markdown should keep body sections")
        expect(!item.documentationMarkdown.contains("description:"), "documentation markdown should strip frontmatter")
        expect(item.iconURL?.lastPathComponent == "brand.png", "raster icons should be preferred over SVG, including nested assets")
        expect(
            SkillCatalogService.installCommand(for: item).contains("--skill 'demo-skill'"),
            "install command should target the selected skill"
        )
        expect(
            SkillCatalogService.manualInstallCommand(repositoryInput: "zephyrwing-ai/GetClowHubSkills") == "npx --yes --prefer-offline skills add 'https://github.com/zephyrwing-ai/GetClowHubSkills' -g -y",
            "manual install should accept owner/repo shorthand"
        )
        expect(
            SkillCatalogService.manualInstallCommand(repositoryInput: "https://github.com/acme/demo.git/") == "npx --yes --prefer-offline skills add 'https://github.com/acme/demo' -g -y",
            "manual install should normalize GitHub URLs"
        )
        expect(
            SkillCatalogService.manualInstallCommand(repositoryInput: "not a repo") == nil,
            "manual install should reject invalid repository input"
        )

        let nestedLegacyRoot = root
            .appendingPathComponent("skills")
            .appendingPathComponent("built-in")
            .appendingPathComponent("curated")
            .appendingPathComponent("nested-legacy-skill")
        try FileManager.default.createDirectory(at: nestedLegacyRoot, withIntermediateDirectories: true)
        try """
        ---
        name: "nested-legacy-skill"
        description: "Nested legacy skill."
        ---
        """.write(to: nestedLegacyRoot.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let flatPreferredItems = try SkillCatalogService.parseCatalog(rootURL: root)
        expect(
            flatPreferredItems.map(\.name) == ["demo-skill"],
            "flat built-in layout should ignore nested built-in directories"
        )

        let nestedOnlyRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skill-catalog-nested-only-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: nestedOnlyRoot) }
        let nestedOnlySkillRoot = nestedOnlyRoot
            .appendingPathComponent("skills")
            .appendingPathComponent("built-in")
            .appendingPathComponent("curated")
            .appendingPathComponent("nested-only-skill")
        try FileManager.default.createDirectory(at: nestedOnlySkillRoot, withIntermediateDirectories: true)
        try """
        ---
        name: "nested-only-skill"
        description: "Nested-only skill."
        ---
        """.write(to: nestedOnlySkillRoot.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let nestedOnlyItems = try SkillCatalogService.parseCatalog(rootURL: nestedOnlyRoot)
        expect(nestedOnlyItems.isEmpty, "nested built-in fallback should not be parsed")

        let legacyRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skill-catalog-legacy-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: legacyRoot) }
        let legacySkillRoot = legacyRoot
            .appendingPathComponent("skills")
            .appendingPathComponent(".curated")
            .appendingPathComponent("legacy-skill")
        try FileManager.default.createDirectory(at: legacySkillRoot, withIntermediateDirectories: true)
        try """
        ---
        name: "legacy-skill"
        description: "Legacy layout skill."
        ---
        """.write(to: legacySkillRoot.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let legacyItems = try SkillCatalogService.parseCatalog(rootURL: legacyRoot)
        expect(legacyItems.isEmpty, "legacy .system/.curated folders should not be parsed")

        struct DuplicateNamedItem {
            let name: String
            let value: String
        }
        let duplicateIndex = SkillNameIndex.firstByName([
            DuplicateNamedItem(name: "openai-docs", value: "system"),
            DuplicateNamedItem(name: "openai-docs", value: "curated"),
            DuplicateNamedItem(name: "imagegen", value: "system")
        ]) { $0.name }
        expect(duplicateIndex.count == 2, "duplicate names should not crash or create duplicate keys")
        expect(duplicateIndex["openai-docs"]?.value == "system", "duplicate names should keep the first catalog item")
    }
}

func XCTUnwrap<T>(_ value: T?, _ message: String) throws -> T {
    guard let value = value else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
    return value
}
