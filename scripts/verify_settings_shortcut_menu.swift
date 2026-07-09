#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboardURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Features")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("DashboardView.swift")
let settingsPanelURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Features")
    .appendingPathComponent("Settings")
    .appendingPathComponent("Shortcut")
    .appendingPathComponent("SettingsShortcutPanel.swift")
let settingsMenuURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Features")
    .appendingPathComponent("Settings")
    .appendingPathComponent("Shortcut")
    .appendingPathComponent("SettingsShortcutMenu.swift")
let settingsRowsURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Features")
    .appendingPathComponent("Settings")
    .appendingPathComponent("Shortcut")
    .appendingPathComponent("SettingsShortcutRows.swift")
let settingsStyleURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Features")
    .appendingPathComponent("Settings")
    .appendingPathComponent("Shortcut")
    .appendingPathComponent("SettingsShortcutStyle.swift")
let settingsStateURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Features")
    .appendingPathComponent("Settings")
    .appendingPathComponent("Shortcut")
    .appendingPathComponent("SettingsShortcutState.swift")
let settingsBillingSummaryURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Features")
    .appendingPathComponent("Settings")
    .appendingPathComponent("Shortcut")
    .appendingPathComponent("SettingsShortcutBillingSummary.swift")
let configURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Features")
    .appendingPathComponent("Settings")
    .appendingPathComponent("Views")
    .appendingPathComponent("ConfigTabView.swift")
let settingsShellURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Features")
    .appendingPathComponent("Settings")
    .appendingPathComponent("Views")
    .appendingPathComponent("SettingsShellView.swift")
let membershipManagerURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Core")
    .appendingPathComponent("Auth")
    .appendingPathComponent("MembershipManager.swift")

