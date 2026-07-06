import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let cronView = read("OpenClawInstaller/Features/Cron/Views/CronTabView.swift")
let cronViewModel = read("OpenClawInstaller/Features/Cron/ViewModels/CronJobsViewModel.swift")
let cronManagement = read("OpenClawInstaller/Features/Cron/CronManagement.swift")

require(
    !cronView.contains("ProgressView()"),
    "Cron tab should not show an indeterminate spinner while loading."
)
require(
    cronView.contains("cronJobsLoadError"),
    "Cron tab should render a dedicated load-error state."
)
require(
    cronView.contains("hasLoadedCronJobs"),
    "Cron tab should distinguish not-yet-loaded from a real empty list."
)
require(
    cronView.contains(#"Image(systemName: "exclamationmark.triangle")"#),
    "Cron load failures should use a static warning icon instead of a spinner."
)
require(
    cronView.contains(#"systemImage: "clock.badge""#),
    "Cron initial loading should use a static clock icon."
)
require(
    cronView.contains("Task { await viewModel.loadCronJobs() }"),
    "Cron load-error state should expose a retry action."
)
require(
    cronView.contains(#"I18n.t("dashboard.cron.refreshing")"#),
    "Cron tab should show a quiet refresh label when existing jobs are refreshing."
)

require(
    cronViewModel.contains("@Published var hasLoadedCronJobs = false"),
    "CronJobsViewModel should track whether cron jobs have completed at least one load."
)
require(
    cronViewModel.contains("@Published var cronJobsLoadError: String?"),
    "CronJobsViewModel should expose cron list load errors to the UI."
)
require(
    cronManagement.contains("defer {") &&
        cronManagement.contains("isLoadingCronJobs = false") &&
        cronManagement.contains("hasLoadedCronJobs = true"),
    "loadCronJobs should always clear loading and mark the first load as complete."
)
require(
    cronManagement.contains("cronJobsLoadError = Self.cronJobLoadErrorMessage(output: output)"),
    "loadCronJobs should set a user-facing error when the cron list output is not parseable."
)
require(
    cronManagement.contains("cronJobListOutputContainsJSON"),
    "Cron management should distinguish an empty JSON list from invalid command output."
)

print("Cron static loading state verification passed")
