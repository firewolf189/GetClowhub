import Foundation

enum SkillStatus: String {
    case ready = "ready"
    case missing = "missing"
}

struct SkillsSummary {
    var ready: Int = 0
    var total: Int = 0
}

struct SkillInfo: Identifiable {
    let id = UUID()
    let name: String
    let status: SkillStatus
    let description: String
    let source: String
}

struct SkillDetailInfo: Identifiable {
    let id = UUID()
    let name: String
    let status: String
    let isReady: Bool
    let description: String
    let source: String
    let path: String
    let requirements: [String]
}
