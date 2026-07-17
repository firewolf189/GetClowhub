import SwiftUI

struct ChatTimelineSurface: View {
    let snapshot: ChatTimelineSnapshot
    @ObservedObject var taskState: TaskActivityState
    let autoBackgroundAfterSeconds: Int?
    let proxy: ScrollViewProxy
    let columnMaxWidth: CGFloat
    let onConfirmEditResend: (UUID, String) -> Void
    let onCancel: (UUID) -> Void
    let onMoveToBackground: (UUID) -> Void

    var body: some View {
        ScrollView(showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 0)

                LazyVStack(spacing: 16) {
                    Color.clear
                        .frame(width: 0, height: 0)
                        .id("chatTop")

                    ForEach(snapshot.messageRows) { message in
                        if message.scrollTargetId != nil {
                            BackgroundTaskNotification(message: message, scrollProxy: proxy)
                                .id(message.id)
                        } else {
                            ChatBubble(
                                message: message,
                                onConfirmEditResend: onConfirmEditResend,
                                onCancel: onCancel
                            )
                            .equatable()
                            .id(message.id)
                        }
                    }

                    ForEach(snapshot.loadingRows) { loadingMsg in
                        ThinkingIndicator(
                            message: loadingMsg,
                            taskState: taskState,
                            autoBackgroundAfterSeconds: autoBackgroundAfterSeconds,
                            onMoveToBackground: onMoveToBackground
                        )
                        .id("loading-\(loadingMsg.id)")
                    }

                    Color.clear
                        .frame(width: 0, height: 0)
                        .id("chatBottom")
                }
                .frame(maxWidth: columnMaxWidth)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }
}
