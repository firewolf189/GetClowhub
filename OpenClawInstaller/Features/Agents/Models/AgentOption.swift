import Foundation

struct AgentOption: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let description: String
    let model: String
    let division: String
}

struct ModelOption: Identifiable {
    let id: String
    let name: String
    let tags: [String]
    let runtimeId: String

    init(id: String, name: String, tags: [String], runtimeId: String? = nil) {
        self.id = id
        self.name = name
        self.tags = tags
        self.runtimeId = runtimeId ?? id
    }
}
