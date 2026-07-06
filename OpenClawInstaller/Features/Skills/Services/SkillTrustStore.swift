import Foundation

enum SkillTrustStore {
    private static var markerURL: URL {
        URL(fileURLWithPath: NSString(string: "~/.openclaw/getclawhub-trusted-skills.json").expandingTildeInPath)
    }

    static func load() -> Set<String> {
        guard let data = try? Data(contentsOf: markerURL),
              let names = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(names)
    }

    static func mark(_ skillName: String) {
        let trimmed = skillName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var names = load()
        names.insert(trimmed)
        write(names)
    }

    static func unmark(_ skillName: String) {
        let trimmed = skillName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var names = load()
        names.remove(trimmed)
        write(names)
    }

    private static func write(_ names: Set<String>) {
        try? FileManager.default.createDirectory(
            at: markerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let sorted = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if let data = try? JSONEncoder().encode(sorted) {
            try? data.write(to: markerURL, options: .atomic)
        }
    }
}
