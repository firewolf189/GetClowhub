//
//  DashboardViewModel+SkillsManagement.swift
//  Skills management methods extracted from DashboardViewModel.
//  P1 refactor: file split only, no behavior change. (Stored @Published
//  skill state stays in the main class; only methods moved here.)
//

import Foundation

extension DashboardViewModel {

    // MARK: - Skills Management (methods)

    private static var trustedSkillsMarkerPath: String {
        NSString("~/.openclaw/getclawhub-trusted-skills.json").expandingTildeInPath
    }

    static func loadTrustedSkillNames() -> Set<String> {
        guard let data = FileManager.default.contents(atPath: trustedSkillsMarkerPath),
              let names = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(names)
    }

    static func markTrustedSkill(_ skillName: String) {
        let trimmed = skillName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var names = loadTrustedSkillNames()
        names.insert(trimmed)
        writeTrustedSkillNames(names)
    }

    static func unmarkTrustedSkill(_ skillName: String) {
        var names = loadTrustedSkillNames()
        names.remove(skillName)
        writeTrustedSkillNames(names)
    }

    private static func writeTrustedSkillNames(_ names: Set<String>) {
        let url = URL(fileURLWithPath: trustedSkillsMarkerPath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let sorted = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if let data = try? JSONEncoder().encode(sorted) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Load skills list by running `openclaw skills list`
    func loadSkills() async {
        isLoadingSkills = true
        let output = await openclawService.runCommand(
            "openclaw skills list 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        let (parsed, summary) = Self.parseSkillsList(output: output)
        let trustedNames = Self.loadTrustedSkillNames()
        let decorated = parsed.map { skill in
            guard trustedNames.contains(skill.name),
                  SkillSourcePresentation(source: skill.source).kind != .builtIn else {
                return skill
            }
            return SkillInfo(
                name: skill.name,
                status: skill.status,
                description: skill.description,
                source: "getclawhub-trusted"
            )
        }
        skills = decorated.sorted { a, b in
            if a.status != b.status {
                return a.status == .ready
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        skillsSummary = summary
        isLoadingSkills = false
    }

    /// Load the GetClowHub skill catalog and overlay local install status separately.
    func loadSkillMarket(forceSync: Bool = false) async {
        if hasLoadedSkillCatalog && !forceSync {
            await loadSkills()
            return
        }

        guard !isLoadingSkillCatalog else { return }

        isLoadingSkillCatalog = true
        skillCatalogError = nil

        let cacheGitURL = SkillCatalogService.defaultCacheURL.appendingPathComponent(".git")
        let shouldSync = forceSync || !FileManager.default.fileExists(atPath: cacheGitURL.path)
        let syncOutput: String?
        if shouldSync {
            syncOutput = await openclawService.runCommand(
                "(\(SkillCatalogService.syncCommand()) && echo __OPENCLAW_SKILL_SYNC_OK__) 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'",
                timeout: 120
            )
            if syncOutput?.contains("__OPENCLAW_SKILL_SYNC_OK__") != true {
                let detail = syncOutput?.trimmingCharacters(in: .whitespacesAndNewlines)
                skillCatalogError = detail?.isEmpty == false ? detail : "Failed to refresh skills"
                await loadSkills()
                isLoadingSkillCatalog = false
                return
            }
        } else {
            syncOutput = nil
        }

        do {
            skillCatalog = try SkillCatalogService.parseCatalog(rootURL: SkillCatalogService.defaultCacheURL)
            hasLoadedSkillCatalog = true
        } catch {
            let detail = syncOutput?.trimmingCharacters(in: .whitespacesAndNewlines)
            skillCatalogError = detail?.isEmpty == false ? detail : error.localizedDescription
            skillCatalog = []
            hasLoadedSkillCatalog = false
        }

        await loadSkills()
        isLoadingSkillCatalog = false

        if forceSync && skillCatalogError == nil {
            showSuccessMessage("Skills updated successfully")
        }
    }

    func installCatalogSkill(_ item: SkillCatalogItem) async {
        guard installingCatalogSkillName == nil else { return }

        installingCatalogSkillName = item.name
        let command = SkillCatalogService.installCommand(for: item)
        let output = await openclawService.runCommand(
            "(\(command) 2>&1 && echo __OPENCLAW_SKILL_INSTALL_OK__) | sed 's/\\x1b\\[[0-9;]*m//g'",
            timeout: 180
        )
        installingCatalogSkillName = nil

        if output?.contains("__OPENCLAW_SKILL_INSTALL_OK__") == true {
            Self.markTrustedSkill(item.name)
            await loadSkills()
            showSuccessMessage("Installed skill \(item.name)")
        } else {
            let trimmed = output?.trimmingCharacters(in: .whitespacesAndNewlines)
            showErrorMessage("Failed to install \(item.name): \(trimmed?.isEmpty == false ? trimmed! : "unknown error")")
        }
    }

    @discardableResult
    func installManualSkill(repository: String) async -> Bool {
        guard !isInstallingManualSkill else { return false }

        let command: String
        do {
            command = try SkillCatalogService.manualInstallCommand(for: repository)
        } catch {
            showErrorMessage(error.localizedDescription)
            return false
        }

        isInstallingManualSkill = true
        let output = await openclawService.runCommand(
            "(\(command) 2>&1 && echo __OPENCLAW_MANUAL_SKILL_INSTALL_OK__) | sed 's/\\x1b\\[[0-9;]*m//g'",
            timeout: 180
        )
        isInstallingManualSkill = false

        if output?.contains("__OPENCLAW_MANUAL_SKILL_INSTALL_OK__") == true {
            await loadSkills()
            showSuccessMessage("Installed skill from repository")
            return true
        } else {
            let trimmed = output?.trimmingCharacters(in: .whitespacesAndNewlines)
            showErrorMessage("Failed to install skill: \(trimmed?.isEmpty == false ? trimmed! : "unknown error")")
            return false
        }
    }

    /// Parse `openclaw skills list` table output.
    /// Table format: │ Status │ Skill │ Description │ Source │
    static func parseSkillsList(output: String?) -> ([SkillInfo], SkillsSummary) {
        guard let output = output else { return ([], SkillsSummary()) }

        var results: [SkillInfo] = []
        var summary = SkillsSummary()

        // Parse header "Skills (35/81 ready)"
        for line in output.components(separatedBy: .newlines) {
            if line.contains("Skills (") && line.contains("ready)") {
                if let range = line.range(of: "\\((\\d+)/(\\d+)\\s+ready\\)", options: .regularExpression) {
                    let match = String(line[range])
                    let nums = match.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
                    if nums.count >= 2 {
                        summary.ready = Int(nums[0]) ?? 0
                        summary.total = Int(nums[1]) ?? 0
                    }
                }
                break
            }
        }

        // Current row accumulator (for multiline cells)
        var currentStatus: String?
        var currentName: String?
        var currentDesc: String?
        var currentSource: String?

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip border lines and non-table lines
            guard trimmed.hasPrefix("│") else { continue }

            // Skip header row
            if trimmed.contains("Status") && trimmed.contains("Skill") && trimmed.contains("Description") && trimmed.contains("Source") {
                continue
            }

            // Split by │ and trim
            let cells = trimmed.components(separatedBy: "│")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            // cells[0]="" cells[1]=Status cells[2]=Skill cells[3]=Description cells[4]=Source
            guard cells.count >= 5 else { continue }

            let status = cells[1]
            // Strip leading emoji from skill name (e.g. "📦 feishu-doc" -> "feishu-doc")
            let skill = cells[2].drop(while: { !$0.isASCII })
                .trimmingCharacters(in: .whitespaces)
            let desc = cells[3]
            let source = cells[4]

            // Check if this is a new row (status column is non-empty)
            if !status.isEmpty {
                // Flush previous row
                if let prevName = currentName, !prevName.isEmpty {
                    results.append(SkillInfo(
                        name: prevName,
                        status: currentStatus?.contains("ready") == true ? .ready : .missing,
                        description: currentDesc ?? "",
                        source: currentSource ?? ""
                    ))
                }
                currentStatus = status
                currentName = skill
                currentDesc = desc
                currentSource = source
            } else {
                // Continuation line — append description
                if !skill.isEmpty {
                    currentName = (currentName ?? "") + skill
                }
                if !desc.isEmpty {
                    currentDesc = ((currentDesc ?? "") + " " + desc).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        // Flush last row
        if let prevName = currentName, !prevName.isEmpty {
            results.append(SkillInfo(
                name: prevName,
                status: currentStatus?.contains("ready") == true ? .ready : .missing,
                description: currentDesc ?? "",
                source: currentSource ?? ""
            ))
        }

        return (results, summary)
    }

    /// Load detail info for a specific skill
    func loadSkillDetail(_ skillName: String) async {
        isLoadingSkillDetail = true
        let output = await openclawService.runCommand(
            "openclaw skills info '\(skillName)' 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        selectedSkillDetail = Self.parseSkillInfo(output: output, skillName: skillName)
        isLoadingSkillDetail = false
    }

    static func canRemoveSkill(_ skill: SkillInfo) -> Bool {
        SkillSourcePresentation(source: skill.source).isRemovable
    }

    func removeSkill(_ skill: SkillInfo) async {
        guard Self.canRemoveSkill(skill) else {
            showErrorMessage("Built-in skills cannot be removed")
            return
        }

        removingSkillName = skill.name
        let scopeFlag = skill.source == "openclaw-workspace" ? "" : " -g"
        let command = "npx skills remove \(Self.shellQuote(skill.name))\(scopeFlag) -y"
        let output = await openclawService.runCommand(
            "(\(command) 2>&1 && echo __OPENCLAW_SKILL_REMOVE_OK__) | sed 's/\\x1b\\[[0-9;]*m//g'",
            timeout: 120
        )
        removingSkillName = nil

        if output?.contains("__OPENCLAW_SKILL_REMOVE_OK__") == true {
            Self.unmarkTrustedSkill(skill.name)
            await loadSkills()
            showSuccessMessage("Removed skill \(skill.name)")
        } else {
            let trimmed = output?.trimmingCharacters(in: .whitespacesAndNewlines)
            showErrorMessage("Failed to remove \(skill.name): \(trimmed?.isEmpty == false ? trimmed! : "unknown error")")
        }
    }

    /// Parse `openclaw skills info <name>` output
    static func parseSkillInfo(output: String?, skillName: String) -> SkillDetailInfo? {
        guard let output = output else { return nil }

        var status = ""
        var description = ""
        var source = ""
        var path = ""
        var requirements: [String] = []
        var isReady = false

        var inRequirements = false
        var inDescription = true

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip noise lines
            if trimmed.hasPrefix("[agent-scope]") || trimmed.hasPrefix("Config warnings:")
                || trimmed.hasPrefix("- plugins.") || trimmed.isEmpty { continue }
            if trimmed.hasPrefix("│") || trimmed.hasPrefix("◇") || trimmed.hasPrefix("├") { continue }

            // Status line: "📦 brainstorming ✓ Ready" or "🎮 discord ✗ Missing requirements"
            if trimmed.contains("Ready") || trimmed.contains("Missing") {
                if trimmed.contains("Ready") {
                    status = "Ready"
                    isReady = true
                } else {
                    status = "Missing requirements"
                    isReady = false
                }
                inDescription = true
                continue
            }

            if trimmed.hasPrefix("Details:") {
                inDescription = false
                inRequirements = false
                continue
            }

            if trimmed.hasPrefix("Requirements:") {
                inDescription = false
                inRequirements = true
                continue
            }

            if trimmed.hasPrefix("Tip:") {
                break
            }

            if trimmed.hasPrefix("Source:") {
                source = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                continue
            }

            if trimmed.hasPrefix("Path:") {
                path = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                continue
            }

            if inRequirements {
                if trimmed.hasPrefix("Config:") || trimmed.hasPrefix("Bins:") {
                    requirements.append(trimmed)
                }
                continue
            }

            if inDescription && !trimmed.hasPrefix("Details:") && !trimmed.hasPrefix("Source:")
                && !trimmed.hasPrefix("Path:") {
                if !description.isEmpty { description += " " }
                description += trimmed
            }
        }

        return SkillDetailInfo(
            name: skillName,
            status: status,
            isReady: isReady,
            description: description,
            source: source,
            path: path,
            requirements: requirements
        )
    }

    // internal (not private): also used by the ChannelManagement extension
    // split out in P1.3.
    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
