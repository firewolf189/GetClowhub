import Combine
import Foundation
import AppKit

/// Represents the editable fields from ~/.openclaw/openclaw.json
struct AppSettings: Equatable {
    var gatewayPort: Int = 18789
    var gatewayAuthToken: String = ""
    var modelBaseUrl: String = ""
    var modelApiKey: String = ""
    var selectedProviderKey: String = "aliyun-codingplan"
    var providerApi: String = "openai-completions"
    var configuredModels: [PresetModel] = []

    static func == (lhs: AppSettings, rhs: AppSettings) -> Bool {
        lhs.gatewayPort == rhs.gatewayPort
            && lhs.gatewayAuthToken == rhs.gatewayAuthToken
            && lhs.modelBaseUrl == rhs.modelBaseUrl
            && lhs.modelApiKey == rhs.modelApiKey
            && lhs.selectedProviderKey == rhs.selectedProviderKey
            && lhs.providerApi == rhs.providerApi
            && lhs.configuredModels == rhs.configuredModels
    }
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

    // MARK: - Read from openclaw.json

    /// Load settings from ~/.openclaw/openclaw.json
    func loadFromFile() {
        guard let dict = readConfigDict() else { return }

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
           let providers = models["providers"] as? [String: Any],
           let firstKey = providers.keys.first,
           let firstProvider = providers[firstKey] as? [String: Any] {
            newSettings.selectedProviderKey = firstKey
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

        // Only publish if changed, to avoid unnecessary SwiftUI re-renders
        if newSettings != settings {
            settings = newSettings
        }
    }

    // MARK: - Write to openclaw.json

    /// Save edited fields back to ~/.openclaw/openclaw.json
    /// Creates the full models.providers node if it doesn't exist.
    func saveToFile() -> Bool {
        var dict = readConfigDict() ?? [:]

        // Update gateway.port and gateway.auth.token
        var gateway = dict["gateway"] as? [String: Any] ?? [:]
        gateway["port"] = settings.gatewayPort

        var auth = gateway["auth"] as? [String: Any] ?? [:]
        auth["token"] = settings.gatewayAuthToken
        gateway["auth"] = auth

        dict["gateway"] = gateway

        // Build the provider entry
        let providerKey = settings.selectedProviderKey.isEmpty ? "custom" : settings.selectedProviderKey

        let modelsArray: [[String: Any]] = settings.configuredModels.map { model in
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
            "baseUrl": settings.modelBaseUrl,
            "apiKey": settings.modelApiKey,
            "api": settings.providerApi,
            "models": modelsArray
        ]

        // Build models node — remove old providers and set new one
        var modelsNode = dict["models"] as? [String: Any] ?? [:]
        modelsNode["mode"] = "merge"
        // Replace all providers with the single selected one
        modelsNode["providers"] = [providerKey: providerEntry]
        dict["models"] = modelsNode

        // Build agents.defaults
        var agents = dict["agents"] as? [String: Any] ?? [:]
        var defaults = agents["defaults"] as? [String: Any] ?? [:]

        // Set primary model to first configured model
        if let firstModel = settings.configuredModels.first {
            defaults["model"] = ["primary": "\(providerKey)/\(firstModel.id)"]
        }

        // Build models mapping: "providerKey/modelId": {}
        var modelsMapping: [String: Any] = [:]
        for model in settings.configuredModels {
            modelsMapping["\(providerKey)/\(model.id)"] = [String: Any]()
        }
        defaults["models"] = modelsMapping
        agents["defaults"] = defaults
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
        guard FileManager.default.fileExists(atPath: configPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }

    private func writeConfigDict(_ dict: [String: Any]) -> Bool {
        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
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
