import Foundation

struct I18nAgentDisplay: Hashable {
    let name: String
    let division: String
    let description: String
    let vibe: String
    let specialty: String?
    let whenToUse: String?
    let content: String
}

struct I18nSkillDisplay: Hashable {
    let displayName: String
    let description: String
    let content: String
}

struct I18nPluginDisplay: Hashable {
    let displayName: String
    let description: String
    let longDescription: String
    let category: String
    let capabilities: [String]
}

enum I18n {
    private static let namespaces = ["common", "settings", "agents", "skills", "plugins"]
    private static let resourceCache = I18nResourceCache()

    @MainActor
    static func t(_ key: String, fallback: String? = nil) -> String {
        localizedString(key, localeID: LanguageManager.shared.currentLocale.identifier, fallback: fallback, arguments: [])
    }

    @MainActor
    static func format(_ key: String, fallback: String? = nil, _ arguments: CVarArg...) -> String {
        localizedString(key, localeID: LanguageManager.shared.currentLocale.identifier, fallback: fallback, arguments: arguments)
    }

    @MainActor
    static func markdown(_ key: String, fallback: String) -> String {
        localizedString(key, localeID: LanguageManager.shared.currentLocale.identifier, fallback: fallback, arguments: [])
    }

    static func string(_ key: String, localeID: String, fallback: String? = nil, _ arguments: CVarArg...) -> String {
        localizedString(key, localeID: localeID, fallback: fallback, arguments: arguments)
    }

    static func markdown(_ key: String, localeID: String, fallback: String) -> String {
        localizedString(key, localeID: localeID, fallback: fallback, arguments: [])
    }

    static func agentDisplay(for agent: MarketplaceAgent, localeID: String) -> I18nAgentDisplay {
        let prefix = "agents.\(slug(agent.id))"
        return I18nAgentDisplay(
            name: string("\(prefix).name", localeID: localeID, fallback: agent.name),
            division: string("\(prefix).division", localeID: localeID, fallback: agent.division),
            description: string("\(prefix).description", localeID: localeID, fallback: agent.description),
            vibe: string("\(prefix).vibe", localeID: localeID, fallback: agent.vibe),
            specialty: optionalString("\(prefix).specialty", localeID: localeID, fallback: agent.specialty),
            whenToUse: optionalString("\(prefix).whenToUse", localeID: localeID, fallback: agent.whenToUse),
            content: markdown("\(prefix).content", localeID: localeID, fallback: agent.content)
        )
    }

    @MainActor
    static func skillDisplay(for item: SkillCatalogItem) -> I18nSkillDisplay {
        skillDisplay(for: item, localeID: LanguageManager.shared.currentLocale.identifier)
    }

    static func skillDisplay(for item: SkillCatalogItem, localeID: String) -> I18nSkillDisplay {
        let prefix = "skills.catalog.\(slug(item.name))"
        return I18nSkillDisplay(
            displayName: string("\(prefix).displayName", localeID: localeID, fallback: item.displayName),
            description: string("\(prefix).description", localeID: localeID, fallback: item.description),
            content: markdown("\(prefix).content", localeID: localeID, fallback: item.documentationMarkdown)
        )
    }

    @MainActor
    static func installedSkillDisplay(for skill: SkillInfo, catalogItem: SkillCatalogItem?) -> I18nSkillDisplay {
        installedSkillDisplay(
            for: skill,
            catalogItem: catalogItem,
            localeID: LanguageManager.shared.currentLocale.identifier
        )
    }

    static func installedSkillDisplay(
        for skill: SkillInfo,
        catalogItem: SkillCatalogItem?,
        localeID: String
    ) -> I18nSkillDisplay {
        if let catalogItem {
            return skillDisplay(for: catalogItem, localeID: localeID)
        }

        let prefix = "skills.installed.\(slug(skill.name))"
        let displayName = optionalLocalizedString("\(prefix).displayName", localeID: localeID)
            ?? skill.name
        let description = optionalLocalizedString("\(prefix).description", localeID: localeID)
            ?? string(
                "skills.installed.fallback.description",
                localeID: localeID,
                fallback: skill.description.nilIfBlank ?? "Installed skill",
                displayName
            )
        let content = optionalLocalizedString("\(prefix).content", localeID: localeID)
            ?? string(
                "skills.installed.fallback.content",
                localeID: localeID,
                fallback: description,
                displayName,
                description
            )

        return I18nSkillDisplay(
            displayName: displayName,
            description: description,
            content: content
        )
    }