let dashboard = try String(contentsOf: dashboardURL, encoding: .utf8)
let settingsPanel = try String(contentsOf: settingsPanelURL, encoding: .utf8)
let settingsMenu = try String(contentsOf: settingsMenuURL, encoding: .utf8)
let settingsRows = try String(contentsOf: settingsRowsURL, encoding: .utf8)
let settingsStyle = try String(contentsOf: settingsStyleURL, encoding: .utf8)
let settingsBillingSummary = (try? String(contentsOf: settingsBillingSummaryURL, encoding: .utf8)) ?? ""
let settingsShortcutSource = settingsPanel + settingsMenu + settingsRows + settingsStyle + settingsBillingSummary
let settingsState = try String(contentsOf: settingsStateURL, encoding: .utf8)
let config = try String(contentsOf: configURL, encoding: .utf8)
let settingsShell = (try? String(contentsOf: settingsShellURL, encoding: .utf8)) ?? ""
let membershipManager = try String(contentsOf: membershipManagerURL, encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
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

func offset(of needle: String, in haystack: String) -> String.Index {
    guard let range = haystack.range(of: needle) else {
        fputs("FAIL: missing \(needle)\n", stderr)
        exit(1)
    }
    return range.lowerBound
}

let sidebarMainList = slice(
    dashboard,
    from: "private var sidebarMainList: some View",
    to: "private func navRow"
)
let sidebarBottomBar = slice(
    dashboard,
    from: "private var sidebarBottomBar: some View",
    to: "// MARK: - Agents List"
)
let providerSettingsContent = slice(
    config,
    from: "case .provider:\n            settingsScroll {",
    to: "case .budget:"
)
let officialServiceSection = slice(
    config,
    from: "struct GetClawHubServiceSection: View",
    to: "#endif"
)

require(
    !sidebarMainList.contains("navRow(.status"),
    "Status should move into the Settings page instead of staying as a main sidebar entry."
)
require(
    sidebarMainList.contains("navRow(.skills") &&
        sidebarMainList.contains("navRow(.plugins"),
    "Skills and Plugins should remain first-class entries in the main sidebar."
)
let searchChatsOffset = offset(of: "actions.openGlobalSessionSearch()", in: sidebarMainList)
let skillsOffset = offset(of: "navRow(.skills", in: sidebarMainList)
let pluginsOffset = offset(of: "navRow(.plugins", in: sidebarMainList)
let automationOffset = offset(of: "navRow(.tasksLogs", in: sidebarMainList)
let marketOffset = offset(of: "navRow(.market", in: sidebarMainList)
require(
    searchChatsOffset < skillsOffset &&
        skillsOffset < pluginsOffset &&
        pluginsOffset < automationOffset &&
        automationOffset < marketOffset,
    "Sidebar order should be Search chats, Skills, Plugins, Automation, AgentsMarket."
)
require(
    !sidebarMainList.contains("navRow(.budget") &&
        !sidebarMainList.contains("navRow(.billing") &&
        !sidebarMainList.contains("navRow(.config"),
    "Main sidebar should not expose Settings, Budget, or Billing as top-level management rows."
)
require(
    dashboard.contains("SettingsShortcutPanelButton(") &&
        !dashboard.contains("SettingsShortcutPanelHost(") &&
        !dashboard.contains("SettingsShortcutMenu(") &&
        settingsPanel.contains("SettingsShortcutPanelHost(") &&
        settingsPanel.contains("SettingsShortcutMenu(") &&
        settingsMenu.contains("struct SettingsShortcutMenu: View") &&
        !sidebarBottomBar.contains(".popover(isPresented:"),
    "Sidebar bottom bar should expose one Settings button that opens the arrowless shortcut panel."
)
require(
    !dashboard.contains("struct DashboardSettingsShortcutState") &&
        dashboard.contains("settingsShortcut: SettingsShortcutState(") &&
        settingsState.contains("struct SettingsShortcutState: Equatable"),
    "Settings shortcut state should be owned by the Settings feature, not Dashboard."
)
require(
    sidebarBottomBar.contains("SettingsShortcutPanelButton(") &&
        !sidebarBottomBar.contains("SettingsSectionRow(") &&
        !sidebarBottomBar.contains("sparkleUpdater.checkForUpdates") &&
        !sidebarBottomBar.contains("appAppearance = isDark ?"),
    "Sidebar bottom bar should contain only the Settings shortcut, not update or theme controls."
)
require(
    dashboard.contains("onOpenSettingsSection: actions.openSettingsSection") &&
        dashboard.contains("private func openSettingsSection(_ section: SettingsPageSection)") &&
        dashboard.contains("presentationMode = .settings(section)") &&
        !dashboard.contains("openSettingsSection(_ section: SettingsPageSection) {\n        selectedSettingsSection = section") &&
        !dashboard.contains("viewModel.selectedTab = .config"),
    "Settings shortcut menu should open the independent Settings page shell without routing through the main sidebar config tab."
)
require(
    settingsMenu.contains("authManager.logout()"),
    "Settings shortcut menu should call the existing logout flow."
)
require(
    settingsMenu.contains("BillingShortcutSummary") &&
        settingsMenu.contains("BudgetShortcutSummary") &&
        !settingsShortcutSource.contains("DefaultModelShortcutPicker") &&
        !settingsShortcutSource.contains("Picker(\"\", selection: Binding<String>("),
    "Shortcut menu should keep Billing and Budget summaries but not load or show a model picker."
)
require(
        settingsState.contains("struct SettingsShortcutBillingSnapshot: Equatable, Codable") &&
        settingsState.contains("static func current(\n        from membershipManager: MembershipManager?,\n        cacheIdentity: String?") &&
        settingsState.contains("static func persistCurrentRemoteValue(") &&
        settingsState.contains("SettingsShortcutBillingSnapshotCache") &&
        settingsState.contains("billingSnapshot: SettingsShortcutBillingSnapshot") &&
        dashboard.contains("cacheIdentity: authManager.userId ?? authManager.userEmail") &&
        dashboard.contains("SettingsShortcutBillingSnapshot.persistCurrentRemoteValue(") &&
        settingsMenu.contains("BillingShortcutSummary(\n                snapshot: shortcutState.billingSnapshot\n            )") &&
        settingsBillingSummary.contains("struct BillingShortcutSummary: View") &&
        settingsBillingSummary.contains("let snapshot: SettingsShortcutBillingSnapshot") &&
        !settingsBillingSummary.contains("@ObservedObject var membershipManager") &&
        !settingsBillingSummary.contains("membershipManager.isBillingLoading") &&
        !settingsBillingSummary.contains("billing.loading") &&
        dashboard.contains("private func preloadSettingsShortcutData() async") &&
        dashboard.contains("await preloadSettingsShortcutData()") &&
        dashboard.contains("loadSettingsShortcutData: preloadSettingsShortcutData") &&
        membershipManager.contains("@Published var hasLoadedKeysBilling: Bool = false") &&
        membershipManager.contains("guard !isBillingLoading else { return }") &&
        membershipManager.contains("hasLoadedKeysBilling = true"),
    "Settings shortcut should prewarm billing/budget data, avoid duplicate billing fetches, and distinguish loading from a loaded empty result."
)
require(
    !settingsShortcutSource.contains("@State private var isBillingExpanded") &&
        !settingsShortcutSource.contains("@State private var isBudgetExpanded") &&
        !settingsShortcutSource.contains("SettingsShortcutExpandableRow") &&
        settingsRows.contains("SettingsShortcutSummaryRow") &&
        settingsBillingSummary.contains("trailingSummary: billingSummary") &&
        settingsMenu.contains("trailingSummary: budgetSummary") &&
        settingsBillingSummary.contains("meter: billingMeter") &&
        settingsMenu.contains("meter: budgetMeter"),
    "Billing and Budget shortcut rows should be non-expandable rows with inline value summaries and meters."
)
require(
    !settingsMenu.contains("SettingsShortcutActionRow(title: I18n.t(\"Profile\")") &&
        settingsMenu.contains("title: I18n.t(\"All settings\")") &&
        settingsMenu.contains("showsTrailingChevron: false") &&
        !settingsMenu.contains("showsTrailingChevron: true") &&
        !settingsMenu.contains("title: I18n.t(\"All settings\"), systemImage: \"gearshape\")"),
    "Shortcut menu should not expose Profile as a top-level row, and All settings should not show a disclosure chevron."
)
require(
    !settingsMenu.contains("onOpenBudget") &&
        !settingsMenu.contains("action: onOpenBudget") &&
        !settingsMenu.contains("onOpenSettingsSection(.budget)") &&
        settingsMenu.contains("BudgetShortcutSummary(\n                snapshots: shortcutState.budgetSnapshots\n            )") &&
        settingsRows.contains("if let action") &&
        settingsRows.contains("rowContent"),
    "Budget shortcut row should be a read-only summary with no click-to-open behavior."
)
require(
    settingsPanel.contains("anchorAboveSource") &&
        settingsPanel.contains("sourceFrameOnScreen.minX") &&
        settingsPanel.contains("sourceFrameOnScreen.maxY + SettingsShortcutPanelMetrics.verticalSourceGap") &&
        !settingsPanel.contains("sourceFrameOnScreen.minY - panelHeight") &&
        !settingsPanel.contains("sourceFrameOnScreen.maxX + SettingsShortcutPanelMetrics.sidebarTrailingInset") &&
        !settingsPanel.contains("x: sidebarMaxX"),
    "Settings shortcut panel should open as a small card above the Settings button instead of to the right of the sidebar."
)
require(
    !settingsShortcutSource.contains("StatusShortcutSummary"),
    "Shortcut menu should not add a Status summary; Status belongs in the Settings page."
)
require(
    config.contains("enum SettingsPageSection") &&
        config.contains("@Binding var selectedSection: SettingsPageSection") &&
        !config.contains("SettingsSectionSidebar") &&
        config.contains("case .profile") &&
        config.contains("case .status") &&
        config.contains("StatusTabView(viewModel: viewModel)") &&
        config.contains("case .budget") &&
        config.contains("case .models") &&
        config.contains("case .channels") &&
        config.contains("case .logs"),
    "ConfigTabView should keep account, system, configuration, models, channels, and logs Settings sections."
)
require(
    settingsShell.contains("struct SettingsShellView: View") &&
        settingsShell.contains("settings.shell.backToApp") &&
        settingsShell.contains("onBackToApp") &&
        settingsShell.contains("SettingsSectionSidebar") &&
        settingsShell.contains("settings.shell.searchPlaceholder") &&
        settingsShell.contains("ConfigTabView(") &&
        settingsShell.contains("selectedSection: $selectedSection"),
    "SettingsShellView should own the full Settings page chrome, search/sidebar navigation, and Back to app action."
)
require(
    dashboard.contains("@State private var presentationMode: DashboardPresentationMode = .app") &&
        dashboard.contains("private enum DashboardPresentationMode: Equatable, Hashable") &&
        dashboard.contains("private struct DashboardChromePolicy: Equatable") &&
        dashboard.contains("if presentationMode.isSettingsPresented") &&
        dashboard.contains("SettingsShellView(") &&
        dashboard.contains("onBackToApp: closeSettingsPage") &&
        dashboard.contains("private func openSettingsSection(_ section: SettingsPageSection)") &&
        dashboard.contains("presentationMode = .settings(section)") &&
        dashboard.contains("private func closeSettingsPage()") &&
        dashboard.contains("presentationMode = .app"),
    "Dashboard should only switch into the Settings page shell and return to the app, not own Settings navigation chrome."
)
require(
    !config.contains("case .skills") &&
        !config.contains("case .plugins") &&
        !config.contains("case .cron") &&
        !config.contains("SkillsTabView(viewModel: viewModel") &&
        !config.contains("PluginsTabView(") &&
        !config.contains("CronTabView(viewModel: viewModel"),
    "Settings should not duplicate main sidebar entries for Skills, Plugins, or Automation/Cron."
)
let officialProviderOffset = offset(of: "GetClawHubServiceSection(viewModel: viewModel)", in: providerSettingsContent)
let customProviderOffset = offset(of: "CustomProviderListSection(viewModel: viewModel)", in: providerSettingsContent)
require(
    officialProviderOffset < customProviderOffset,
    "Provider settings should keep the official GetClawHub service option before the custom provider list."
)
require(
    officialServiceSection.contains("Available Models") &&
        officialServiceSection.contains("officialAvailableModels") &&
        officialServiceSection.contains("membershipManager.filterAllowedGetClawHubModels(officialPresetModels)") &&
        officialServiceSection.contains("availableModelsView"),
    "Official GetClawHub provider settings should show the usable model list."
)
require(
    officialServiceSection.contains("@State private var areModelsExpanded = false") &&
        officialServiceSection.contains("officialModelSummary") &&
        officialServiceSection.contains("areModelsExpanded.toggle()") &&
        officialServiceSection.contains("if areModelsExpanded") &&
        officialServiceSection.contains(".frame(maxHeight: 260)"),
    "Official GetClawHub model list should be collapsed by default and expand into a height-limited list."
)

print("Settings shortcut menu verification passed")
