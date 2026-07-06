import Foundation

struct ChannelInfo: Identifiable {
    let id = UUID()
    let name: String
    let account: String
    let enabled: Bool
    let configured: Bool
    let linked: Bool
    let error: String?
    let statusTags: [String]
}
