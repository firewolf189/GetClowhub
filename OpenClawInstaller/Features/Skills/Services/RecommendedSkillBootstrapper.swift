import Foundation

@MainActor
final class RecommendedSkillBootstrapper {
    private struct Marker: Codable {
        var version: Int
        var attemptedSkillNames: [String]
        var installedSkillNames: [String]
        var failedSkillNames: [String]
        var completedAt: Date?
    }

    private enum Constants {
        static let markerVersion = 1
        static let markerFilename = "getclowhub-recommended-skills-bootstrap.json"
        static let installSentinel = "__OPENCLAW_RECOMMENDED_SKILL_INSTALL_OK__"
    }

    private let openclawService: OpenClawService
    private var hasStarted = false

    init(openclawService: OpenClawService) {
        self.openclawService = openclawService
    }

    func bootstrapRecommendedSkillsIfNeeded() async {
        guard !hasStarted else { return }
        guard openclawService.status == .running else { return }
        guard !isCompleted else { return }
        guard let bundledCatalogURL else { return }

        hasStarted = true
        defer { hasStarted = false }

        let catalog: [SkillCatalogItem]
        do {
            catalog = try SkillCatalogService.parseCatalog(rootURL: bundledCatalogURL)
        } catch {
            return
        }

        let recommendedSkills = catalog.filter(\.isRecommended)
        let catalogRevision = SkillCatalogService.catalogRevision(cacheURL: bundledCatalogURL)
        guard !recommendedSkills.isEmpty else {
            writeMarker(
                attemptedSkillNames: [],
                installedSkillNames: [],
                failedSkillNames: [],
                completedAt: Date()
            )
            return
        }

        let installedNames = await loadInstalledSkillNames()
        let missingSkills = recommendedSkills.filter { !installedNames.contains($0.name) }

        var attempted: [String] = []
        var installed: [String] = recommendedSkills
            .filter { installedNames.contains($0.name) }
            .map(\.name)
        var failed: [String] = []

        for skillName in installed {
            SkillTrustStore.mark(skillName)
        }

        for skill in missingSkills {
            attempted.append(skill.name)
            let command = SkillCatalogService.installCommand(for: skill, cacheURL: bundledCatalogURL)
            let output = await openclawService.runCommand(
                "(\(command) 2>&1 && echo \(Constants.installSentinel)) | sed 's/\\x1b\\[[0-9;]*m//g'",
                timeout: 180
            )

            if output?.contains(Constants.installSentinel) == true {
                installed.append(skill.name)
                SkillTrustStore.mark(skill.name)
                SkillInstallStateStore.recordInstall(
                    skillName: skill.name,
                    skillRevision: SkillCatalogService.skillRevision(for: skill, cacheURL: bundledCatalogURL),
                    catalogRevision: catalogRevision,
                    relativePath: skill.relativePath
                )
            } else {
                failed.append(skill.name)
            }
        }

        let completed = failed.isEmpty && Set(installed).isSuperset(of: recommendedSkills.map(\.name))
        writeMarker(
            attemptedSkillNames: attempted,
            installedSkillNames: installed,
            failedSkillNames: failed,
            completedAt: completed ? Date() : nil
        )
    }

    private var bundledCatalogURL: URL? {
        Bundle.main.url(forResource: "BundledSkillCatalog", withExtension: nil)
    }

    private var markerURL: URL {
        URL(fileURLWithPath: NSString(string: "~/.openclaw/\(Constants.markerFilename)").expandingTildeInPath)
    }

    private var isCompleted: Bool {
        guard let data = try? Data(contentsOf: markerURL),
              let marker = try? JSONDecoder().decode(Marker.self, from: data) else {
            return false
        }
        return marker.version == Constants.markerVersion && marker.completedAt != nil
    }

    private func loadInstalledSkillNames() async -> Set<String> {
        let output = await openclawService.runCommand(
            "openclaw skills list 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'",
            timeout: 30
        )
        return parseInstalledSkillNames(output: output)
    }

    private func parseInstalledSkillNames(output: String?) -> Set<String> {
        guard let output else { return [] }

        var names = Set<String>()
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("│") else { continue }
            guard !(trimmed.contains("Status") && trimmed.contains("Skill")) else { continue }

            let cells = trimmed.components(separatedBy: "│")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 3, !cells[1].isEmpty else { continue }

            let name = cells[2]
                .drop(while: { !$0.isASCII })
                .trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                names.insert(name)
            }
        }
        return names
    }

    private func writeMarker(
        attemptedSkillNames: [String],
        installedSkillNames: [String],
        failedSkillNames: [String],
        completedAt: Date?
    ) {
        try? FileManager.default.createDirectory(
            at: markerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let marker = Marker(
            version: Constants.markerVersion,
            attemptedSkillNames: attemptedSkillNames.sorted(),
            installedSkillNames: Array(Set(installedSkillNames)).sorted(),
            failedSkillNames: failedSkillNames.sorted(),
            completedAt: completedAt
        )
        if let data = try? JSONEncoder().encode(marker) {
            try? data.write(to: markerURL, options: .atomic)
        }
    }
}
