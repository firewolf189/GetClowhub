import Combine
import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    let runtimeState: ChatRuntimeState
    let taskState: TaskActivityState

    private var cancellables = Set<AnyCancellable>()

    init(
        runtimeState: ChatRuntimeState? = nil,
        taskState: TaskActivityState? = nil
    ) {
        self.runtimeState = runtimeState ?? ChatRuntimeState()
        self.taskState = taskState ?? TaskActivityState()

        self.runtimeState.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        self.taskState.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}