    @MainActor
    static func pluginDisplay(for item: PluginCatalogItem) -> I18nPluginDisplay {
        pluginDisplay(for: item, localeID: LanguageManager.shared.currentLocale.identifier)
    }

    static func pluginDisplay(for item: PluginCatalogItem, localeID: String) -> I18nPluginDisplay {
        let prefix = "plugins.catalog.\(slug(item.name))"
        let capabilities = item.capabilities.enumerated().map { index, capability in
            string("\(prefix).capabilities.\(index)", localeID: localeID, fallback: capability)
        }
        return I18nPluginDisplay(
            displayName: string("\(prefix).displayName", localeID: localeID, fallback: item.displayName),
            description: string("\(prefix).description", localeID: localeID, fallback: item.description),
            longDescription: markdown("\(prefix).longDescription", localeID: localeID, fallback: item.longDescription),
            category: string("\(prefix).category", localeID: localeID, fallback: item.category),
            capabilities: capabilities
        )
    }

    @MainActor
    static func installedPluginDisplay(for plugin: PluginInfo, catalogItem: PluginCatalogItem?) -> I18nPluginDisplay {
        installedPluginDisplay(
            for: plugin,
            catalogItem: catalogItem,
            localeID: LanguageManager.shared.currentLocale.identifier
        )
    }

    static func installedPluginDisplay(
        for plugin: PluginInfo,
        catalogItem: PluginCatalogItem?,
        localeID: String
    ) -> I18nPluginDisplay {
        if let catalogItem {
            return pluginDisplay(for: catalogItem, localeID: localeID)
        }

        let family = installedPluginFamily(for: plugin)
        let rawName = installedPluginBaseNameCandidate(for: plugin)
        let baseName = baseNameWithoutFamilySuffix(rawName, family: family)
        let localizedDisplayName = string(
            "plugins.installed.family.\(family.rawValue).displayName",
            localeID: localeID,
            fallback: defaultInstalledPluginDisplayName(baseName: baseName, family: family),
            baseName
        )
        let displayName = sanitizedInstalledPluginDisplayName(
            localizedDisplayName,
            plugin: plugin,
            baseName: baseName,
            family: family
        )
        let localizedDescription = string(
            "plugins.installed.family.\(family.rawValue).description",
            localeID: localeID,
            fallback: defaultInstalledPluginDescription(baseName: baseName, family: family),
            baseName
        )
        let description = sanitizedInstalledPluginDescription(
            localizedDescription,
            plugin: plugin,
            baseName: baseName,
            family: family
        )
        let category = string(
            "plugins.installed.family.\(family.rawValue).category",
            localeID: localeID,
            fallback: defaultInstalledPluginCategory(family)
        )
        let status = plugin.enabled
            ? string("catalog.status.loaded", localeID: localeID, fallback: "Loaded")
            : string("catalog.status.disabled", localeID: localeID, fallback: "Disabled")
        var lines = [
            description,
            "",
            string("plugins.installed.detail.pluginId", localeID: localeID, fallback: "**Plugin ID:** `%@`", plugin.pluginId),
            "",
            string("plugins.installed.detail.status", localeID: localeID, fallback: "**Status:** %@", status)
        ]
        if !plugin.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append(string("plugins.installed.detail.version", localeID: localeID, fallback: "**Version:** %@", plugin.version))
        }

