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

func exists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(_ source: String, from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start) else {
        fputs("FAIL: missing slice start: \(start)\n", stderr)
        exit(1)
    }
    let tail = source[startRange.lowerBound...]
    guard let endRange = tail.range(of: end) else {
        fputs("FAIL: missing slice end: \(end)\n", stderr)
        exit(1)
    }
    return String(tail[..<endRange.lowerBound])
}

func jsonObject(_ path: String) -> [String: String] {
    let data = Data(read(path).utf8)
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
        fputs("FAIL: invalid JSON string object in \(path)\n", stderr)
        exit(1)
    }
    return json
}

func placeholderSignature(_ value: String) -> [String] {
    let pattern = #"%(?:\d+\$)?(?:[-+#0 ]*)?(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|q|L|z|t|j)?[@diuoxXfFeEgGaAcCsSp%]"#
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return regex.matches(in: value, range: range).compactMap { match in
        guard let tokenRange = Range(match.range, in: value) else { return nil }
        let token = String(value[tokenRange])
        if token == "%%" {
            return nil
        }
        if token.contains(" ") {
            return nil
        }
        return token.replacingOccurrences(
            of: #"^%(\d+\$)"#,
            with: "%",
            options: .regularExpression
        )
    }
}

func isPluginCatalogFieldThatMustBeLocalized(_ key: String) -> Bool {
    guard key.hasPrefix("plugins.catalog.") else { return false }
    return key.hasSuffix(".description")
        || key.hasSuffix(".longDescription")
        || key.hasSuffix(".category")
        || key.range(of: #"\.capabilities\.\d+$"#, options: .regularExpression) != nil
}

func isSkillCatalogFieldThatMustBeLocalized(_ key: String) -> Bool {
    guard key.hasPrefix("skills.catalog.") else { return false }
    return key.hasSuffix(".description") || key.hasSuffix(".content")
}

func isAgentCatalogFieldThatMustBeLocalized(_ key: String) -> Bool {
    let uiPrefixes = ["agents.search.", "agents.empty.", "agents.detail.", "agents.action.", "agents.alert."]
    guard !uiPrefixes.contains(where: { key.hasPrefix($0) }) else { return false }
    return key.range(
        of: #"^agents\.[a-z0-9.]+\.(description|division|vibe|whenToUse|content)$"#,
        options: .regularExpression
    ) != nil
}

func isDynamicCatalogField(_ namespace: String, _ key: String) -> Bool {
    switch namespace {
    case "plugins":
        return key.hasPrefix("plugins.catalog.")
    case "skills":
        return key.hasPrefix("skills.catalog.")
    case "agents":
        let uiPrefixes = ["agents.search.", "agents.empty.", "agents.detail.", "agents.action.", "agents.alert."]
        guard !uiPrefixes.contains(where: { key.hasPrefix($0) }) else { return false }
        return key.range(
            of: #"^agents\.[a-z0-9.]+\.(name|division|description|vibe|specialty|whenToUse|content)$"#,
            options: .regularExpression
        ) != nil
    default:
        return false
    }
}

func isCatalogFieldThatMustBeLocalized(namespace: String, key: String) -> Bool {
    switch namespace {
    case "plugins":
        return isPluginCatalogFieldThatMustBeLocalized(key)
    case "skills":
        return isSkillCatalogFieldThatMustBeLocalized(key)
    case "agents":
        return isAgentCatalogFieldThatMustBeLocalized(key)
    default:
        return false
    }
}

func containsCJK(_ value: String) -> Bool {
    value.unicodeScalars.contains { scalar in
        (0x4E00...0x9FFF).contains(Int(scalar.value))
            || (0x3400...0x4DBF).contains(Int(scalar.value))
    }
}

func englishWordCount(_ value: String) -> Int {
    let pattern = #"[A-Za-z]{3,}"#
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return regex.numberOfMatches(in: value, range: range)
}

func englishTokens(_ value: String) -> Set<String> {
    let pattern = #"[A-Za-z][A-Za-z0-9.+-]{2,}"#
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    let ignored: Set<String> = [
        "ai",
        "api",
        "app",
        "apps",
        "ios",
        "macos",
        "mcp",
        "openclaw",
        "swiftui",
        "ui",
        "web"
    ]
    return Set(regex.matches(in: value, range: range).compactMap { match in
        guard let tokenRange = Range(match.range, in: value) else { return nil }
        let token = String(value[tokenRange]).lowercased()
        return ignored.contains(token) ? nil : token
    })
}

func hasHighEnglishSourceOverlap(localized: String, english: String) -> Bool {
    let source = englishTokens(english)
    guard source.count >= 3 else { return false }
    let localizedTokens = englishTokens(localized)
    guard !localizedTokens.isEmpty else { return false }
    let overlap = source.intersection(localizedTokens).count
    return Double(overlap) / Double(source.count) >= 0.6
}

func assertLocalizedPluginCatalogValue(
    language: String,
    namespace: String,
    key: String,
    localized: String,
    english: String,
    path: String
) {
    let trimmedLocalized = localized.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedEnglish = english.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedEnglish.isEmpty else { return }

    let preservedTechnicalTerms: Set<String> = ["MCP"]
    if preservedTechnicalTerms.contains(trimmedEnglish) {
        return
    }

    require(
        trimmedLocalized != trimmedEnglish,
        "\(path) keeps English \(namespace) catalog text for \(key)"
    )

    if language == "zh-Hans" || language == "zh-Hant" {
        require(
            containsCJK(trimmedLocalized),
            "\(path) should contain Chinese text for \(key)"
        )
        require(
            !hasHighEnglishSourceOverlap(localized: trimmedLocalized, english: trimmedEnglish),
            "\(path) looks like pseudo-localized \(namespace) text for \(key): \(trimmedLocalized)"
        )
    }
}

func supportedLanguageIDs(from source: String) -> [String] {
    let pattern = #"Language\(id:\s*\"([^\"]+)\""#
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(source.startIndex..<source.endIndex, in: source)
    return regex.matches(in: source, range: range).compactMap { match in
        guard let range = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[range])
    }
}

