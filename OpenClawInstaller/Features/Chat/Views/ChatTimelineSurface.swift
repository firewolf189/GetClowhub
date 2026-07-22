import SwiftUI

struct ChatTimelineSurface: View {
    let snapshot: ChatTimelineSnapshot
    let proxy: ScrollViewProxy
    let columnMaxWidth: CGFloat
    /// Messages above the current tail window (not rendered). > 0 shows the
    /// "load earlier" row at the top.
    var hiddenEarlierCount: Int = 0
    /// Cold-load in progress and nothing to show yet — render a lightweight
    /// placeholder instead of a blank timeline.
    var isLoadingHistory: Bool = false
    var onLoadEarlier: () -> Void = {}
    let onConfirmEditResend: (UUID, String) -> Void
    let onCancel: (UUID) -> Void
    let onRetryConnection: (UUID) -> Void

    var body: some View {
        if isLoadingHistory {
            VStack(spacing: 10) {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text(I18n.t("dashboard.chat.loadingSession"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            timeline
        }
    }

    private var timeline: some View {
        ScrollView(showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 0)

                LazyVStack(spacing: 16) {
                    Color.clear
                        .frame(width: 0, height: 0)
                        .id("chatTop")

                    if hiddenEarlierCount > 0 {
                        loadEarlierRow
                    }

                    ForEach(snapshot.messageRows) { message in
                        if message.scrollTargetId != nil {
                            BackgroundTaskNotification(message: message, scrollProxy: proxy)
                                .id(message.id)
                        } else {
                            ChatBubble(
                                message: message,
                                onConfirmEditResend: onConfirmEditResend,
                                onCancel: onCancel,
                                onRetryConnection: onRetryConnection
                            )
                            .equatable()
                            .id(message.id)
                        }
                    }

                    ForEach(snapshot.loadingRows) { loadingMsg in
                        ThinkingIndicator(
                            message: loadingMsg,
                            onRetryConnection: onRetryConnection
                        )
                        .equatable()
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

    private var loadEarlierRow: some View {
        Button {
            // Anchor the viewport to today's top row so the newly inserted
            // batch doesn't visually shove the conversation downward.
            let anchorId = snapshot.messageRows.first?.id
            onLoadEarlier()
            if let anchorId {
                DispatchQueue.main.async {
                    proxy.scrollTo(anchorId, anchor: .top)
                }
            }
        } label: {
            Text(I18n.format("dashboard.chat.loadEarlier", String(hiddenEarlierCount)))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}
