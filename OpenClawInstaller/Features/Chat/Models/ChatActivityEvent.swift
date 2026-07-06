import Foundation

struct ChatActivityEvent: Identifiable, Codable, Equatable {
    let id: String
    let kind: Kind
    let count: Int
    let detail: String?
    let details: [String]

    init(kind: Kind, count: Int, detail: String?, ordinal: Int) {
        self.init(kind: kind, count: count, details: detail.map { [$0] } ?? [], ordinal: ordinal)
    }

    init(kind: Kind, count: Int, details: [String], ordinal: Int) {
        self.kind = kind
        self.count = max(1, count)
        self.details = details
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.detail = self.details.first
        self.id = "\(kind.rawValue)-\(self.count)-\(self.details.joined(separator: "|"))-\(ordinal)"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case count
        case detail
        case details
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        count = max(1, try container.decodeIfPresent(Int.self, forKey: .count) ?? 1)
        let decodedDetail = try container.decodeIfPresent(String.self, forKey: .detail)
        let decodedDetails = try container.decodeIfPresent([String].self, forKey: .details)
        details = (decodedDetails ?? decodedDetail.map { [$0] } ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        detail = details.first ?? decodedDetail
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? "\(kind.rawValue)-\(count)-\(details.joined(separator: "|"))"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(count, forKey: .count)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encode(details, forKey: .details)
    }

    enum Kind: String, Codable {
        case loadedTools
        case searchedCode
        case readFiles
        case ranCommands
        case editedFiles
        case createdFiles
        case selectedModel
        case agentUsed
        case agentRecruited
        case toolFailed
        case progressUpdate

        init(gatewayKind: GatewayActivityEvent.Kind) {
            switch gatewayKind {
            case .loadedTools:
                self = .loadedTools
            case .searchedCode:
                self = .searchedCode
            case .readFiles:
                self = .readFiles
            case .ranCommands:
                self = .ranCommands
            case .editedFiles:
                self = .editedFiles
            case .createdFiles:
                self = .createdFiles
            case .selectedModel:
                self = .selectedModel
            case .agentUsed:
                self = .agentUsed
            case .agentRecruited:
                self = .agentRecruited
            case .toolFailed:
                self = .toolFailed
            }
        }

        func title(count: Int) -> String {
            switch self {
            case .loadedTools:
                return "Loaded \(count) \(count == 1 ? "tool" : "tools")"
            case .searchedCode:
                return "Searched code"
            case .readFiles:
                return "Read \(count) \(count == 1 ? "file" : "files")"
            case .ranCommands:
                return "Ran \(count) \(count == 1 ? "command" : "commands")"
            case .editedFiles:
                return count == 1 ? "Edited a file" : "Edited \(count) files"
            case .createdFiles:
                return "Created \(count) \(count == 1 ? "file" : "files")"
            case .selectedModel:
                return "Selected model"
            case .agentUsed:
                return "Used \(count) \(count == 1 ? "agent" : "agents")"
            case .agentRecruited:
                return "Recruited \(count) \(count == 1 ? "agent" : "agents")"
            case .toolFailed:
                return count == 1 ? "Tool failed" : "\(count) tools failed"
            case .progressUpdate:
                return "Progress update"
            }
        }

        var systemImage: String {
            switch self {
            case .loadedTools: return "wrench.and.screwdriver"
            case .searchedCode: return "magnifyingglass"
            case .readFiles: return "doc.text"
            case .ranCommands: return "terminal"
            case .editedFiles: return "pencil"
            case .createdFiles: return "doc.badge.plus"
            case .selectedModel: return "cpu"
            case .agentUsed: return "person.2"
            case .agentRecruited: return "person.crop.circle.badge.plus"
            case .toolFailed: return "exclamationmark.triangle"
            case .progressUpdate: return "text.alignleft"
            }
        }
    }
}