let languageManager = read("OpenClawInstaller/Services/LanguageManager.swift")
let languages = supportedLanguageIDs(from: languageManager).filter { $0 != "system" }
require(!languages.isEmpty, "LanguageManager should expose supported languages")

require(exists("OpenClawInstaller/Services/I18nService.swift"), "I18nService.swift should exist")
let service = read("OpenClawInstaller/Services/I18nService.swift")
for token in ["enum I18n", "func t(", "func markdown(", "localeCandidates", "LanguageManager.shared.currentLocale.identifier", "String(format:"] {
    require(service.contains(token), "I18nService should contain \(token)")
}

let namespaces = ["common", "settings", "agents", "skills", "plugins"]
var englishResources: [String: [String: String]] = [:]
for namespace in namespaces {
    let path = "OpenClawInstaller/Resources/I18n/en/\(namespace).json"
    require(exists(path), "missing English i18n resource: \(path)")
    englishResources[namespace] = jsonObject(path)
}

for language in languages {
    for namespace in namespaces {
        let path = "OpenClawInstaller/Resources/I18n/\(language)/\(namespace).json"
        require(exists(path), "missing i18n resource: \(path)")
        let json = jsonObject(path)
        require(!json.isEmpty, "i18n resource should not be empty: \(path)")

        let english = englishResources[namespace] ?? [:]
        let missing = Set(english.keys).subtracting(json.keys)
        let extra = Set(json.keys).subtracting(english.keys)
        require(missing.isEmpty, "\(path) is missing keys: \(missing.sorted().prefix(8).joined(separator: ", "))")
        require(extra.isEmpty, "\(path) has keys not present in English fallback: \(extra.sorted().prefix(8).joined(separator: ", "))")

        for key in english.keys {
            if !isDynamicCatalogField(namespace, key) {
                let basePlaceholders = placeholderSignature(english[key] ?? "")
                let localizedPlaceholders = placeholderSignature(json[key] ?? "")
                require(
                    basePlaceholders == localizedPlaceholders,
                    "\(path) placeholder mismatch for \(key): expected \(basePlaceholders), got \(localizedPlaceholders)"
                )
            }

            if language != "en", isCatalogFieldThatMustBeLocalized(namespace: namespace, key: key) {
                assertLocalizedPluginCatalogValue(
                    language: language,
                    namespace: namespace,
                    key: key,
                    localized: json[key] ?? "",
                    english: english[key] ?? "",
                    path: path
                )
            }
        }
    }
}

