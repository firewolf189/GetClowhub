import Foundation

struct ChatActiveStreamState: Equatable {
    let messageId: UUID
    let visibleDraftText: String
    let activityEvents: [ChatActivityEvent]

    init(
        messageId: UUID,
        visibleDraftText: String,
        activityEvents: [ChatActivityEvent]
    ) {
        self.messageId = messageId
        self.visibleDraftText = visibleDraftText
        self.activityEvents = activityEvents
    }
}
