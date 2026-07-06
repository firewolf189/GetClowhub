import Combine
import Foundation

@MainActor
final class ChannelListViewModel: ObservableObject {
    @Published var channels: [ChannelInfo] = []
    @Published var isLoadingChannels = false
}
