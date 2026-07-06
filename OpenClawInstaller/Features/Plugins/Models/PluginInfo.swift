import Foundation

enum PluginOrigin: String {
    case bundled
    case global
    case unknown
}

struct PluginInfo: Identifiable {
    let id = UUID()
    let channel: String
    let pluginId: String
    var installed: Bool
    var enabled: Bool
    var source: String
    var version: String
    var origin: PluginOrigin
    var channelIds: [String] = []
}