let pbx = read("OpenClawInstaller.xcodeproj/project.pbxproj")
require(pbx.contains("I18nService.swift in Sources"), "Xcode project should compile I18nService.swift")
require(pbx.contains("I18n in Resources"), "Xcode project should bundle I18n resources")

let marketplace = read("OpenClawInstaller/Models/MarketplaceAgent.swift")
require(marketplace.contains("I18n.agentDisplay"), "MarketplaceAgent should localize display through unified I18n")
require(!marketplace.contains("marketplace_agents.i18n"), "MarketplaceAgent should not load the old marketplace_agents.i18n overlay directly")

let skillsView = read("OpenClawInstaller/Views/Dashboard/Skills/SkillsTabView.swift")
for token in ["@EnvironmentObject private var languageManager: LanguageManager", "I18n.skillDisplay", "I18n.t(\"skills.", "localizedSearchFields"] {
    require(skillsView.contains(token), "SkillsTabView should contain \(token)")
}
for forbidden in ["Text(\"Skills\")", "UnifiedSearchField(placeholder: \"Search skills\"", "Text(\"Install Skill\")", "Text(\"Description\")"] {
    require(!skillsView.contains(forbidden), "SkillsTabView still has hardcoded UI text: \(forbidden)")
}
let catalogSkillRow = slice(skillsView, from: "private struct CatalogSkillListRow: View", to: "private struct InstalledSkillListRow: View")
let installedSkillRow = slice(skillsView, from: "private struct InstalledSkillListRow: View", to: "private struct InstalledStatusMark: View")
require(catalogSkillRow.contains("let display = I18n.skillDisplay(for: item)"), "CatalogSkillListRow should resolve localized skill display once")
require(installedSkillRow.contains("let display = catalogItem.map { I18n.skillDisplay(for: $0) }"), "InstalledSkillListRow should resolve localized catalog display when available")
for forbidden in ["Text(item.displayName)", "Text(item.description)", "Text(catalogItem?.displayName ?? skill.name)", "Text(catalogItem?.description.nilIfBlank ?? skill.description.nilIfBlank ?? I18n.t(\"skills.fallback.installedSkill\"))"] {
    require(!(catalogSkillRow + installedSkillRow).contains(forbidden), "SkillsTabView catalog rows should use I18n.skillDisplay instead of raw catalog text: \(forbidden)")
}

let pluginsView = read("OpenClawInstaller/Views/Dashboard/Plugins/PluginsTabView.swift")
for token in ["@EnvironmentObject private var languageManager: LanguageManager", "I18n.pluginDisplay", "I18n.t(\"plugins.", "localizedSearchFields"] {
    require(pluginsView.contains(token), "PluginsTabView should contain \(token)")
}
for forbidden in ["Text(\"Plugins\")", "UnifiedSearchField(placeholder: \"Search plugins\"", "Text(\"Description\")", ".alert(\"Uninstall Plugin\""] {
    require(!pluginsView.contains(forbidden), "PluginsTabView still has hardcoded UI text: \(forbidden)")
}

