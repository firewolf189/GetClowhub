import Foundation

struct ModelOverview: Equatable {
    var defaultModel: String = "-"
    var imageModel: String?
    var fallbacks: String = ""
    var imageFallbacks: String = ""
    var aliases: String = ""
}

struct ModelInfo: Identifiable, Equatable {
    let id = UUID()
    let modelId: String
    let input: String
    let contextLength: String
    let local: Bool
    let authenticated: Bool
    var isDefault: Bool
    let supportsImage: Bool
    let tags: String
}
