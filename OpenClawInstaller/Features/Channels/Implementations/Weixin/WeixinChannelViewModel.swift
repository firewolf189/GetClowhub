import AppKit
import Combine
import Foundation

enum WeixinLoginStatus: Equatable {
    case idle
    case waitingScan
    case success
    case failed(String)
}

@MainActor
final class WeixinChannelViewModel: ObservableObject {
    @Published var qrImage: NSImage?
    @Published var loginStatus: WeixinLoginStatus = .idle

    var loginProcess: Process?
}