let marketplaceOverview = read("OpenClawInstaller/Views/Dashboard/MarketplaceOverviewView.swift")
let marketplaceDetail = read("OpenClawInstaller/Views/Dashboard/MarketplaceDetailView.swift")
for token in ["I18n.t(\"agents.search.placeholder\")", "I18n.t(\"agents.empty.noMatching\")", "I18n.t(\"agents.action.recruit\")"] {
    require((marketplaceOverview + marketplaceDetail).contains(token), "AgentsMarket views should contain \(token)")
}
for forbidden in ["String(localized: \"Search agents", "String(localized: \"No matching agents", "String(localized: \"Recruit\"", "String(localized: \"Persona Content\""] {
    require(!(marketplaceOverview + marketplaceDetail).contains(forbidden), "AgentsMarket still has hardcoded localized UI through old entry: \(forbidden)")
}

let settingsShortcutPanel = read("OpenClawInstaller/Views/Dashboard/SettingsShortcutPanel.swift")
for forbidden in ["Text(\"Settings\")", "Text(\"Local user\")", "Label(\"Model\"", "Button(\"Configure\")", "Text(\"No models loaded\")", "Text(\"No billing data yet\")", "Text(\"No local budget rule\")", "Button(\"Edit budget rules\")"] {
    require(!settingsShortcutPanel.contains(forbidden), "SettingsShortcutPanel still has hardcoded UI text: \(forbidden)")
}

let dashboardView = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
for token in [
    "I18n.skillDisplay",
    "localizedSkillDescription",
    "localizedSkillHelp",
    "loadSkillMarket()",
    "I18n.t(\"dashboard.alert.error\")",
    "I18n.t(\"dashboard.agent.remove.title\")",
    "I18n.t(\"dashboard.session.action.rename\")",
    "I18n.t(\"dashboard.sidebar.pinned\")",
    "I18n.t(\"dashboard.skills.title\")",
    "I18n.t(\"dashboard.composer.mode.label\")"
] {
    require(dashboardView.contains(token), "DashboardView skill surfaces should contain \(token)")
}
require(dashboardView.split(separator: "\n").filter { $0.contains("Task { await viewModel.loadSkills() }") || $0.contains("await viewModel.loadSkills()") }.isEmpty, "DashboardView skill display surfaces should load the catalog through loadSkillMarket() before rendering localized skill descriptions")
for forbidden in ["Text(skill.description)", ".help(skill.description.isEmpty ? skill.name : skill.description)"] {
    require(!dashboardView.contains(forbidden), "DashboardView skill surfaces should not show raw skill descriptions when a catalog localization exists: \(forbidden)")
}
for forbidden in [
    ".alert(\"Error\"",
    ".alert(\"Remove Agent\"",
    "Button(\"OK\"",
    "Label(\"Rename\"",
    "Label(\"Export…\"",
    "Label(\"Archive\"",
    "Label(\"Delete\"",
    "title: \"Pinned\"",
    ".help(\"Add Work Folder...\"",
    "Label(\"Add Work Folder...\"",
    "Text(\"Skills\")",
    "Text(\"Loading…\")",
    "Text(\"No skills detected\")",
    "Text(\"Mode:\")",
    "return \"Run Task\"",
    "return \"Code Mode\""
] {
    require(!dashboardView.contains(forbidden), "DashboardView still has hardcoded dashboard UI text: \(forbidden)")
}

