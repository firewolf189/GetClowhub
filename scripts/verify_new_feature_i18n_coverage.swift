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
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func json(_ path: String) -> [String: String] {
    let data = Data(read(path).utf8)
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
        fputs("FAIL: could not parse \(path)\n", stderr)
        exit(1)
    }
    return object
}

let dashboard = read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let settingsShell = read("OpenClawInstaller/Features/Settings/Views/SettingsShellView.swift")
let config = read("OpenClawInstaller/Features/Settings/Views/ConfigTabView.swift")
let budget = read("OpenClawInstaller/Features/Budget/Views/BudgetTabView.swift")
let environmentCheck = read("OpenClawInstaller/Features/Installation/Views/EnvironmentCheckView.swift")
let legacyInstaller = read("OpenClawInstaller/Features/Dashboard/Legacy/ContentView.swift")
let installationViewModel = read("OpenClawInstaller/Features/Installation/InstallationViewModel.swift")
let nodeInstaller = read("OpenClawInstaller/Core/Install/NodeInstaller.swift")
let openClawInstaller = read("OpenClawInstaller/Core/Install/OpenClawInstaller.swift")
let appDelegate = read("OpenClawInstaller/App/AppDelegate.swift")
let billing = read("OpenClawInstaller/Features/Settings/Account/BillingTabView.swift")
let generator = read("scripts/generate_unified_i18n_resources.py")

