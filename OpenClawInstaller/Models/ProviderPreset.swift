import Foundation
import AppKit

// MARK: - Codable Data Structures

struct PresetModelCost: Codable, Equatable {
    var input: Double = 0
    var output: Double = 0
    var cacheRead: Double = 0
    var cacheWrite: Double = 0
}

struct PresetModel: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var reasoning: Bool = false
    var input: [String] = ["text"]
    var cost: PresetModelCost = PresetModelCost()
    var contextWindow: Int = 128000
    var maxTokens: Int = 8192
}

struct ProviderPreset: Codable, Equatable, Identifiable {
    var id: String { key }
    var key: String
    var displayName: String
    var baseUrl: String
    var api: String
    var models: [PresetModel]
}

// MARK: - Preset Manager

class ProviderPresetManager {
    private let localPath: String

    init() {
        self.localPath = NSString("~/.openclaw/providers_preset.json").expandingTildeInPath
        syncWithBundle()
    }

    /// Sync Bundle presets to local: append new providers, keep existing user versions
    private func syncWithBundle() {
        let fm = FileManager.default
        let dir = (localPath as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        guard let bundlePresets = loadFromBundle(), !bundlePresets.isEmpty else { return }

        // Local file doesn't exist → copy Bundle directly
        guard fm.fileExists(atPath: localPath),
              let localData = try? Data(contentsOf: URL(fileURLWithPath: localPath)),
              var localPresets = try? JSONDecoder().decode([ProviderPreset].self, from: localData) else {
            if let bundlePath = Bundle.main.path(forResource: "providers_preset", ofType: "json") {
                try? fm.copyItem(atPath: bundlePath, toPath: localPath)
            }
            return
        }

        // Find providers in Bundle that are missing locally
        let localKeys = Set(localPresets.map { $0.key })
        let newPresets = bundlePresets.filter { !localKeys.contains($0.key) }

        guard !newPresets.isEmpty else { return }

        // Insert new providers before "custom" (custom stays at the end)
        if let customIndex = localPresets.firstIndex(where: { $0.key == "custom" }) {
            localPresets.insert(contentsOf: newPresets, at: customIndex)
        } else {
            localPresets.append(contentsOf: newPresets)
        }

        // Write back to local file
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(localPresets) {
            try? data.write(to: URL(fileURLWithPath: localPath))
        }
    }

    /// Load presets from local JSON file
    func loadPresets() -> [ProviderPreset] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: localPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: localPath)),
              let presets = try? JSONDecoder().decode([ProviderPreset].self, from: data) else {
            // Fallback: try loading from Bundle directly
            return loadFromBundle() ?? []
        }
        return presets
    }

    private func loadFromBundle() -> [ProviderPreset]? {
        guard let bundlePath = Bundle.main.path(forResource: "providers_preset", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: bundlePath)),
              let presets = try? JSONDecoder().decode([ProviderPreset].self, from: data) else {
            return nil
        }
        return presets
    }

    /// Open the local preset file in TextEdit
    func openPresetFile() {
        let url = URL(fileURLWithPath: localPath)
        if FileManager.default.fileExists(atPath: localPath) {
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }

    /// Find a provider preset by baseUrl
    func findProvider(byBaseUrl baseUrl: String) -> ProviderPreset? {
        let presets = loadPresets()
        return presets.first { $0.baseUrl == baseUrl && $0.key != "custom" }
    }

    /// Find a provider preset by key
    func findProvider(byKey key: String) -> ProviderPreset? {
        let presets = loadPresets()
        return presets.first { $0.key == key }
    }
}
