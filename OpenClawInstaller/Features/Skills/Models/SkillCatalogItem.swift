import Foundation

struct SkillCatalogItem: Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String
    let description: String
    let documentationMarkdown: String
    let isRecommended: Bool
    let tags: [String]
    let sortOrder: Int
    let relativePath: String
    let iconURL: URL?
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