let dashboardI18nTargets: [(String, [String], [String])] = [
    (
        "OpenClawInstaller/Views/Dashboard/CronTabView.swift",
        ["I18n.t(\"dashboard.cron.", "I18n.format(\"dashboard.cron.", "I18n.t(\"catalog.action."],
        ["Text(\"Cron Jobs\")", "Text(\"Add Job\")", "Text(\"Refreshing...\")", "Button(\"Retry\"", ".alert(\"Remove Cron Job\"", "Text(\"Add Cron Job\")", "Text(\"Name\")", "Text(\"Cron Expression\")", "Text(\"Session Target\")", "Text(\"Message\")", "Button(\"Add\")"]
    ),
    (
        "OpenClawInstaller/Views/Dashboard/ChannelsTabView.swift",
        ["I18n.t(\"dashboard.channels.", "I18n.format(\"dashboard.channels.", "I18n.t(\"catalog.action."],
        ["Text(\"Channels\")", "Text(\"Add Channel\")", "Text(\"Loading channels...\")", "Text(\"No channels configured\")", "Text(\"Add a channel to get started\")", ".alert(\"Remove Channel\"", "\"Configured\"", "\"Not Configured\"", "\"Linked\"", "\"Not Linked\""]
    ),
    (
        "OpenClawInstaller/Views/Dashboard/ModelsTabView.swift",
        ["I18n.t(\"dashboard.models.", "I18n.t(\"catalog.action."],
        ["Text(\"Models\")", "Text(\"Loading models...\")", "Text(\"No models configured\")", "Text(\"For aliases and auth configuration, use:\")", "label: \"Default\"", "label: \"Image Model\"", "label: \"Fallbacks\"", "Text(\"Fallback Models\")", "Button(\"Set Default\")"]
    ),
    (
        "OpenClawInstaller/Views/Dashboard/StatusTabView.swift",
        ["I18n.t(\"dashboard.status.", "I18n.format(\"dashboard.status."],
        ["Text(\"Port\")", "Text(\"Uptime\")", "Text(\"Version\")", "Text(\"Start\")", "Text(\"Stop\")", "Text(\"Restart\")", "Label(\"Agent Sessions\"", "Label(\"Cron Health\"", "Label(\"Token Usage\"", "Text(\"No token data\")", "Text(\"System Information\")"]
    ),
    (
        "OpenClawInstaller/Views/Dashboard/LogsTabView.swift",
        ["I18n.t(\"dashboard.logs."],
        ["TextField(\"Search logs...\"", "Label(\"Auto\"", "Label(\"Refresh\"", "Label(\"Export\"", "Label(\"Open File\"", "Text(\"No Logs Available\")", "Text(\"Logs will appear here when the gateway service is running\")", "Logs exported successfully"]
    ),
    (
        "OpenClawInstaller/Views/Dashboard/Inspector/WorkspaceInspectorPane.swift",
        ["I18n.t(\"workspace.", "I18n.format(\"workspace.", "I18n.t(\"common.action."],
        ["Text(\"Outputs\")", ".alert(\"Delete\"", "Text(\"No outputs yet\")", "Label(\"New File\"", "Label(\"New Folder\"", "Label(\"Rename\"", "Label(\"Cut\"", "Label(\"Copy\"", "Label(\"Paste\"", "TextField(\"Filter files...\"", "Text(\"No files\")", "Text(\"No matching files\")", ".help(\"Double-click to copy path\")"]
    ),
    (
        "OpenClawInstaller/Views/Dashboard/ProjectWorkspace/AgentProjectFolderRow.swift",
        ["I18n.t(\"workspace."],
        [".help(\"New chat in project\")", "Label(\"New chat in project\"", "Label(\"Reveal in Finder\"", "Label(\"Remove from Agent\""]
    ),
    (
        "OpenClawInstaller/Views/Shared/ErrorView.swift",
        ["I18n.t(\"common.action.", "I18n.t(\"error."],
        ["Text(\"Retry\")", "Text(\"Cancel\")", "Text(\"OK\")", "Text(\"Report Issue\")", "Error Report Copied", "Error details have been copied to your clipboard"]
    )
]

for (path, requiredTokens, forbiddenTokens) in dashboardI18nTargets {
    let source = read(path)
    for token in requiredTokens {
        require(source.contains(token), "\(path) should use unified i18n token \(token)")
    }
    for token in forbiddenTokens {
        require(!source.contains(token), "\(path) still has hardcoded user-visible text: \(token)")
    }
}

print("Unified i18n resources verification passed")
