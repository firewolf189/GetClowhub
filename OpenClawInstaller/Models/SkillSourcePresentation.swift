import Foundation

enum SkillSourceKind: Hashable {
    case builtIn
    case trusted
    case external
}

struct SkillSourcePresentation {
    let source: String

    var kind: SkillSourceKind {
        switch source {
        case "openclaw-bundled":
            return .builtIn
        case "openclaw-extra", "getclawhub-trusted":
            return .trusted
        default:
            return .external
        }
    }

    var label: String {
        switch kind {
        case .builtIn:
            return "Built-in"
        case .trusted:
            return "Trusted"
        case .external:
            return "External"
        }
    }

    var detail: String {
        source
    }

    var isRemovable: Bool {
        kind != .builtIn
    }
}
