import Foundation

@MainActor
final class ChatViewModel {
    let runtimeState: ChatRuntimeState
    let taskState: TaskActivityState

    init(
        runtimeState: ChatRuntimeState? = nil,
        taskState: TaskActivityState? = nil
    ) {
        self.runtimeState = runtimeState ?? ChatRuntimeState()
        self.taskState = taskState ?? TaskActivityState()
    }
}
