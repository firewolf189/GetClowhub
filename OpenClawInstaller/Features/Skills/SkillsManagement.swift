//
//  SkillsManagement.swift
//  Dashboard compatibility facade for skills feature state.
//

import Foundation

extension DashboardViewModel {
    static func loadTrustedSkillNames() -> Set<String> {
        SkillTrustStore.load()
    }

    static func markTrustedSkill(_ skillName: String) {
        SkillTrustStore.mark(skillName)
    }

    static func unmarkTrustedSkill(_ skillName: String) {
        SkillTrustStore.unmark(skillName)
    }

    func loadSkills() async {
        await skillsViewModel.loadSkills()
    }

    func loadSkillMarket(forceSync: Bool = false) async {
        await skillsViewModel.loadSkillMarket(forceSync: forceSync)
    }

    func installCatalogSkill(_ item: SkillCatalogItem) async {
        await skillsViewModel.installCatalogSkill(item)
    }

    @discardableResult
    func installManualSkill(repository: String) async -> Bool {
        await skillsViewModel.installManualSkill(repository: repository)
    }

    static func parseSkillsList(output: String?) -> ([SkillInfo], SkillsSummary) {
        SkillsParser.parseSkillsList(output: output)
    }

    func loadSkillDetail(_ skillName: String) async {
        isLoadingSkillDetail = true
        let output = await openclawService.runCommand(
            "openclaw skills info '\(skillName)' 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        selectedSkillDetail = Self.parseSkillInfo(output: output, skillName: skillName)
        isLoadingSkillDetail = false
    }

    static func canRemoveSkill(_ skill: SkillInfo) -> Bool {
        SkillsViewModel.canRemoveSkill(skill)
    }

    func removeSkill(_ skill: SkillInfo) async {
        await skillsViewModel.removeSkill(skill)
    }

    static func parseSkillInfo(output: String?, skillName: String) -> SkillDetailInfo? {
        SkillsParser.parseSkillInfo(output: output, skillName: skillName)
    }
}
