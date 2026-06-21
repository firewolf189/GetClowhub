import Foundation

enum PluginCatalogSource: String, Codable, Hashable, Identifiable {
    case all
    case recommend

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "Built-in"
        case .recommend:
            return "Recommend"
        }
    }
}

struct PluginCatalogItem: Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String
    let description: String
    let longDescription: String
    let version: String
    let developerName: String
    let category: String
    let capabilities: [String]
    let keywords: [String]
    let relativePath: String
    let source: PluginCatalogSource
    let iconURL: URL?
    let repositoryURL: String?
    let homepageURL: String?
    let openClawPluginID: String
    let isOpenClawInstallable: Bool

    var isRecommended: Bool {
        source == .recommend
    }
}