func swiftUsesI18nKey(_ source: String, _ key: String) -> Bool {
    source.contains(#"I18n.t("\#(key)""#)
        || source.contains(#"I18n.format("\#(key)""#)
        || source.contains(#""\#(key)""#)
}

let requiredDashboardKeys = [
    "app.update.currentVersion",
    "app.update.toVersion",
    "app.update.installLatest",
    "app.update.upToDate",
    "app.update.check",
    "app.update.lookForLatest",
    "billing.loginRequired",
    "billing.unavailable",
    "dashboard.model.label",
    "dashboard.model.defaultInherit",
    "dashboard.chat.viewResult",
    "dashboard.chat.moveToBackground",
    "dashboard.diagnostics.title",
    "dashboard.outputs.title",
    "dashboard.outputs.empty",
    "dashboard.terminal.title",
    "dashboard.chat.clearConversation",
    "dashboard.activity.empty",
    "dashboard.agent.fallbackDescription"
]

for key in requiredDashboardKeys {
    require(dashboard.contains(#"I18n.t("\#(key)""#) || dashboard.contains(#"I18n.format("\#(key)""#), "Dashboard should use i18n key \(key)")
    require(generator.contains(#""\#(key)":"#), "generator should define \(key)")
}

let forbiddenDashboardSnippets = [
    #"I18n.t("Up to date")"#,
    #"I18n.t("Check for Updates")"#,
    #"I18n.t("Look for the latest GetClawHub version")"#,
    #"title: "Update to v"#,
    #"detail: "Install the latest app update""#,
    #"Text("Please log in to view billing.")"#,
    #"Text("Billing is not available in this build.")"#,
    #"Text("Model")"#,
    #"Text("View result ↑")"#,
    #"Text("Move to Background")"#,
    #"Text("Default (inherit)")"#,
    #"Label("Copy""#,
    #"Text("Diagnostics Report")"#,
    #"Button("Close")"#,
    #"Text("Model:")"#,
    #"Text("Outputs")"#,
    #"Text("No outputs yet")"#,
    #"Text("Terminal")"#,
    #"Text("Clear Conversation")"#,
    #"Text("No activity yet")"#,
    #"Text("General-purpose assistant")"#
]

for snippet in forbiddenDashboardSnippets {
    require(!dashboard.contains(snippet), "Dashboard still has hardcoded new-feature UI text: \(snippet)")
}

let requiredSettingsShellKeys = [
    "settings.shell.backToApp",
    "settings.shell.searchPlaceholder",
    "settings.group.account",
    "settings.group.system",
    "settings.group.configuration",
    "settings.group.advanced"
]

for key in requiredSettingsShellKeys {
    require(settingsShell.contains(#""\#(key)""#), "Settings shell should use stable i18n key \(key)")
    require(generator.contains(#""\#(key)":"#), "generator should define \(key)")
}

let forbiddenSettingsShellSnippets = [
    #"I18n.t("Back to app""#,
    #"I18n.t("Search settings""#,
    #"Text(I18n.t(group.0"#
]

for snippet in forbiddenSettingsShellSnippets {
    require(!settingsShell.contains(snippet), "Settings shell should not use display text as i18n key: \(snippet)")
}

let requiredProviderKeys = [
    "settings.provider.custom.addTitle",
    "settings.provider.custom.addSubtitle",
    "settings.provider.custom.apiKeyOptional",
    "settings.provider.custom.confirmDelete",
    "settings.provider.custom.needsSetup",
    "settings.provider.custom.emptyTitle",
    "settings.provider.custom.emptyDetail",
    "settings.provider.custom.showModelList",
    "settings.provider.custom.hideModelList",
    "settings.provider.custom.removeModel",
    "settings.provider.custom.addModelSubtitle",
    "settings.provider.custom.supportsImageInput",
    "settings.provider.custom.supportsReasoning"
]

for key in requiredProviderKeys {
    require(config.contains(#"localizedString("\#(key)")"#), "ConfigTabView should use stable provider i18n key \(key)")
    require(generator.contains(#""\#(key)":"#), "generator should define \(key)")
}

let forbiddenProviderRawKeys = [
    "Add Custom Provider",
    "Enter a base URL directly. API key is optional for local providers.",
    "API Key Optional",
    "Needs setup",
    "Add a provider above with its base URL and API key.",
    "Show model list",
    "Hide model list",
    "Remove Model",
    "Register a model ID exposed by this provider.",
    "Supports image input",
    "Supports reasoning"
]

for rawKey in forbiddenProviderRawKeys {
    require(!config.contains(#"localizedString("\#(rawKey)")"#), "ConfigTabView should not use raw display text as provider i18n key: \(rawKey)")
}

let requiredInstallerCommonKeys = [
    "installer.environment.title",
    "installer.environment.checking",
    "installer.environment.operatingSystem",
    "installer.environment.architecture",
    "installer.environment.diskSpace",
    "installer.environment.nodeWillUseBundled",
    "installer.environment.nodeWillInstallBundled",
    "installer.environment.nodeBundledNote",
    "installer.environment.openClawNotInstalled",
    "installer.environment.issuesFound",
    "legacy.installer.title",
    "legacy.installer.subtitleMacOS",
    "legacy.installer.checkingEnvironment",
    "legacy.installer.systemInformation",
    "legacy.installer.checkEnvironment",
    "legacy.installer.startInstallation",
    "legacy.installer.adminPrivileges",
    "legacy.installer.granted",
    "legacy.installer.notGranted",
    "legacy.installer.notDetected",
    "install.progress.checkingEnvironment",
    "install.progress.analyzingRequirements",
    "install.progress.systemRequirementsNotMet",
    "install.progress.nodeRequired",
    "install.progress.nodeUpgradeRequired",
    "install.progress.nodeAlreadyInstalled",
    "install.progress.openClawAlreadyInstalled",
    "install.progress.openClawRequired",
    "install.progress.startingNode",
    "install.progress.nodeSuccess",
    "install.progress.nodeFailed",
    "install.progress.startingOpenClaw",
    "install.progress.openClawSuccess",
    "install.progress.openClawFailed",
    "install.progress.savingConfig",
    "install.progress.configSaved",
    "install.progress.configSaveFailed",
    "install.node.status.detectingRegion",
    "install.node.region.china",
    "install.node.region.international",
    "install.node.mirror.china",
    "install.node.mirror.official",
    "install.node.status.regionDetected",
    "install.node.status.latestLTS",
    "install.node.status.downloadingFrom",
    "install.node.status.downloadComplete",
    "install.node.status.downloadingPercent",
    "install.node.status.verifyingDownload",
    "install.node.status.preparingExtract",
    "install.node.status.extracting",
    "install.node.status.extractingPercent",
    "install.node.status.verifyingBinaries",
    "install.node.status.complete",
    "install.node.status.installing",
    "install.node.status.verifyingInstallation",
    "install.node.status.installedAt",
    "install.node.status.usingBundled",
    "install.node.status.bundledMissing",
    "install.node.status.success",
    "install.node.status.cancelled",
    "install.openclaw.status.installingBundled",
    "install.openclaw.status.extracting",
    "install.openclaw.status.extractingPercent",
    "install.openclaw.status.removingQuarantine",
    "install.openclaw.status.settingUpBinary",
    "install.openclaw.status.complete",
    "install.openclaw.status.configuring",
    "install.openclaw.status.configured",
    "install.openclaw.status.verifying",
    "install.openclaw.status.verifiedAt",
    "install.openclaw.status.installedAt",
    "menu.status.uptime",
    "menu.status.openDashboard",
    "menu.status.startService",
    "menu.status.stopService",
    "menu.status.statusLine",
    "menu.status.restartService",
    "menu.status.checkUpdates",
    "menu.status.showMainWindow",
    "menu.status.quitInstaller",
    "menu.status.helperVersion",
    "menu.status.serviceVersion"
]

for key in requiredInstallerCommonKeys {
    require(generator.contains(#""\#(key)":"#), "generator should define \(key)")
}

let requiredExistingInstallViewKeys = [
    "install.status.uninstalling",
    "install.status.uninstallComplete",
    "install.status.dataPreserved",
    "install.status.openclawInstalled",
    "install.status.readyToInstall",
    "install.action.start",
    "install.action.openDashboard",
    "install.action.uninstall",
    "install.alert.uninstallTitle",
    "install.alert.uninstallMessage",
    "install.welcome.title",
    "install.welcome.subtitle",
    "install.welcome.feature.automated.title",
    "install.welcome.feature.automated.description",
    "install.welcome.feature.configuration.title",
    "install.welcome.feature.configuration.description",
    "install.welcome.feature.secure.title",
    "install.welcome.feature.secure.description",
    "install.welcome.feature.quick.title",
    "install.welcome.feature.quick.description",
    "install.action.quit",
    "install.action.getStarted",
    "install.node.title",
    "install.node.installingNode",
    "install.shared.log",
    "install.shared.progress",
    "install.shared.failed",
    "install.shared.errorDetails",
    "install.shared.possibleSolutions",
    "install.shared.solution.retry",
    "install.shared.version",
    "install.shared.location",
    "install.shared.status",
    "install.node.solution.internet",
    "install.node.solution.disk",
    "install.node.solution.vpn",
    "install.node.success",
    "install.node.ready",
    "install.openclaw.title",
    "install.openclaw.installing",
    "install.openclaw.solution.node",
    "install.openclaw.solution.npm",
    "install.openclaw.solution.network",
    "install.openclaw.solution.log",
    "install.openclaw.success",
    "install.openclaw.readyForConfig",
    "install.openclaw.configHelp",
    "install.config.title",
    "install.config.subtitle",
    "install.config.authToken",
    "install.config.tokenPlaceholder",
    "install.config.tokenHelp",
    "install.config.whyToken",
    "install.config.whyTokenDetail",
    "install.action.generate",
    "install.action.continue",
    "install.complete.title",
    "install.complete.subtitle",
    "install.complete.configuration",
    "install.status.installed",
    "install.status.completed",
    "install.status.starting",
    "install.complete.gatewayStarting",
    "install.complete.gatewayStarted",
    "install.complete.gatewayFailed",
    "install.action.retryStart",
    "install.action.goToManagement"
]

for key in requiredExistingInstallViewKeys {
    require(generator.contains(#""\#(key)":"#), "generator should define existing install view key \(key)")
}

let requiredBillingSettingsKeys = [
    "billing.expires"
]

for key in requiredBillingSettingsKeys {
    require(billing.contains(#"I18n.format("\#(key)""#), "Billing view should use i18n key \(key)")
    require(generator.contains(#""\#(key)":"#), "generator should define \(key)")
}

require(budget.contains(#"Button(I18n.t("common.action.cancel"), role: .cancel)"#), "Budget delete alert cancel button should use common.action.cancel")
require(budget.contains(#"Button(I18n.t("common.action.delete"), role: .destructive)"#), "Budget delete alert delete button should use common.action.delete")
require(!budget.contains(#"Button("Cancel", role: .cancel)"#), "Budget delete alert still hardcodes Cancel")
require(!budget.contains(#"Button("Delete", role: .destructive)"#), "Budget delete alert still hardcodes Delete")

let environmentRequiredUsages = [
    "installer.environment.title",
    "installer.environment.checking",
    "installer.environment.operatingSystem",
    "installer.environment.architecture",
    "installer.environment.diskSpace",
    "installer.environment.nodeWillUseBundled",
    "installer.environment.nodeWillInstallBundled",
    "installer.environment.nodeBundledNote",
    "installer.environment.openClawNotInstalled",
    "installer.environment.issuesFound"
]

for key in environmentRequiredUsages {
    require(swiftUsesI18nKey(environmentCheck, key), "EnvironmentCheckView should use \(key)")
}

let forbiddenEnvironmentSnippets = [
    #"Text("Environment Check")"#,
    #"Checking your system environment..."#,
    #"title: "Operating System""#,
    #"title: "Architecture""#,
    #"title: "Available Disk Space""#,
    #"将使用内置 v24.14.0"#,
    #"未安装 (将自动安装内置 v24.14.0)"#,
    #"OpenClaw 自带独立的 Node.js"#,
    #"value: viewModel.systemEnvironment.openclawInfo?.version ?? "Not Installed""#,
    #"Text("Issues Found:")"#,
    #"Text("Retry")"#
]

for snippet in forbiddenEnvironmentSnippets {
    require(!environmentCheck.contains(snippet), "EnvironmentCheckView still has hardcoded UI text: \(snippet)")
}

let legacyRequiredUsages = [
    "legacy.installer.title",
    "legacy.installer.subtitleMacOS",
    "legacy.installer.checkingEnvironment",
    "legacy.installer.systemInformation",
    "legacy.installer.checkEnvironment",
    "legacy.installer.startInstallation",
    "legacy.installer.adminPrivileges",
    "legacy.installer.granted",
    "legacy.installer.notGranted",
    "legacy.installer.notDetected"
]

for key in legacyRequiredUsages {
    require(legacyInstaller.contains(#"I18n.t("\#(key)""#), "Legacy installer should use \(key)")
}

let forbiddenLegacySnippets = [
    #"Text("OpenClaw Installer")"#,
    #"Text("for macOS")"#,
    #"Text("Checking environment...")"#,
    #"Text("System Information")"#,
    #"Text("Check Environment")"#,
    #"Text("Start Installation")"#,
    #"title: "Administrator Privileges""#,
    #" ? "Granted" : "Not Granted""#,
    #"?? "Not Detected""#
]

for snippet in forbiddenLegacySnippets {
    require(!legacyInstaller.contains(snippet), "Legacy installer still has hardcoded UI text: \(snippet)")
}

let installationViewModelKeys = [
    "install.progress.checkingEnvironment",
    "install.progress.analyzingRequirements",
    "install.progress.systemRequirementsNotMet",
    "install.progress.nodeRequired",
    "install.progress.nodeUpgradeRequired",
    "install.progress.nodeAlreadyInstalled",
    "install.progress.openClawAlreadyInstalled",
    "install.progress.openClawRequired",
    "install.progress.startingNode",
    "install.progress.nodeSuccess",
    "install.progress.nodeFailed",
    "install.progress.startingOpenClaw",
    "install.progress.openClawSuccess",
    "install.progress.openClawFailed",
    "install.progress.savingConfig",
    "install.progress.configSaved",
    "install.progress.configSaveFailed"
]

for key in installationViewModelKeys {
    require(swiftUsesI18nKey(installationViewModel, key), "InstallationViewModel should use \(key)")
}

let forbiddenInstallationViewModelSnippets = [
    #"message: "Checking system environment...""#,
    #"message: "Analyzing requirements...""#,
    #"System requirements not met:\n"#,
    #"message: "Node.js installation required""#,
    #"message: "OpenClaw installation required""#,
    #"Node.js installation failed:"#,
    #"OpenClaw installation failed:"#,
    #"Saving gateway configuration..."#,
    #"Configuration saved"#,
    #"Failed to save configuration:"#
]

for snippet in forbiddenInstallationViewModelSnippets {
    require(!installationViewModel.contains(snippet), "InstallationViewModel still has hardcoded user-facing status: \(snippet)")
}

for key in [
    "install.node.status.detectingRegion",
    "install.node.status.regionDetected",
    "install.node.status.latestLTS",
    "install.node.status.downloadingFrom",
    "install.node.status.downloadComplete",
    "install.node.status.downloadingPercent",
    "install.node.status.verifyingDownload",
    "install.node.status.preparingExtract",
    "install.node.status.extracting",
    "install.node.status.extractingPercent",
    "install.node.status.verifyingBinaries",
    "install.node.status.complete",
    "install.node.status.installing",
    "install.node.status.verifyingInstallation",
    "install.node.status.installedAt",
    "install.node.status.usingBundled",
    "install.node.status.bundledMissing",
    "install.node.status.success",
    "install.node.status.cancelled"
] {
    require(swiftUsesI18nKey(nodeInstaller, key), "NodeInstaller should use \(key)")
}

for key in [
    "install.openclaw.status.installingBundled",
    "install.openclaw.status.extracting",
    "install.openclaw.status.extractingPercent",
    "install.openclaw.status.removingQuarantine",
    "install.openclaw.status.settingUpBinary",
    "install.openclaw.status.complete",
    "install.openclaw.status.configuring",
    "install.openclaw.status.configured",
    "install.openclaw.status.verifying",
    "install.openclaw.status.verifiedAt",
    "install.openclaw.status.installedAt"
] {
    require(swiftUsesI18nKey(openClawInstaller, key), "OpenClawInstaller should use \(key)")
}

for key in [
    "menu.status.uptime",
    "menu.status.openDashboard",
    "menu.status.startService",
    "menu.status.stopService",
    "menu.status.statusLine",
    "menu.status.restartService",
    "menu.status.checkUpdates",
    "menu.status.showMainWindow",
    "menu.status.quitInstaller",
    "menu.status.helperVersion",
    "menu.status.serviceVersion"
] {
    require(swiftUsesI18nKey(appDelegate, key), "AppDelegate menu bar UI should use \(key)")
}

for snippet in [
    #"Text("Uptime:")"#,
    "Text(\"OpenClaw Helper v",
    "Text(\"OpenClaw Service ",
    #"String(localized: "Open Dashboard")"#,
    #"String(localized: "Stop Service")"#,
    #"String(localized: "Start Service")"#,
    #"String(localized: "Show Main Window")"#
] {
    require(!appDelegate.contains(snippet), "AppDelegate menu bar UI still has hardcoded/default-bundle text: \(snippet)")
}

for language in ["en", "zh-Hans", "zh-Hant"] {
    let common = json("OpenClawInstaller/Resources/I18n/\(language)/common.json")
    let settings = json("OpenClawInstaller/Resources/I18n/\(language)/settings.json")
    for key in requiredDashboardKeys {
        require(common[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, "\(language) common.json missing \(key)")
    }
    for key in requiredInstallerCommonKeys + requiredExistingInstallViewKeys {
        require(common[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, "\(language) common.json missing \(key)")
    }
    for key in requiredSettingsShellKeys + requiredProviderKeys {
        require(settings[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, "\(language) settings.json missing \(key)")
    }
    for key in requiredBillingSettingsKeys {
        require(settings[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, "\(language) settings.json missing \(key)")
    }
}

let zhHansCommon = json("OpenClawInstaller/Resources/I18n/zh-Hans/common.json")
let zhHansSettings = json("OpenClawInstaller/Resources/I18n/zh-Hans/settings.json")
require(zhHansCommon["billing.loginRequired"] != "Please log in to view billing.", "zh-Hans billing.loginRequired should not fallback to English")
require(zhHansCommon["dashboard.outputs.empty"] != "No outputs yet", "zh-Hans outputs empty text should not fallback to English")
require(zhHansSettings["settings.provider.custom.addTitle"] != "Add Custom Provider", "zh-Hans custom provider title should not fallback to English")
require(zhHansCommon["installer.environment.nodeBundledNote"] != "OpenClaw includes an independent Node.js v24.14.0 runtime and can run without a system Node installation.", "zh-Hans installer environment note should not fallback to English")
require(zhHansCommon["install.node.status.detectingRegion"] != "Detecting region...", "zh-Hans Node installer status should not fallback to English")
require(zhHansCommon["menu.status.uptime"] != "Uptime:", "zh-Hans menu status label should not fallback to English")
require(zhHansSettings["billing.expires"] != "Expires %@", "zh-Hans billing.expires should not fallback to English")

print("New feature i18n coverage verified")
