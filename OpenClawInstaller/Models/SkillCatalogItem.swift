import Foundation

enum SkillCatalogCategory: String, CaseIterable, Codable, Hashable, Identifiable {
    case builtIn = "built-in"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtIn:
            return "Built-in"
        }
    }
}

struct SkillCatalogItem: Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String
    let description: String
    let documentationMarkdown: String
    let category: SkillCatalogCategory
    let relativePath: String
    let iconURL: URL?
}

enum SkillLibrarySection: String, CaseIterable, Hashable, Identifiable {
    case builtIn
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtIn:
            return "Built-in"
        case .custom:
            return "Custom"
        }
    }

    static func section(
        forSkillName skillName: String,
        catalogItemsByName: [String: SkillCatalogItem]
    ) -> SkillLibrarySection {
        catalogItemsByName[skillName] == nil ? .custom : .builtIn
    }
}

enum SkillNameIndex {
    static func firstByName<Value>(_ values: [Value], name: (Value) -> String) -> [String: Value] {
        values.reduce(into: [:]) { result, value in
            let key = name(value)
            guard result[key] == nil else { return }
            result[key] = value
        }
    }
}
