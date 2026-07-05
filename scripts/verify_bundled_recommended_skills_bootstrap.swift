import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ relativePath: String) -> String {
    let url = root.appendingPathComponent(relativePath)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fputs("FAIL: could not read \(relativePath)\n", stderr)
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

let appBundledCatalog = "OpenClawInstaller/Resources/BundledSkillCatalog"
let bundledMarketplacePath = "\(appBundledCatalog)/marketplace.json"
let bundledSkillsPath = "\(appBundledCatalog)/skills"
let bundledMarketplaceText = read(bundledMarketplacePath)
let bundledSkillsURL = root.appendingPathComponent(bundledSkillsPath)

require(!bundledMarketplaceText.localizedCaseInsensitiveContains("openspec"), "bundled recommended marketplace must not include openspec skills")
require(FileManager.default.fileExists(atPath: bundledSkillsURL.path), "bundled recommended skills folder must exist")

guard let bundledMarketplaceData = bundledMarketplaceText.data(using: .utf8),
      let bundledMarketplace = try? JSONSerialization.jsonObject(with: bundledMarketplaceData) as? [String: Any],
      let bundledEntries = bundledMarketplace["skills"] as? [[String: Any]] else {
    fputs("FAIL: bundled marketplace must be valid JSON with skills array\n", stderr)
    exit(1)
}

let bundledIDs = bundledEntries.compactMap { $0["id"] as? String }
require(!bundledIDs.isEmpty, "bundled marketplace should contain recommended skills")
let bundledSkillMarkdownURLs = (try? FileManager.default.contentsOfDirectory(
    at: bundledSkillsURL,
    includingPropertiesForKeys: [.isDirectoryKey],
    options: [.skipsHiddenFiles]
))?.map { $0.appendingPathComponent("SKILL.md") }.filter {
    FileManager.default.fileExists(atPath: $0.path)
} ?? []
let bundledSkillNames = Set(bundledSkillMarkdownURLs.map { markdownURL -> String in
    let folderName = markdownURL.deletingLastPathComponent().lastPathComponent
    guard let text = try? String(contentsOf: markdownURL, encoding: .utf8),
          text.hasPrefix("---") else {
        return folderName
    }
    for line in text.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("name:") {
            let rawName = trimmed.dropFirst("name:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return rawName.isEmpty ? folderName : rawName
        }
    }
    return folderName
})
for entry in bundledEntries {
    let id = entry["id"] as? String ?? "(missing)"
    require(entry["recommended"] as? Bool == true, "bundled skill \(id) must be marked recommended")
    require(bundledSkillNames.contains(id), "bundled skill \(id) must include a matching SKILL.md name")
}

let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")
require(project.contains("BundledSkillCatalog in Resources"), "Xcode project should copy BundledSkillCatalog as an app resource")

let catalogService = read("OpenClawInstaller/Services/SkillCatalogService.swift")
require(catalogService.contains("static var bundledCatalogURL"), "SkillCatalogService should expose bundled catalog URL")
require(catalogService.contains("seedBundledCatalogIfNeeded"), "SkillCatalogService should seed the local catalog cache from bundled resources")
require(catalogService.contains("copyItem(at: bundledCatalogURL, to: cacheURL)"), "SkillCatalogService should copy bundled catalog into the normal cache path")

let trustStore = read("OpenClawInstaller/Services/SkillTrustStore.swift")
require(trustStore.contains("getclawhub-trusted-skills.json"), "SkillTrustStore should own the trusted skills marker path")
require(trustStore.contains("static func mark"), "SkillTrustStore should expose mark")
require(trustStore.contains("static func unmark"), "SkillTrustStore should expose unmark")

let bootstrapper = read("OpenClawInstaller/Services/RecommendedSkillBootstrapper.swift")
require(bootstrapper.contains(#"Bundle.main.url(forResource: "BundledSkillCatalog""#), "bootstrapper should load bundled catalog from app resources")
require(bootstrapper.contains("SkillCatalogService.parseCatalog(rootURL:"), "bootstrapper should parse bundled catalog through SkillCatalogService")
require(bootstrapper.contains("SkillCatalogService.installCommand(for:"), "bootstrapper should reuse catalog install command")
require(bootstrapper.contains("cacheURL: bundledCatalogURL"), "bootstrapper should install from the bundled local catalog path")
require(bootstrapper.contains("openclaw skills list"), "bootstrapper should check installed skills through the CLI")
require(bootstrapper.contains("SkillTrustStore.mark"), "bootstrapper should mark successful recommended installs as trusted")
require(bootstrapper.contains("getclowhub-recommended-skills-bootstrap.json"), "bootstrapper should persist a one-time bootstrap marker")
require(bootstrapper.contains("__OPENCLAW_RECOMMENDED_SKILL_INSTALL_OK__"), "bootstrapper should use an install success sentinel")

let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
require(dashboard.contains("RecommendedSkillBootstrapper"), "DashboardView should own the recommended skill bootstrapper")
require(dashboard.contains("bootstrapRecommendedSkillsIfNeeded"), "DashboardView should trigger recommended skill bootstrap after dashboard appears")

let skillsModel = read("OpenClawInstaller/Views/Dashboard/Skills/SkillsTabModel.swift")
require(skillsModel.contains("SkillTrustStore.load"), "SkillsTabModel should read trusted skills from SkillTrustStore")
require(skillsModel.contains("SkillTrustStore.mark"), "SkillsTabModel should mark installed catalog skills through SkillTrustStore")
require(skillsModel.contains("SkillTrustStore.unmark"), "SkillsTabModel should unmark removed skills through SkillTrustStore")
require(skillsModel.contains("seedBundledCatalogIfNeeded"), "SkillsTabModel should use bundled catalog cache before first remote sync")
require(skillsModel.contains("forceSync || (!didSeedBundledCatalog && !FileManager.default.fileExists"), "SkillsTabModel should avoid remote sync after seeding bundled catalog unless refresh is explicit")

let viewModel = read("OpenClawInstaller/ViewModels/DashboardViewModel.swift")
require(viewModel.contains("SkillTrustStore.load"), "DashboardViewModel legacy skill flow should read trusted skills from SkillTrustStore")
require(viewModel.contains("SkillTrustStore.mark"), "DashboardViewModel legacy skill flow should mark trusted skills through SkillTrustStore")
require(viewModel.contains("SkillTrustStore.unmark"), "DashboardViewModel legacy skill flow should unmark trusted skills through SkillTrustStore")
require(viewModel.contains("seedBundledCatalogIfNeeded"), "DashboardViewModel legacy skill flow should use bundled catalog cache before first remote sync")

let cacheMarketplacePath = "/Users/zephyrwing/.openclaw/getclowhub-skills-catalog/marketplace.json"
if let cacheMarketplaceText = try? String(contentsOfFile: cacheMarketplacePath, encoding: .utf8) {
    require(!cacheMarketplaceText.localizedCaseInsensitiveContains("openspec"), "local catalog marketplace should not include openspec recommended skills")
}

print("Bundled recommended skills bootstrap verification passed")
