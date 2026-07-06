import Combine
import Foundation

@MainActor
final class SessionNavigationViewModel: ObservableObject {
    let state: SessionNavigationState
    let chatSessionStore: ChatSessionStore

    private var cancellables = Set<AnyCancellable>()

    init(
        state: SessionNavigationState? = nil,
        chatSessionStore: ChatSessionStore? = nil
    ) {
        self.state = state ?? SessionNavigationState()
        self.chatSessionStore = chatSessionStore ?? ChatSessionStore()

        self.state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        self.chatSessionStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}
