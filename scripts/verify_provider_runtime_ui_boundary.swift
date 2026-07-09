#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func require(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let appSettings = read("OpenClawInstaller/Shared/Models/AppSettings.swift")
let saveToFile = slice(
    appSettings,
    from: "    func saveToFile() -> Bool {",
    to: "    // MARK: - Open config file in editor"
)
let configuredProvider = slice(
    appSettings,
    from: "struct ConfiguredCustomProvider",
    to: "@MainActor"
)
let runtimeDictionary = slice(
    appSettings,
    from: "private static func runtimeCustomProviderDictionary",
    to: "private static func modelDictionary"
)

require(
    !configuredProvider.contains("displayName"),
    "ConfiguredCustomProvider must not carry a persisted displayName; provider titles should be derived from runtime fields."
)

require(
    saveToFile.contains("runtimeCustomProviderDictionary(from: provider)") &&
        !saveToFile.contains("customProviderSnapshotDictionary(from: provider)") &&
        !saveToFile.contains("customProviderSnapshots[provider.key]"),
    "saveToFile must persist only runtime provider fields for custom providers."
)

require(
    !runtimeDictionary.contains("\"displayName\"") &&
        runtimeDictionary.contains("\"baseUrl\"") &&
        runtimeDictionary.contains("\"apiKey\"") &&
        runtimeDictionary.contains("\"api\"") &&
        runtimeDictionary.contains("\"models\""),
    "Runtime provider config must not write UI-only displayName into openclaw.json."
)

require(
    !appSettings.contains("customProviderSnapshotDictionary") &&
        !appSettings.contains("customProviderSnapshotsKey"),
    "App-state must not keep duplicate custom provider snapshots after displayName removal."
)

print("Provider runtime/UI boundary verification passed")
