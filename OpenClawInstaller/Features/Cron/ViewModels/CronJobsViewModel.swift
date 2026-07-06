import Combine
import Foundation

@MainActor
final class CronJobsViewModel: ObservableObject {
    @Published var cronJobs: [CronJobInfo] = []
    @Published var isLoadingCronJobs = false
    @Published var hasLoadedCronJobs = false
    @Published var cronJobsLoadError: String?
}
