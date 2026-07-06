import Foundation

enum SkillInstallStateStore {
    struct Entry: Codable, Equatable {
        let skillName: String
        let skillRevision: String
        let catalogRevision: String
        let relativePath: String
        let repositoryIdentifier: String
        let installedAt: Date
    }

    private struct Store: Codable {
        var version: Int
        var entries: [Entry]
    }

    private static let storeVersion = 1

    private static var markerURL: URL {
        URL(fileURLWithPath: NSString(string: "~/.openclaw/getclowhub-skill-install-state.json").expandingTildeInPath)
    }

    static func load() -> [String: Entry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = try? Data(contentsOf: markerURL),
              let store = try? decoder.decode(Store.self, from: data),
              store.version == storeVersion else {
            return [:]
        }

        return store.entries.reduce(into: [:]) { result, entry in
            result[entry.skillName] = entry
        }
    }

    static func recordInstall(
        skillName: String,
        skillRevision: String?,
        catalogRevision: String?,
        relativePath: String,
        repositoryIdentifier: String = SkillCatalogService.repositoryIdentifier,
        installedAt: Date = Date()
    ) {
        let trimmedName = skillName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSkillRevision = skillRevision?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedCatalogRevision = catalogRevision?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedRelativePath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRepositoryIdentifier = repositoryIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty,
              !trimmedSkillRevision.isEmpty,
              !trimmedCatalogRevision.isEmpty,
              !trimmedRelativePath.isEmpty,
              !trimmedRepositoryIdentifier.isEmpty else {
            return
        }

        var entries = load()
        entries[trimmedName] = Entry(
            skillName: trimmedName,
            skillRevision: trimmedSkillRevision,
            catalogRevision: trimmedCatalogRevision,
            relativePath: trimmedRelativePath,
            repositoryIdentifier: trimmedRepositoryIdentifier,
            installedAt: installedAt
        )
        write(entries)
    }

    static func remove(_ skillName: String) {
        let trimmedName = skillName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        var entries = load()
        entries.removeValue(forKey: trimmedName)
        write(entries)
    }

    static func hasUpdate(
        skillName: String,
        currentSkillRevision: String?,
        currentCatalogRevision: String?,
        states: [String: Entry]
    ) -> Bool {
        let trimmedSkillRevision = currentSkillRevision?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedCatalogRevision = currentCatalogRevision?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedSkillRevision.isEmpty,
              !trimmedCatalogRevision.isEmpty,
              let entry = states[skillName],
              entry.repositoryIdentifier == SkillCatalogService.repositoryIdentifier else {
            return false
        }

        return entry.skillRevision != trimmedSkillRevision
    }

    private static func write(_ entriesByName: [String: Entry]) {
        try? FileManager.default.createDirectory(
            at: markerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let entries = entriesByName.values.sorted {
            $0.skillName.localizedCaseInsensitiveCompare($1.skillName) == .orderedAscending
        }
        let store = Store(version: storeVersion, entries: entries)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(store) {
            try? data.write(to: markerURL, options: .atomic)
        }
    }
}
