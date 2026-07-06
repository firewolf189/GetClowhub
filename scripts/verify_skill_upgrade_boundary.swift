#!/usr/bin/env swift

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

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fputs("FAIL: could not slice source between \(start) and \(end)\n", stderr)
        exit(1)
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let skillCatalogService = read("OpenClawInstaller/Features/Skills/Services/SkillCatalogService.swift")
let installStateStore = read("OpenClawInstaller/Features/Skills/Services/SkillInstallStateStore.swift")
let skillsModel = read("OpenClawInstaller/Features/Skills/ViewModels/SkillsViewModel.swift")
let skillsView = read("OpenClawInstaller/Features/Skills/Views/SkillsTabView.swift")
let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")

let loadSkillMarket = slice(
    skillsModel,
    from: "func loadSkillMarket(forceSync: Bool = false) async",
    to: "func installCatalogSkill"
)
let installCatalogSkill = slice(
    skillsModel,
    from: "func installCatalogSkill(_ item: SkillCatalogItem) async",
    to: "@discardableResult"
)
let removeSkill = slice(
    skillsModel,
    from: "func removeSkill(_ skill: SkillInfo) async",
    to: "private static func shellQuote"
)
let detailOverlay = slice(
    skillsView,
    from: "private func skillDetailOverlay(for item: SkillDetailPresentationItem) -> some View",
    to: "private struct ManualSkillInstallSheet"
)
let detailSheet = slice(
    skillsView,
    from: "struct SkillCatalogDetailSheet: View",
    to: "private struct SkillDetailChip: View"
)

require(
    skillCatalogService.contains("static func catalogRevision(cacheURL: URL = defaultCacheURL) -> String?") &&
        skillCatalogService.contains("static func skillRevision(for item: SkillCatalogItem, cacheURL: URL = defaultCacheURL) -> String?") &&
        skillCatalogService.contains("git -C") &&
        skillCatalogService.contains("rev-parse HEAD") &&
        skillCatalogService.contains("SHA256.hash"),
    "SkillCatalogService should expose catalog revision and stable per-skill content revision without mutating installed skills."
)
require(
    installStateStore.contains("getclowhub-skill-install-state.json"),
    "SkillInstallStateStore should persist catalog install revisions in its own state file."
)
require(
    installStateStore.contains("catalogRevision: String") &&
        installStateStore.contains("skillRevision: String") &&
        installStateStore.contains("relativePath: String") &&
        installStateStore.contains("repositoryIdentifier: String"),
    "SkillInstallStateStore entries should record skill revision, catalog revision, relative path, and repository identity."
)
require(
    installStateStore.contains("static func recordInstall") &&
        installStateStore.contains("static func remove") &&
        installStateStore.contains("static func hasUpdate"),
    "SkillInstallStateStore should record install state, clear it on removal, and calculate update availability."
)
require(
    project.contains("SkillInstallStateStore.swift in Sources"),
    "Xcode project should compile SkillInstallStateStore."
)
require(
    skillsModel.contains("@Published var skillCatalogRevision: String?") &&
        skillsModel.contains("@Published var skillInstallStates: [String: SkillInstallStateStore.Entry] = [:]") &&
        skillsModel.contains("@Published var upgradingCatalogSkillName: String?"),
    "SkillsViewModel should publish catalog revision, install states, and upgrade progress."
)
require(
    loadSkillMarket.contains("SkillCatalogService.catalogRevision()") &&
        loadSkillMarket.contains("skillCatalogRevision =") &&
        loadSkillMarket.contains("skillInstallStates = SkillInstallStateStore.load()") &&
        !loadSkillMarket.contains("installCatalogSkill(") &&
        !loadSkillMarket.contains("upgradeCatalogSkill(") &&
        !loadSkillMarket.contains("SkillInstallStateStore.recordInstall"),
    "Global refresh should update catalog metadata/state view only, not install or upgrade skills."
)
require(
    installCatalogSkill.contains("recordCatalogInstall(for: item)") &&
        skillsModel.contains("private func recordCatalogInstall(for item: SkillCatalogItem)") &&
        skillsModel.contains("SkillInstallStateStore.recordInstall") &&
        skillsModel.contains("skillRevision: SkillCatalogService.skillRevision(for: item)") &&
        skillsModel.contains("catalogRevision: skillCatalogRevision"),
    "Catalog install should record the skill and catalog revisions after a successful explicit install."
)
require(
    skillsModel.contains("func upgradeCatalogSkill(_ item: SkillCatalogItem) async") &&
        skillsModel.contains("__OPENCLAW_SKILL_UPGRADE_OK__") &&
        skillsModel.contains(#"notifySuccess(I18n.format("skills.toast.upgraded""#),
    "SkillsViewModel should expose an explicit upgrade action with its own sentinel and toast."
)
require(
    removeSkill.contains("SkillInstallStateStore.remove(skill.name)") &&
        removeSkill.contains("skillInstallStates = SkillInstallStateStore.load()"),
    "Removing a skill should clear catalog install revision state."
)
require(
    skillsModel.contains("func isUpdateAvailable(for item: SkillCatalogItem, installedSkill: SkillInfo?) -> Bool") &&
        skillsModel.contains("SkillInstallStateStore.hasUpdate"),
    "SkillsViewModel should calculate update availability from recorded revision versus current catalog revision."
)
require(
    detailOverlay.contains("isUpdateAvailable:") &&
        detailOverlay.contains("model.isUpdateAvailable(for:") &&
        detailOverlay.contains("isUpgrading: model.upgradingCatalogSkillName == item.name") &&
        detailOverlay.contains("upgradeCatalogSkill(catalogItem)"),
    "Skill detail overlay should wire explicit upgrade state and action."
)
require(
    detailSheet.contains("let isUpdateAvailable: Bool") &&
        detailSheet.contains("let isUpgrading: Bool") &&
        detailSheet.contains("let onUpgrade: () -> Void") &&
        detailSheet.contains(#"I18n.t("catalog.action.upgrade""#) &&
        detailSheet.contains(#"I18n.t("catalog.action.upgrading""#) &&
        detailSheet.contains(#"I18n.t("catalog.status.updateAvailable""#),
    "Skill detail sheet should render update availability and Upgrade controls."
)
require(
    skillsView.contains("case upgrade"),
    "Skill pill button style should include an upgrade tone."
)

print("OK: skill upgrade boundary verified")
