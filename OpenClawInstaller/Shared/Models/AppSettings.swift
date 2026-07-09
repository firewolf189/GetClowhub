import Combine
import Foundation
import AppKit

/// Represents the editable fields from ~/.openclaw/openclaw.json
struct AppSettings: Equatable {
    var gatewayPort: Int = 18789
    var gatewayAuthToken: String = ""
    var modelBaseUrl: String = ""
    var modelApiKey: String = ""
    var selectedProviderKey: String = ""
    var providerApi: String = "openai-completions"
    var configuredModels: [PresetModel] = []
    var activeServiceSource: String = "custom" // "getclawhub" or "custom"
    var customProviders: [ConfiguredCustomProvider] = []

    static func == (lhs: AppSettings, rhs: AppSettings) -> Bool {
        lhs.gatewayPort == rhs.gatewayPort
            && lhs.gatewayAuthToken == rhs.gatewayAuthToken
            && lhs.modelBaseUrl == rhs.modelBaseUrl
            && lhs.modelApiKey == rhs.modelApiKey
            && lhs.selectedProviderKey == rhs.selectedProviderKey
            && lhs.providerApi == rhs.providerApi
            && lhs.configuredModels == rhs.configuredModels
            && lhs.activeServiceSource == rhs.activeServiceSource
            && lhs.customProviders == rhs.customProviders
    }
}

struct ConfiguredProviderModelSource {
    let providerKey: String
    let models: [PresetModel]
}

struct ConfiguredCustomProvider: Equatable, Identifiable {
    var id: String { key }
    var key: String
    var baseUrl: String
    var apiKey: String
    var api: String
    var models: [PresetModel]
}

@MainActor
class AppSettingsManager: ObservableObject {
    @Published var settings: AppSettings

    private let configPath: String

    init() {
        self.configPath = NSString("~/.openclaw/openclaw.json").expandingTildeInPath
        self.settings = AppSettings()
        loadFromFile()
    }

    private static var defaultConfigPath: String {
        NSString("~/.openclaw/openclaw.json").expandingTildeInPath
    }
    private static var appStatePath: String {
        NSString("~/.openclaw/getclawhub-app-state.json").expandingTildeInPath
    }
    private static let legacyAppStateKey = "getclawhubApp"
    private static let activeServiceSourceKey = "activeServiceSource"
    private static let selectedCustomProviderKey = "selectedCustomProviderKey"

    // MARK: - Read from openclaw.json

