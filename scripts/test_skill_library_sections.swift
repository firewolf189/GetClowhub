import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum SkillLibrarySectionTests {
    static func main() {
        let catalogItem = SkillCatalogItem(
            id: "weather",
            name: "weather",
            displayName: "Weather",
            description: "Get current weather",
            documentationMarkdown: "# Weather\n\nGet current weather",
            category: .builtIn,
            relativePath: "skills/built-in/weather",
            iconURL: nil
        )
        let catalog = SkillNameIndex.firstByName([catalogItem]) { $0.name }

        expect(SkillLibrarySection.builtIn.title == "Built-in", "built-in section title should match UI copy")
        expect(SkillLibrarySection.custom.title == "Custom", "custom section title should match UI copy")
        expect(
            SkillLibrarySection.section(forSkillName: "weather", catalogItemsByName: catalog) == .builtIn,
            "catalog skills should be classified as built-in"
        )
        expect(
            SkillLibrarySection.section(forSkillName: "local-only", catalogItemsByName: catalog) == .custom,
            "installed skills missing from catalog should be classified as custom"
        )

        print("OK: skill library sections classify built-in and custom skills")
    }
}
