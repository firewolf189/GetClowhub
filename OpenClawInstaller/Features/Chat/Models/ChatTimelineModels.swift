import Foundation

struct ChatTimelineSnapshot: Equatable {
    let messageRows: [ChatMessageRowModel]
    let loadingRows: [ChatLoadingRowModel]

    static func build(
        messages: [ChatMessage],
        activeStreamStatesByMessageId: [UUID: ChatActiveStreamState],
        highlightedMessageId: UUID?,
        highlightedMessageFlashOn: Bool
    ) -> ChatTimelineSnapshot {
        let richMarkdownMessageIds = MarkdownRenderPolicy.recentRichMessageIds(in: messages)
        var messageRows: [ChatMessageRowModel] = []
        var loadingRows: [ChatLoadingRowModel] = []

        for message in messages {
            let activeStreamState = activeStreamStatesByMessageId[message.id]
            let isLoadingPlaceholder = message.role == .assistant
                && message.content.isEmpty
                && message.attachments.isEmpty
                && message.taskStatus == .loading

            if isLoadingPlaceholder && activeStreamState == nil {
                loadingRows.append(ChatLoadingRowModel(message: message))
                continue
            }

            messageRows.append(
                ChatMessageRowModel(
                    message: message,
                    visibleContent: activeStreamState?.visibleDraftText ?? message.content,
                    activityEvents: activeStreamState?.activityEvents ?? message.activityEvents,
                    isStreamingDraft: activeStreamState != nil,
                    allowsRichMarkdown: activeStreamState == nil && richMarkdownMessageIds.contains(message.id),
                    isJumpHighlighted: highlightedMessageId == message.id && highlightedMessageFlashOn
                )
            )
        }

        return ChatTimelineSnapshot(messageRows: messageRows, loadingRows: loadingRows)
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
    let visibleContent: String
    let isStreamingDraft: Bool
    let allowsRichMarkdown: Bool
    let isJumpHighlighted: Bool

    init(
        message: ChatMessage,
        visibleContent: String,
        activityEvents: [ChatActivityEvent],
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
        self.visibleContent = visibleContent
        self.isStreamingDraft = isStreamingDraft
        self.allowsRichMarkdown = allowsRichMarkdown
        self.isJumpHighlighted = isJumpHighlighted
    }
}

struct ChatLoadingRowModel: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date?
    let activityEvents: [ChatActivityEvent]

    init(message: ChatMessage) {
        self.id = message.id
        self.timestamp = message.timestamp
        self.activityEvents = message.activityEvents
    }
}