        return I18nPluginDisplay(
            displayName: displayName,
            description: description,
            longDescription: lines.joined(separator: "\n"),
            category: category,
            capabilities: [category]
        )
    }

    static func localizedSearchFields(_ localized: [String], originals: [String]) -> [String] {
        var seen = Set<String>()
        return (localized + originals).filter { value in
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
        }
    }

    static func slug(_ value: String) -> String {
        let lower = value.lowercased()
        var result = ""
        var previousWasSeparator = true

        for scalar in lower.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                result.append(".")
                previousWasSeparator = true
            }
        }

        return result.trimmingCharacters(in: CharacterSet(charactersIn: ".")).nilIfBlank ?? "item"
    }

    static func localeCandidates(for localeID: String) -> [String] {
        let normalized = localeID.replacingOccurrences(of: "_", with: "-")
        let parts = normalized.split(separator: "-").map(String.init)
        guard let language = parts.first, !language.isEmpty else { return ["en"] }

        var candidates: [String] = [normalized]
        if parts.count >= 2 {
            candidates.append("\(parts[0])-\(parts[1])")
        }
        if language == "zh" {
            let tags = Set(parts.dropFirst().map { $0.lowercased() })
            candidates.append(tags.contains("hant") || tags.contains("tw") || tags.contains("hk") || tags.contains("mo") ? "zh-Hant" : "zh-Hans")
        }
        if language == "pt" {
            candidates.append("pt-BR")
        }
        candidates.append(language)
        candidates.append("en")

        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private static func optionalString(_ key: String, localeID: String, fallback: String?) -> String? {
        let value = localizedString(key, localeID: localeID, fallback: fallback, arguments: [])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func optionalLocalizedString(_ key: String, localeID: String) -> String? {
        let value = resourceCache.value(for: key, localeID: localeID, namespaces: namespaces)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private static func localizedString(_ key: String, localeID: String, fallback: String?, arguments: [CVarArg]) -> String {
        let template = resourceCache.value(for: key, localeID: localeID, namespaces: namespaces) ?? fallback ?? key
        guard !arguments.isEmpty else { return template }
        return String(format: template, arguments: arguments)
    }

    private enum InstalledPluginFamily: String {
        case provider
        case browser
        case speech
        case memory
        case proxy
        case runtime
        case plugin
    }

    private static func installedPluginFamily(for plugin: PluginInfo) -> InstalledPluginFamily {
        let haystack = [plugin.channel, plugin.pluginId, plugin.source]
            .joined(separator: " ")
            .lowercased()

        if haystack.contains("browser") { return .browser }
        if haystack.contains("speech") || haystack.contains("elevenlabs") || haystack.contains("deepgram") { return .speech }
        if haystack.contains("memory") { return .memory }
        if haystack.contains("proxy") { return .proxy }
        if haystack.contains("runtime") || haystack.contains("core") { return .runtime }
        if haystack.contains("provider") { return .provider }
        return .plugin
    }

    private static func readableName(fromInstalledIdentifier rawValue: String) -> String? {
        let withoutScope = rawValue
            .split(separator: "/")
            .last
            .map(String.init) ?? rawValue
        let strippedSuffixes = ["-provider", "-plugin"]
            .reduce(withoutScope) { partial, suffix in
                partial.hasSuffix(suffix) ? String(partial.dropLast(suffix.count)) : partial
            }
        let name = strippedSuffixes
            .split { $0 == "-" || $0 == "_" }
            .map { word in
                humanizedInstalledPluginWord(String(word))
            }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func humanizedInstalledPluginWord(_ rawWord: String) -> String {
        switch rawWord.lowercased() {
        case "ai": return "AI"
        case "api": return "API"
        case "cli": return "CLI"
        case "http": return "HTTP"
        case "imessage": return "iMessage"
        case "irc": return "IRC"
        case "llm": return "LLM"
        case "lmstudio": return "LM Studio"
        case "mcp": return "MCP"
        case "msteams": return "MS Teams"
        case "openai": return "OpenAI"
        case "opencode": return "OpenCode"
        case "openrouter": return "OpenRouter"
        case "rpc": return "RPC"
        case "sglang": return "SGLang"
        case "sms": return "SMS"
        case "tts": return "TTS"
        case "xai": return "xAI"
        case "zai": return "Z.ai"
        default:
            guard rawWord.count > 2 else { return rawWord.uppercased() }
            return rawWord.prefix(1).uppercased() + rawWord.dropFirst()
        }
    }

    private static func installedPluginBaseNameCandidate(for plugin: PluginInfo) -> String {
        if plugin.channel.contains("/") || plugin.channel.hasPrefix("@") {
            return readableName(fromInstalledIdentifier: plugin.pluginId)
                ?? readableName(fromInstalledIdentifier: plugin.channel)
                ?? plugin.pluginId
        }

        return readableName(fromInstalledIdentifier: plugin.channel)
            ?? readableName(fromInstalledIdentifier: plugin.pluginId)
            ?? plugin.channel
    }

    private static func sanitizedInstalledPluginDisplayName(
        _ value: String,
        plugin: PluginInfo,
        baseName: String,
        family: InstalledPluginFamily
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !looksLikeRawPluginIdentifier(trimmed, plugin: plugin) else {
            return defaultInstalledPluginDisplayName(baseName: baseName, family: family)
        }
        return trimmed.isEmpty ? defaultInstalledPluginDisplayName(baseName: baseName, family: family) : trimmed
    }

    private static func sanitizedInstalledPluginDescription(
        _ value: String,
        plugin: PluginInfo,
        baseName: String,
        family: InstalledPluginFamily
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !looksLikeRawPluginIdentifier(trimmed, plugin: plugin) else {
            return defaultInstalledPluginDescription(baseName: baseName, family: family)
        }
        return trimmed.isEmpty ? defaultInstalledPluginDescription(baseName: baseName, family: family) : trimmed
    }

    private static func looksLikeRawPluginIdentifier(_ value: String, plugin: PluginInfo) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return normalized.hasPrefix("@")
            || normalized.contains("/")
            || normalized == plugin.pluginId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func baseNameWithoutFamilySuffix(_ value: String, family: InstalledPluginFamily) -> String {
        let suffix: String
        switch family {
        case .provider: suffix = " Provider"
        case .browser: suffix = " Browser"
        case .speech: suffix = " Speech"
        case .memory: suffix = " Memory"
        case .proxy: suffix = " Proxy"
        case .runtime, .plugin: suffix = ""
        }
        guard !suffix.isEmpty,
              value.localizedCaseInsensitiveContains(suffix),
              value.lowercased().hasSuffix(suffix.lowercased()) else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(value.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func defaultInstalledPluginDisplayName(baseName: String, family: InstalledPluginFamily) -> String {
        switch family {
        case .provider: return "\(baseName) Provider"
        case .browser: return "\(baseName) Browser"
        case .speech: return "\(baseName) Speech"
        case .memory: return "\(baseName) Memory"
        case .proxy: return "\(baseName) Proxy"
        case .runtime, .plugin: return baseName
        }
    }

    private static func defaultInstalledPluginDescription(baseName: String, family: InstalledPluginFamily) -> String {
        switch family {
        case .provider:
            return "Model provider for connecting OpenClaw to \(baseName) models."
        case .browser:
            return "Browser automation capability for opening pages, inspecting content, and interacting with websites."
        case .speech:
            return "Speech capability for transcription, voice, or audio-related model workflows."
        case .memory:
            return "Memory storage capability for retaining reusable context across OpenClaw sessions."
        case .proxy:
            return "Proxy capability for routing model requests through a compatible provider or local service."
        case .runtime:
            return "Core runtime capability used by OpenClaw to provide built-in plugin behavior."
        case .plugin:
            return "Installed OpenClaw plugin."
        }
    }

    private static func defaultInstalledPluginCategory(_ family: InstalledPluginFamily) -> String {
        switch family {
        case .provider: return "Provider"
        case .browser: return "Browser"
        case .speech: return "Speech"
        case .memory: return "Memory"
        case .proxy: return "Proxy"
        case .runtime: return "Runtime"
        case .plugin: return "Plugin"
        }
    }
}

private final class I18nResourceCache {
    private var cache: [String: [String: String]] = [:]
    private let lock = NSLock()

    func value(for key: String, localeID: String, namespaces: [String]) -> String? {
        for locale in I18n.localeCandidates(for: localeID) {
            for namespace in namespaces {
                if let value = resources(languageID: locale, namespace: namespace)[key],
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private func resources(languageID: String, namespace: String) -> [String: String] {
        let cacheKey = "\(languageID)/\(namespace)"
        lock.lock()
        if let cached = cache[cacheKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let loaded = loadResources(languageID: languageID, namespace: namespace)

        lock.lock()
        cache[cacheKey] = loaded
        lock.unlock()
        return loaded
    }

    private func loadResources(languageID: String, namespace: String) -> [String: String] {
        guard let url = Bundle.main.url(forResource: namespace, withExtension: "json", subdirectory: "I18n/\(languageID)"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
