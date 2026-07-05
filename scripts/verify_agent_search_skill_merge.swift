import Foundation

let repoRoot = URL(fileURLWithPath: "/Users/zephyrwing/.openclaw/getclowhub-skills-catalog")
let appRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ url: URL) -> String {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fputs("FAIL: could not read \(url.path)\n", stderr)
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

func marketplaceIDs(_ url: URL) -> [String] {
    guard let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let skills = object["skills"] as? [[String: Any]] else {
        fputs("FAIL: invalid marketplace at \(url.path)\n", stderr)
        exit(1)
    }
    return skills.compactMap { $0["id"] as? String }
}

let sourceIDs = marketplaceIDs(repoRoot.appendingPathComponent("marketplace.json"))
let bundledIDs = marketplaceIDs(appRoot.appendingPathComponent("OpenClawInstaller/Resources/BundledSkillCatalog/marketplace.json"))

for ids in [sourceIDs, bundledIDs] {
    require(ids.contains("agent-search"), "marketplace should recommend agent-search")
    require(!ids.contains("agent-reach"), "marketplace should not keep agent-reach as a separate entry")
    require(!ids.contains("opencli-usage"), "marketplace should not keep opencli-usage as a separate entry")
    require(!ids.contains("smart-search"), "marketplace should not keep smart-search as a separate entry")
}

let sourceSkillDir = repoRoot.appendingPathComponent("skills/agent-search")
let bundledSkillDir = appRoot.appendingPathComponent("OpenClawInstaller/Resources/BundledSkillCatalog/skills/agent-search")
require(FileManager.default.fileExists(atPath: sourceSkillDir.appendingPathComponent("SKILL.md").path), "source agent-search skill should exist")
require(FileManager.default.fileExists(atPath: bundledSkillDir.appendingPathComponent("SKILL.md").path), "bundled agent-search skill should exist")
require(!FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("skills/agent-reach").path), "old agent-reach folder should be removed")
require(!FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("skills/opencli-usage").path), "old opencli-usage folder should be removed")
require(!FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("skills/smart-search").path), "old smart-search folder should be removed")

let skill = read(sourceSkillDir.appendingPathComponent("SKILL.md"))
require(skill.contains("name: agent-search"), "merged skill should use valid agent-search skill name")
require(skill.contains("display_name: AgentSearch"), "merged skill should expose AgentSearch display name")
require(skill.contains("agent-reach doctor --json"), "merged skill should preserve AgentSearch backend doctor route")
require(skill.contains("opencli list -f json"), "merged skill should preserve OpenCLI live registry discovery")
require(skill.contains("OpenCLI Search Budget"), "merged skill should preserve smart-search budget rules")
require(skill.contains("opencli-sources-ai.md"), "merged skill should route to migrated smart-search source references")

let expectedReferenceFiles = [
    "career.md",
    "dev.md",
    "search.md",
    "social.md",
    "video.md",
    "web.md",
    "opencli-sources-ai.md",
    "opencli-sources-tech.md",
    "opencli-sources-social.md",
    "opencli-sources-media.md",
    "opencli-sources-info.md",
    "opencli-sources-shopping.md",
    "opencli-sources-travel.md",
    "opencli-sources-other.md",
]

for filename in expectedReferenceFiles {
    require(
        FileManager.default.fileExists(atPath: sourceSkillDir.appendingPathComponent("references/\(filename)").path),
        "merged skill should include reference \(filename)"
    )
    require(
        FileManager.default.fileExists(atPath: bundledSkillDir.appendingPathComponent("references/\(filename)").path),
        "bundled merged skill should include reference \(filename)"
    )
}

print("AgentSearch skill merge verification passed")
