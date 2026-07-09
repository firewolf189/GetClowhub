#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fputs("FAIL: could not read \(path)\n", stderr)
        exit(1)
    }
    return text
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fputs("FAIL: could not slice source between \(start) and \(end)\n", stderr)
        exit(1)
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")
let sharedState = read("OpenClawInstaller/Features/Settings/Views/SettingsRefreshPresentation.swift")
let billing = read("OpenClawInstaller/Features/Settings/Account/BillingTabView.swift")
let budget = read("OpenClawInstaller/Features/Budget/Views/BudgetTabView.swift")
let status = read("OpenClawInstaller/Features/Status/Views/StatusTabView.swift")
let models = read("OpenClawInstaller/Features/Settings/ProviderModels/ModelsTabView.swift")
let channels = read("OpenClawInstaller/Features/Channels/Views/ChannelsTabView.swift")
let logs = read("OpenClawInstaller/Features/Status/Views/LogsTabView.swift")
let modelsPage = slice(models, from: "struct ModelsTabView: View", to: "// MARK: - Overview Card")
let channelsPage = slice(channels, from: "struct ChannelsTabView: View", to: "// MARK: - Channel Row")

require(
    project.contains("SettingsRefreshPresentation.swift in Sources"),
    "Settings refresh presentation should be a compiled Settings component, not duplicated inside each page."
)
require(
    sharedState.contains("struct SettingsInlineRefreshStatus: View") &&
        sharedState.contains("struct SettingsStaticLoadingPlaceholder: View") &&
        sharedState.contains("settings.refreshing") &&
        !sharedState.contains("ProgressView"),
    "Settings refresh presentation should provide quiet refresh/placeholder views without spinner progress."
)

let pageSources: [(name: String, source: String)] = [
    ("BillingTabView", billing),
    ("BudgetTabView", budget),
    ("StatusTabView", status),
    ("ModelsTabView", modelsPage),
    ("ChannelsTabView", channelsPage),
    ("LogsTabView", logs)
]

for page in pageSources {
    require(!page.source.contains("ProgressView()"), "\(page.name) should not render page-level indeterminate ProgressView spinners.")
}

require(
    billing.contains("SettingsInlineRefreshStatus(isRefreshing: membershipManager.isBillingLoading") &&
        !billing.contains("if membershipManager.isBillingLoading"),
    "Billing should show cached/empty billing content immediately and report refresh quietly."
)
require(
    budget.contains("SettingsInlineRefreshStatus(isRefreshing: viewModel.isLoadingBudgets") &&
        !budget.contains("if viewModel.isLoadingBudgets"),
    "Budget overview should not replace its content with a spinner while refreshing."
)
require(
    status.contains("SettingsInlineRefreshStatus(isRefreshing: viewModel.isLoadingSessionsSummary") &&
        status.contains("SettingsInlineRefreshStatus(isRefreshing: viewModel.isLoadingCronJobs") &&
        status.contains("SettingsInlineRefreshStatus(isRefreshing: viewModel.isLoadingChannels") &&
        !status.contains("if viewModel.isLoadingSessionsSummary") &&
        !status.contains("if viewModel.isLoadingCronJobs") &&
        !status.contains("if viewModel.isLoadingChannels"),
    "Status cards should keep their current/empty content visible while their data refreshes."
)
require(
    models.contains("SettingsStaticLoadingPlaceholder(") &&
        models.contains("SettingsInlineRefreshStatus(isRefreshing: viewModel.isLoadingModels") &&
        !models.contains("if viewModel.isLoadingModels && viewModel.models.isEmpty"),
    "Models should use a static first-load placeholder and quiet refresh status."
)
require(
    channels.contains("SettingsStaticLoadingPlaceholder(") &&
        channels.contains("SettingsInlineRefreshStatus(isRefreshing: viewModel.isLoadingChannels") &&
        !channels.contains("if viewModel.isLoadingChannels && viewModel.channels.isEmpty"),
    "Channels should use a static first-load placeholder and quiet refresh status."
)
require(
    logs.contains("SettingsInlineRefreshStatus(isRefreshing: isLoading") &&
        logs.contains("EmptyLogsView()") &&
        !logs.contains("if isLoading {\n                    ProgressView()"),
    "Logs should not expose auto-refresh as a spinner."
)

print("Settings non-blocking refresh verification passed")