    /// Load settings from ~/.openclaw/openclaw.json
    func loadFromFile() {
        guard let rawDict = readConfigDict() else { return }
        let appState = Self.readAppStateDict(legacyConfig: rawDict)
        let dictWithoutLegacyState = Self.removeLegacyAppState(fromConfigAt: configPath, dict: rawDict)
        let dict = Self.removeUnsupportedProviderMetadata(fromConfigAt: configPath, dict: dictWithoutLegacyState)

        var newSettings = AppSettings()

        // gateway.port
        if let gateway = dict["gateway"] as? [String: Any],
           let port = gateway["port"] as? Int {
            newSettings.gatewayPort = port
        }

        // gateway.auth.token
        if let gateway = dict["gateway"] as? [String: Any],
           let auth = gateway["auth"] as? [String: Any],
           let token = auth["token"] as? String {
            newSettings.gatewayAuthToken = token
        }

        // Provider key, baseUrl, apiKey, api, models
        if let models = dict["models"] as? [String: Any],
           let providers = models["providers"] as? [String: Any] {
            let activeProviderKey = Self.activeProviderKey(in: dict)
            let hasGetclawhub = providers["getclawhub"] != nil
            let customKeys = providers.keys.filter { $0 != "getclawhub" }.sorted()
            let hasCustom = !customKeys.isEmpty
            let savedSource = appState?[Self.activeServiceSourceKey] as? String
            let savedCustomProvider = appState?[Self.selectedCustomProviderKey] as? String
            newSettings.customProviders = customKeys.compactMap { key in
                Self.customProvider(
                    from: key,
                    providers: providers
                )
            }

            // The runtime default model is the source of truth for which provider is active.
            // If both providers exist, do not let a synced GetClawHub key override a custom default.
            if savedSource == "custom", hasCustom {
                newSettings.activeServiceSource = "custom"
            } else if savedSource == "getclawhub", hasGetclawhub {
                newSettings.activeServiceSource = "getclawhub"
            } else if activeProviderKey == "getclawhub" || (activeProviderKey == nil && hasGetclawhub && !hasCustom) {
                newSettings.activeServiceSource = "getclawhub"
            } else if activeProviderKey != nil || hasCustom {
                newSettings.activeServiceSource = "custom"
            }

            // Load the user's custom provider (non-getclawhub)
            let customProviderKey: String? = {
                if let savedCustomProvider,
                   Self.customProviderEntry(for: savedCustomProvider, providers: providers) != nil,
                   savedCustomProvider != "getclawhub" {
                    return savedCustomProvider
                }
                if let activeProviderKey,
                   activeProviderKey != "getclawhub",
                   Self.customProviderEntry(for: activeProviderKey, providers: providers) != nil {
                    return activeProviderKey
                }
                return customKeys.first
            }()
            if let providerKey = customProviderKey,
               let firstProvider = Self.customProviderEntry(for: providerKey, providers: providers) {
                newSettings.selectedProviderKey = providerKey
                if let baseUrl = firstProvider["baseUrl"] as? String {
                    newSettings.modelBaseUrl = baseUrl
                }
                if let apiKey = firstProvider["apiKey"] as? String {
                    newSettings.modelApiKey = apiKey
                }
                if let api = firstProvider["api"] as? String {
                    newSettings.providerApi = api
                }
                if let modelArray = firstProvider["models"] as? [[String: Any]] {
                    newSettings.configuredModels = modelArray.compactMap { Self.parseModelDict($0) }
                }
            }

            if newSettings.activeServiceSource == "getclawhub",
               let getclawhubProvider = providers["getclawhub"] as? [String: Any] {
                if let baseUrl = getclawhubProvider["baseUrl"] as? String {
                    newSettings.modelBaseUrl = baseUrl
                }
                if let apiKey = getclawhubProvider["apiKey"] as? String {
                    newSettings.modelApiKey = apiKey
                }
                if let api = getclawhubProvider["api"] as? String {
                    newSettings.providerApi = api
                }
                if let modelArray = getclawhubProvider["models"] as? [[String: Any]] {
                    newSettings.configuredModels = modelArray.compactMap { Self.parseModelDict($0) }
                }
            }
        }

        // Only publish if changed, to avoid unnecessary SwiftUI re-renders
        if newSettings != settings {
            settings = newSettings
        }
    }

    func loadConfiguredProviderModelSources() -> [ConfiguredProviderModelSource] {
        guard let rawDict = readConfigDict() else {
            return []
        }
        let dict = Self.removeUnsupportedProviderMetadata(fromConfigAt: configPath, dict: rawDict)
        guard let modelsNode = dict["models"] as? [String: Any],
              let providers = modelsNode["providers"] as? [String: Any] else {
            return []
        }
        let providerKeys = providers.keys.sorted()

        return providerKeys.compactMap { key in
            guard let provider = providers[key] as? [String: Any],
                  let modelArray = provider["models"] as? [[String: Any]] else {
                return nil
            }
            let parsedModels = modelArray.compactMap { Self.parseModelDict($0) }
            guard !parsedModels.isEmpty else { return nil }
            return ConfiguredProviderModelSource(providerKey: key, models: parsedModels)
        }
    }

    // MARK: - Write to openclaw.json

