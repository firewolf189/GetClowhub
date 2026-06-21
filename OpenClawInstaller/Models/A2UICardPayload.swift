import Foundation

struct A2UICardPayload: Codable {
    let version: String
    let title: String?
    let components: [A2UIComponent]

    init(version: String = "0.1", title: String? = nil, components: [A2UIComponent]) {
        self.version = version
        self.title = title
        self.components = components
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case title
        case components
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "0.1"
        title = try container.decodeIfPresent(String.self, forKey: .title)
        components = try container.decode([A2UIComponent].self, forKey: .components)
    }

    var componentCount: Int {
        components.reduce(0) { $0 + $1.componentCount }
    }

    var componentDepth: Int {
        components.map(\.componentDepth).max() ?? 0
    }
}

struct A2UIComponent: Codable {
    let component: A2UIComponentType
    let title: String?
    let subtitle: String?
    let text: String?
    let url: String?
    let icon: String?
    let name: String?
    let items: [String]
    let children: [A2UIComponent]

    var displayText: String {
        text ?? title ?? subtitle ?? ""
    }

    var iconName: String {
        icon ?? name ?? "sparkles"
    }

    var sanitizedURL: URL? {
        guard let url,
              let parsed = URL(string: url),
              let scheme = parsed.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }
        return parsed
    }

    var componentCount: Int {
        1 + children.reduce(0) { $0 + $1.componentCount }
    }

    var componentDepth: Int {
        1 + (children.map(\.componentDepth).max() ?? 0)
    }

    private enum CodingKeys: String, CodingKey {
        case component
        case type
        case title
        case subtitle
        case text
        case url
        case icon
        case name
        case items
        case children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawComponent = try container.decodeIfPresent(String.self, forKey: .component)
            ?? container.decodeIfPresent(String.self, forKey: .type)
            ?? ""
        component = A2UIComponentType(rawValue: rawComponent)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        items = try container.decodeIfPresent([String].self, forKey: .items) ?? []
        children = try container.decodeIfPresent([A2UIComponent].self, forKey: .children) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(component.rawValue, forKey: .component)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(icon, forKey: .icon)
        try container.encodeIfPresent(name, forKey: .name)
        if !items.isEmpty { try container.encode(items, forKey: .items) }
        if !children.isEmpty { try container.encode(children, forKey: .children) }
    }
}

enum A2UIComponentType: Equatable, Codable {
    case card
    case text
    case image
    case icon
    case list
    case row
    case column
    case divider
    case unsupported(String)

    init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "card": self = .card
        case "text": self = .text
        case "image": self = .image
        case "icon": self = .icon
        case "list": self = .list
        case "row": self = .row
        case "column": self = .column
        case "divider": self = .divider
        default: self = .unsupported(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .card: return "Card"
        case .text: return "Text"
        case .image: return "Image"
        case .icon: return "Icon"
        case .list: return "List"
        case .row: return "Row"
        case .column: return "Column"
        case .divider: return "Divider"
        case .unsupported(let value): return value
        }
    }
}

enum A2UICardParser {
    static let maxPayloadBytes = 64 * 1024
    static let maxComponentDepth = 8
    static let maxComponentCount = 80

    // Public entry point for assistant rendering: A2UICardParser.parse(_:)
    static func parse(_ content: String) -> A2UICardPayload? {
        guard let json = extractA2UIBlock(from: content),
              json.utf8.count <= maxPayloadBytes,
              let data = json.data(using: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
        guard let payload = try? decoder.decode(A2UICardPayload.self, from: data),
              payload.componentDepth <= maxComponentDepth,
              payload.componentCount <= maxComponentCount else {
            return nil
        }
        return payload
    }

    private static func extractA2UIBlock(from content: String) -> String? {
        // Matches fenced blocks beginning with ```a2ui and keeps ordinary Markdown untouched.
        let pattern = #"(?s)```a2ui\s*(.*?)\s*```"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, range: range),
              match.numberOfRanges >= 2,
              let bodyRange = Range(match.range(at: 1), in: content) else {
            return nil
        }

        return String(content[bodyRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
