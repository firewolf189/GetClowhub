import Foundation

struct ChatTimelineSnapshot: Equatable {
    let messageRows: [ChatMessageRowModel]
    let loadingRows: [ChatLoadingRowModel]

    static func build(
        messages: [ChatMessage],
        activeStreamStatesByMessageId: [UUID: ChatActiveStreamState],
        runStatesByMessageId: [UUID: ChatRunPresentationState],
        highlightedMessageId: UUID?,
        highlightedMessageFlashOn: Bool
    ) -> ChatTimelineSnapshot {
        let richMarkdownMessageIds = MarkdownRenderPolicy.recentRichMessageIds(in: messages)
        var messageRows: [ChatMessageRowModel] = []
        var loadingRows: [ChatLoadingRowModel] = []

        for message in messages {
            let activeStreamState = activeStreamStatesByMessageId[message.id]
            let runState = runStatesByMessageId[message.id]
            let runPhase = runState?.phase
            let isLoadingPlaceholder = message.role == .assistant
                && message.content.isEmpty
                && message.attachments.isEmpty
                && message.taskStatus == .loading

            if isLoadingPlaceholder && activeStreamState == nil {
                loadingRows.append(ChatLoadingRowModel(message: message, runState: runState))
                continue
            }

            messageRows.append(
                ChatMessageRowModel(
                    message: message,
                    visibleContent: activeStreamState?.visibleDraftText ?? message.content,
                    activityEvents: activeStreamState?.activityEvents ?? message.activityEvents,
                    runState: runState,
                    isStreamingDraft: activeStreamState != nil,
                    allowsRichMarkdown: activeStreamState == nil
                        && runPhase?.isTerminal != false
                        && richMarkdownMessageIds.contains(message.id),
                    isJumpHighlighted: highlightedMessageId == message.id && highlightedMessageFlashOn
                )
            )
        }

        return ChatTimelineSnapshot(messageRows: messageRows, loadingRows: loadingRows)
    }
}

/// Memoizes `ChatTimelineSnapshot.build`. DashboardView renders far more often
/// than the timeline inputs change (shimmer animation, composer typing, layout
/// passes), and `build` copies every message row — running it per render was
/// the amplifier of the 2026-07-21 main-thread layout livelock. Equality checks
/// on unchanged inputs are near-free thanks to CoW storage identity.
@MainActor
final class ChatTimelineSnapshotCache {
    private struct Inputs: Equatable {
        let messages: [ChatMessage]
        let activeStreamStatesByMessageId: [UUID: ChatActiveStreamState]
        let runStatesByMessageId: [UUID: ChatRunPresentationState]
        let highlightedMessageId: UUID?
        let highlightedMessageFlashOn: Bool
    }

    private var inputs: Inputs?
    private var cached: ChatTimelineSnapshot?

    func snapshot(
        messages: [ChatMessage],
        activeStreamStatesByMessageId: [UUID: ChatActiveStreamState],
        runStatesByMessageId: [UUID: ChatRunPresentationState],
        highlightedMessageId: UUID?,
        highlightedMessageFlashOn: Bool
    ) -> ChatTimelineSnapshot {
        let next = Inputs(
            messages: messages,
            activeStreamStatesByMessageId: activeStreamStatesByMessageId,
            runStatesByMessageId: runStatesByMessageId,
            highlightedMessageId: highlightedMessageId,
            highlightedMessageFlashOn: highlightedMessageFlashOn
        )
        if let cached, inputs == next {
            return cached
        }
        let built = ChatTimelineSnapshot.build(
            messages: messages,
            activeStreamStatesByMessageId: activeStreamStatesByMessageId,
            runStatesByMessageId: runStatesByMessageId,
            highlightedMessageId: highlightedMessageId,
            highlightedMessageFlashOn: highlightedMessageFlashOn
        )
        inputs = next
        cached = built
        return built
    }
}

struct ChatMessageRowModel: Identifiable, Equatable {
    let id: UUID
    let role: ChatMessage.ChatRole
    let content: String
    let agentId: String?
    let agentEmoji: String?
    let attachments: [URL]
    let taskStatus: ChatMessage.TaskStatus
    let scrollTargetId: UUID?
    let timestamp: Date?
    let completedAt: Date?
    let activityEvents: [ChatActivityEvent]
    let runState: ChatRunPresentationState?
    let visibleContent: String
    let isStreamingDraft: Bool
    let allowsRichMarkdown: Bool
    let isJumpHighlighted: Bool

    init(
        message: ChatMessage,
        visibleContent: String,
        activityEvents: [ChatActivityEvent],
        runState: ChatRunPresentationState?,
        isStreamingDraft: Bool,
        allowsRichMarkdown: Bool,
        isJumpHighlighted: Bool
    ) {
        self.id = message.id
        self.role = message.role
        self.content = visibleContent
        self.agentId = message.agentId
        self.agentEmoji = message.agentEmoji
        self.attachments = message.attachments
        self.taskStatus = message.taskStatus
        self.scrollTargetId = message.scrollTargetId
        self.timestamp = message.timestamp
        self.completedAt = message.completedAt
        self.activityEvents = activityEvents
        self.runState = runState
        self.visibleContent = visibleContent
        self.isStreamingDraft = isStreamingDraft
        self.allowsRichMarkdown = allowsRichMarkdown
        self.isJumpHighlighted = isJumpHighlighted
    }

    var runPhase: ChatRunPhase? { runState?.phase }
}

struct ChatLoadingRowModel: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date?
    let activityEvents: [ChatActivityEvent]
    let runState: ChatRunPresentationState?

    init(message: ChatMessage, runState: ChatRunPresentationState?) {
        self.id = message.id
        self.timestamp = message.timestamp
        self.activityEvents = message.activityEvents
        self.runState = runState
    }


    var runPhase: ChatRunPhase? { runState?.phase }
}