    /// Save edited fields back to ~/.openclaw/openclaw.json
    /// Creates the full models.providers node if it doesn't exist.
    func saveToFile() -> Bool {
        var dict = Self.sanitizedProviderMetadata(readConfigDict() ?? [:]).dict
        dict.removeValue(forKey: Self.legacyAppStateKey)

        // Update gateway section
        var gateway = dict["gateway"] as? [String: Any] ?? [:]
        gateway["port"] = settings.gatewayPort
        gateway["mode"] = gateway["mode"] as? String ?? "local"

        var auth = gateway["auth"] as? [String: Any] ?? [:]
        // Avoid landing `mode = "none"`: in that mode the gateway returns
        // sharedAuthOk=false and rejects unpaired operator clients with NOT_PAIRED.
        // "token" is the lowest-friction value that still keeps unpaired clients usable.
        auth["mode"] = (auth["mode"] as? String) ?? "token"
        auth["token"] = settings.gatewayAuthToken
        gateway["auth"] = auth

        dict["gateway"] = gateway

        let providerKey = settings.selectedProviderKey.isEmpty ? "custom" : settings.selectedProviderKey

        // Build models node. Preserve inactive providers so switching between
        // official and custom services does not erase the user's saved keys.
        let previousActiveProviderKey = Self.activeProviderKey(in: dict)
        var modelsNode = dict["models"] as? [String: Any] ?? [:]
        modelsNode["mode"] = "merge"
        var providers = modelsNode["providers"] as? [String: Any] ?? [:]
        let getclawhubProvider = providers["getclawhub"]

        providers = [:]
        if let getclawhubProvider {
            providers["getclawhub"] = getclawhubProvider
        }

        let shouldPersistSelectedCustomProvider = settings.activeServiceSource != "getclawhub"
            && !settings.selectedProviderKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (
                !settings.modelBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !settings.modelApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !settings.configuredModels.isEmpty
            )
        let customProviders = Self.normalizedCustomProviders(
            settings.customProviders,
            selectedProviderKey: providerKey,
            selectedProvider: shouldPersistSelectedCustomProvider ? ConfiguredCustomProvider(
                key: providerKey,
                baseUrl: settings.modelBaseUrl,
                apiKey: settings.modelApiKey,
                api: settings.providerApi,
                models: settings.configuredModels
            ) : nil
        )
        for provider in customProviders {
            providers[provider.key] = Self.runtimeCustomProviderDictionary(from: provider)
        }
        modelsNode["providers"] = providers
        dict["models"] = modelsNode

        Self.updateAppState(
            activeServiceSource: settings.activeServiceSource,
            selectedCustomProviderKey: customProviders.contains(where: { $0.key == providerKey })
                ? providerKey
                : customProviders.first?.key
        )

        // Build agents.defaults
        var agents = dict["agents"] as? [String: Any] ?? [:]
        var defaults = agents["defaults"] as? [String: Any] ?? [:]

        // Collect the active provider key and its model IDs for reuse below
        let activeProviderKey: String
        let activeModelIds: [String]

        if settings.activeServiceSource == "getclawhub" {
            activeProviderKey = "getclawhub"
            activeModelIds = Self.providerModelIds(from: providers["getclawhub"])
        } else {
            activeProviderKey = providerKey
            activeModelIds = settings.configuredModels.map { $0.id }
        }

        if let firstModelId = activeModelIds.first {
            let fallbackId = activeModelIds.first(where: { $0 != firstModelId })
            var modelDict: [String: Any] = ["primary": "\(activeProviderKey)/\(firstModelId)"]
            if let fb = fallbackId {
                modelDict["fallbacks"] = ["\(activeProviderKey)/\(fb)"]
            }
            defaults["model"] = modelDict
        } else {
            defaults.removeValue(forKey: "model")
        }

        let activeProviderRuntimeModelEntries = Self.runtimeModelEntries(providerKey: activeProviderKey, modelIds: activeModelIds)
        let mergedRuntimeModelEntries = Self.mergedRuntimeModelEntries(
            providers: providers,
            activeProviderKey: activeProviderKey,
            activeProviderRuntimeModelEntries: activeProviderRuntimeModelEntries
        )
        if mergedRuntimeModelEntries.isEmpty {
            defaults.removeValue(forKey: "models")
        } else {
            defaults["models"] = mergedRuntimeModelEntries
        }

        // Update imageModel — only image-capable models, fallback is one model different from primary
        let imageModelIds: [String]
        if settings.activeServiceSource == "getclawhub" {
            imageModelIds = Self.providerImageModelIds(from: providers["getclawhub"])
        } else {
            imageModelIds = settings.configuredModels.filter { $0.input.contains("image") }.map { $0.id }
        }
        if let firstImageId = imageModelIds.first {
            let imageFallbackId = imageModelIds.first(where: { $0 != firstImageId })
            var imageDict: [String: Any] = ["primary": "\(activeProviderKey)/\(firstImageId)"]
            if let fb = imageFallbackId {
                imageDict["fallbacks"] = ["\(activeProviderKey)/\(fb)"]
            }
            defaults["imageModel"] = imageDict
        } else {
            defaults.removeValue(forKey: "imageModel")
        }

        agents["defaults"] = defaults

        // Update agents.list. Since providers are preserved, switch agents that
        // were following the previous active provider over to the newly active
        // default, while leaving explicit third-party overrides intact.
        let activeProviderKeys = Set(providers.keys)
        if var agentList = agents["list"] as? [[String: Any]] {
            let defaultModel = activeModelIds.first.map { "\(activeProviderKey)/\($0)" } ?? ""
            for i in agentList.indices {
                guard let model = agentList[i]["model"] as? String,
                      let slash = model.firstIndex(of: "/") else { continue }
                let modelProvider = String(model[model.startIndex..<slash])
                let wasPreviousActive = previousActiveProviderKey != nil
                    && previousActiveProviderKey != activeProviderKey
                    && modelProvider == previousActiveProviderKey
                if !defaultModel.isEmpty && (!activeProviderKeys.contains(modelProvider) || wasPreviousActive) {
                    agentList[i]["model"] = defaultModel
                }
            }
            agents["list"] = agentList
        }

        dict["agents"] = agents

        return writeConfigDict(dict)
    }

