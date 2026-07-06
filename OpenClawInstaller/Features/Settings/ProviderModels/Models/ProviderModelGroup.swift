import Foundation

struct ProviderModelGroup: Identifiable {
    let providerKey: String
    let displayName: String
    let models: [ModelOption]

    var id: String { providerKey }
}
