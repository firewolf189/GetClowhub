import Combine
import Foundation

@MainActor
final class StatusSummaryViewModel: ObservableObject {
    @Published var sessionsSummary: SessionsSummary?
    @Published var isLoadingSessionsSummary = false
}