    // MARK: - Open config file in editor

    func openConfigFile() {
        let url = URL(fileURLWithPath: configPath)
        if FileManager.default.fileExists(atPath: configPath) {
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }

    // MARK: - GetClawHub Provider

    /// Write (or update) the `getclawhub` provider entry in openclaw.json.
    /// By default this only syncs the provider entry. Passing `activate: true`
    /// switches the runtime default model to GetClawHub after an explicit user save.
    static func writeGetClawHubProvider(apiKey: String, models: [PresetModel], baseUrl: String = "https://ai.getclawhub.com/v1", activate: Bool = false) {
        let configPath = defaultConfigPath
        let fm = FileManager.default

        // Ensure directory exists
        let dirPath = NSString("~/.openclaw").expandingTildeInPath
        if !fm.fileExists(atPath: dirPath) {
            try? fm.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        }

        var dict: [String: Any] = [:]
        if fm.fileExists(atPath: configPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = sanitizedProviderMetadata(existing).dict
        }
        let existingAppState = readAppStateDict(legacyConfig: dict)
        dict.removeValue(forKey: legacyAppStateKey)
        let previousActiveProviderKey = activeProviderKey(in: dict)

        // Build getclawhub provider entry with full model details (same as custom provider)
        let modelEntries: [[String: Any]] = models.map { model in
            var m: [String: Any] = [
                "id": model.id,
                "name": model.name,
                "reasoning": model.reasoning,
                "input": model.input,
                "contextWindow": model.contextWindow,
                "maxTokens": model.maxTokens
            ]
            m["cost"] = [
                "input": model.cost.input,
                "output": model.cost.output,
                "cacheRead": model.cost.cacheRead,
                "cacheWrite": model.cost.cacheWrite
            ]
            return m
        }

        let providerEntry: [String: Any] = [
            "baseUrl": baseUrl,
            "apiKey": apiKey,
            "api": "openai-completions",
            "models": modelEntries
        ]

        var modelsNode = dict["models"] as? [String: Any] ?? [:]
        modelsNode["mode"] = "merge"
        var providers = modelsNode["providers"] as? [String: Any] ?? [:]
        providers["getclawhub"] = providerEntry
        modelsNode["providers"] = providers
        dict["models"] = modelsNode

        let selectedCustomProvider = (existingAppState?[selectedCustomProviderKey] as? String)
            ?? providers.keys.filter { $0 != "getclawhub" }.sorted().first
        updateAppState(
            activeServiceSource: activate ? "getclawhub" : nil,
            selectedCustomProviderKey: selectedCustomProvider
        )

        guard activate else {
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
            }
            return
        }

        // Update agents.defaults: model, models, imageModel
        let modelIds = models.map { $0.id }
        var agents = dict["agents"] as? [String: Any] ?? [:]
        var defaults = agents["defaults"] as? [String: Any] ?? [:]

        if let firstId = modelIds.first {
            let fallbackId = modelIds.first(where: { $0 != firstId })
            var modelDict: [String: Any] = ["primary": "getclawhub/\(firstId)"]
            if let fb = fallbackId {
                modelDict["fallbacks"] = ["getclawhub/\(fb)"]
            }
            defaults["model"] = modelDict
        }
        // imageModel — only models with image input, fallback is one different from primary
        let imageModelIds = models.filter { $0.input.contains("image") }.map { $0.id }
        if let firstImageId = imageModelIds.first {
            let imageFallbackId = imageModelIds.first(where: { $0 != firstImageId })
            var imageDict: [String: Any] = ["primary": "getclawhub/\(firstImageId)"]
            if let fb = imageFallbackId {
                imageDict["fallbacks"] = ["getclawhub/\(fb)"]
            }
            defaults["imageModel"] = imageDict
        } else {
            defaults.removeValue(forKey: "imageModel")
        }
        let activeProviderRuntimeModelEntries = runtimeModelEntries(providerKey: "getclawhub", modelIds: modelIds)
        let mergedRuntimeModelEntries = mergedRuntimeModelEntries(
            providers: providers,
            activeProviderKey: "getclawhub",
            activeProviderRuntimeModelEntries: activeProviderRuntimeModelEntries
        )
        defaults["models"] = mergedRuntimeModelEntries
        agents["defaults"] = defaults

        // Update agents.list — switch refs from the previously active provider.
        if var agentList = agents["list"] as? [[String: Any]] {
            let defaultModel = modelIds.first.map { "getclawhub/\($0)" } ?? ""
            for i in agentList.indices {
                guard let model = agentList[i]["model"] as? String,
                      let slash = model.firstIndex(of: "/") else { continue }
                let modelProvider = String(model[model.startIndex..<slash])
                let wasPreviousActive = previousActiveProviderKey != nil
                    && previousActiveProviderKey != "getclawhub"
                    && modelProvider == previousActiveProviderKey
                if !defaultModel.isEmpty && (!providers.keys.contains(modelProvider) || wasPreviousActive) {
                    agentList[i]["model"] = defaultModel
                }
            }
            agents["list"] = agentList
        }
        dict["agents"] = agents

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
        }
    }

    // MARK: - Helpers

    /// Get the provider name (for display)
    func providerName() -> String {
        if !settings.selectedProviderKey.isEmpty {
            return settings.selectedProviderKey
        }
        guard let dict = readConfigDict(),
              let models = dict["models"] as? [String: Any],
              let providers = models["providers"] as? [String: Any],
              let firstKey = providers.keys.first else {
            return "unknown"
        }
        return firstKey
    }

    private func readConfigDict() -> [String: Any]? {
        Self.readConfigDict(at: configPath)
    }

    private static func readConfigDict(at path: String) -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }

    static func shouldAutoApplyGetClawHubProvider() -> Bool {
        guard let rawDict = readConfigDict(at: defaultConfigPath) else { return true }
        let dictWithoutLegacyState = removeLegacyAppState(fromConfigAt: defaultConfigPath, dict: rawDict)
        let dict = removeUnsupportedProviderMetadata(fromConfigAt: defaultConfigPath, dict: dictWithoutLegacyState)
        if let appState = readAppStateDict(legacyConfig: dict),
           let savedSource = appState[activeServiceSourceKey] as? String {
            return savedSource == "getclawhub"
        }
        guard let models = dict["models"] as? [String: Any],
              let providers = models["providers"] as? [String: Any],
              !providers.isEmpty else {
            return true
        }

        let activeProvider = activeProviderKey(in: dict)
        if let activeProvider {
            return activeProvider == "getclawhub"
        }

        let hasCustom = providers.keys.contains { $0 != "getclawhub" }
        return !hasCustom
    }

    private static func activeProviderKey(in dict: [String: Any]) -> String? {
        guard let agents = dict["agents"] as? [String: Any],
              let defaults = agents["defaults"] as? [String: Any],
              let model = defaults["model"] as? [String: Any],
              let primary = model["primary"] as? String,
              let slash = primary.firstIndex(of: "/") else {
            return nil
        }
        let provider = String(primary[..<slash])
        return provider.isEmpty ? nil : provider
    }

    private static func providerModelIds(from provider: Any?) -> [String] {
        guard let provider = provider as? [String: Any],
              let models = provider["models"] as? [[String: Any]] else {
            return []
        }
        return models.compactMap { $0["id"] as? String }
    }

    private static func providerImageModelIds(from provider: Any?) -> [String] {
        guard let provider = provider as? [String: Any],
              let models = provider["models"] as? [[String: Any]] else {
            return []
        }
        return models.compactMap { model in
            guard let id = model["id"] as? String,
                  let input = model["input"] as? [String],
                  input.contains("image") else {
                return nil
            }
            return id
        }
    }

    private static func runtimeModelEntries(providerKey: String, modelIds: [String]) -> [String: Any] {
        var entries: [String: Any] = [:]
        for modelId in modelIds {
            let runtimeId = modelId.hasPrefix("\(providerKey)/") ? modelId : "\(providerKey)/\(modelId)"
            entries[runtimeId] = [String: Any]()
        }
        return entries
    }

    private static func mergedRuntimeModelEntries(
        providers: [String: Any],
        activeProviderKey: String,
        activeProviderRuntimeModelEntries: [String: Any]
    ) -> [String: Any] {
        var entries: [String: Any] = [:]
        for providerKey in providers.keys.sorted() {
            let providerEntries = providerKey == activeProviderKey
                ? activeProviderRuntimeModelEntries
                : runtimeModelEntries(providerKey: providerKey, modelIds: providerModelIds(from: providers[providerKey]))
            for (modelId, value) in providerEntries {
                entries[modelId] = value
            }
        }
        return entries
    }

    private static func customProviderEntry(
        for key: String,
        providers: [String: Any]
    ) -> [String: Any]? {
        guard let provider = providers[key] as? [String: Any] else {
            return nil
        }
        return provider
    }

    private static func customProvider(
        from key: String,
        providers: [String: Any]
    ) -> ConfiguredCustomProvider? {
        guard key != "getclawhub",
              let entry = customProviderEntry(for: key, providers: providers) else {
            return nil
        }
        let baseUrl = entry["baseUrl"] as? String ?? ""
        let apiKey = entry["apiKey"] as? String ?? ""
        let api = entry["api"] as? String ?? "openai-completions"
        let models = (entry["models"] as? [[String: Any]] ?? []).compactMap { parseModelDict($0) }
        return ConfiguredCustomProvider(
            key: key,
            baseUrl: baseUrl,
            apiKey: apiKey,
            api: api,
            models: models
        )
    }

    private static func runtimeCustomProviderDictionary(from provider: ConfiguredCustomProvider) -> [String: Any] {
        [
            "baseUrl": provider.baseUrl,
            "apiKey": provider.apiKey,
            "api": provider.api,
            "models": provider.models.map(Self.modelDictionary(from:))
        ]
    }

    private static func modelDictionary(from model: PresetModel) -> [String: Any] {
        var entry: [String: Any] = [
            "id": model.id,
            "name": model.name,
            "reasoning": model.reasoning,
            "input": model.input,
            "contextWindow": model.contextWindow,
            "maxTokens": model.maxTokens
        ]
        entry["cost"] = [
            "input": model.cost.input,
            "output": model.cost.output,
            "cacheRead": model.cost.cacheRead,
            "cacheWrite": model.cost.cacheWrite
        ]
        return entry
    }

    private static func normalizedCustomProviders(
        _ providers: [ConfiguredCustomProvider],
        selectedProviderKey: String,
        selectedProvider: ConfiguredCustomProvider?
    ) -> [ConfiguredCustomProvider] {
        var result = providers.filter { $0.key != "getclawhub" }
        if let selectedProvider, !selectedProvider.key.isEmpty {
            if let index = result.firstIndex(where: { $0.key == selectedProvider.key }) {
                result[index] = selectedProvider
            } else {
                result.append(selectedProvider)
            }
        }
        return result
            .filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                if lhs.key == selectedProviderKey { return true }
                if rhs.key == selectedProviderKey { return false }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
    }

    private static func updateAppState(
        activeServiceSource: String?,
        selectedCustomProviderKey selectedCustomProvider: String?
    ) {
        var appState = readAppStateDict() ?? [:]
        appState.removeValue(forKey: "customProviders")

        if let activeServiceSource {
            appState[activeServiceSourceKey] = activeServiceSource
        }
        if let selectedCustomProvider, selectedCustomProvider != "getclawhub" {
            appState[selectedCustomProviderKey] = selectedCustomProvider
        } else {
            appState.removeValue(forKey: selectedCustomProviderKey)
        }
        if !appState.isEmpty {
            writeAppStateDict(appState)
        } else if FileManager.default.fileExists(atPath: appStatePath) {
            try? FileManager.default.removeItem(atPath: appStatePath)
        }
    }

    private static func readAppStateDict(legacyConfig: [String: Any]? = nil) -> [String: Any]? {
        var appState: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: appStatePath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: appStatePath)),
           let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            appState = saved
        }

        if let legacyState = legacyConfig?[legacyAppStateKey] as? [String: Any] {
            appState = mergeAppState(fileState: appState, legacyState: legacyState)
            writeAppStateDict(appState)
        } else if appState.removeValue(forKey: "customProviders") != nil {
            if appState.isEmpty {
                try? FileManager.default.removeItem(atPath: appStatePath)
            } else {
                writeAppStateDict(appState)
            }
        }

        return appState.isEmpty ? nil : appState
    }

    private static func mergeAppState(fileState: [String: Any], legacyState: [String: Any]) -> [String: Any] {
        var merged = legacyState
        for (key, value) in fileState {
            merged[key] = value
        }
        merged.removeValue(forKey: "customProviders")
        return merged
    }

    private static func writeAppStateDict(_ appState: [String: Any]) {
        let dirPath = NSString("~/.openclaw").expandingTildeInPath
        if !FileManager.default.fileExists(atPath: dirPath) {
            try? FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: appState, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: URL(fileURLWithPath: appStatePath), options: .atomic)
    }

    @discardableResult
    private static func removeLegacyAppState(fromConfigAt path: String, dict: [String: Any]) -> [String: Any] {
        guard dict[legacyAppStateKey] != nil else { return dict }
        var sanitized = dict
        sanitized.removeValue(forKey: legacyAppStateKey)
        guard let data = try? JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted, .sortedKeys]) else {
            return sanitized
        }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        return sanitized
    }

    @discardableResult
    private static func removeUnsupportedProviderMetadata(fromConfigAt path: String, dict: [String: Any]) -> [String: Any] {
        let result = sanitizedProviderMetadata(dict)
        guard result.changed,
              let data = try? JSONSerialization.data(withJSONObject: result.dict, options: [.prettyPrinted, .sortedKeys]) else {
            return result.dict
        }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        return result.dict
    }

    private static func sanitizedProviderMetadata(_ dict: [String: Any]) -> (dict: [String: Any], changed: Bool) {
        var sanitized = dict
        guard var modelsNode = sanitized["models"] as? [String: Any],
              var providers = modelsNode["providers"] as? [String: Any] else {
            return (dict, false)
        }

        var changed = false
        for key in providers.keys {
            guard var provider = providers[key] as? [String: Any] else { continue }
            if provider.removeValue(forKey: "displayName") != nil {
                providers[key] = provider
                changed = true
            }
        }

        guard changed else { return (dict, false) }
        modelsNode["providers"] = providers
        sanitized["models"] = modelsNode
        return (sanitized, true)
    }

    private func writeConfigDict(_ dict: [String: Any]) -> Bool {
        do {
            var sanitized = Self.sanitizedProviderMetadata(dict).dict
            sanitized.removeValue(forKey: Self.legacyAppStateKey)
            let data = try JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Parse a model dictionary from JSON into PresetModel
    private static func parseModelDict(_ dict: [String: Any]) -> PresetModel? {
        guard let id = dict["id"] as? String else { return nil }
        let name = dict["name"] as? String ?? id
        let reasoning = dict["reasoning"] as? Bool ?? false
        let input = dict["input"] as? [String] ?? ["text"]
        let contextWindow = dict["contextWindow"] as? Int ?? 128000
        let maxTokens = dict["maxTokens"] as? Int ?? 8192

        var cost = PresetModelCost()
        if let costDict = dict["cost"] as? [String: Any] {
            cost.input = costDict["input"] as? Double ?? 0
            cost.output = costDict["output"] as? Double ?? 0
            cost.cacheRead = costDict["cacheRead"] as? Double ?? 0
            cost.cacheWrite = costDict["cacheWrite"] as? Double ?? 0
        }

        return PresetModel(
            id: id,
            name: name,
            reasoning: reasoning,
            input: input,
            cost: cost,
            contextWindow: contextWindow,
            maxTokens: maxTokens
        )
    }
}
