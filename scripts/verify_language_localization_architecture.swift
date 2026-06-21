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

let app = read("OpenClawInstaller/OpenClawInstallerApp.swift")
let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let localizable = read("OpenClawInstaller/Localizable.xcstrings")

require(
    app.contains("@StateObject private var languageManager = LanguageManager.shared"),
    "App entry should inject the existing LanguageManager.shared instance, not create a second LanguageManager."
)

require(
    !app.contains("@StateObject private var languageManager = LanguageManager()"),
    "App entry must not create a second LanguageManager instance."
)

let forbiddenDashboardPatterns = [
    "hasPrefix(\"zh\")",
    "isChinese ?",
    "let isChinese =",
    "private var isChinese:"
]

for pattern in forbiddenDashboardPatterns {
    require(
        !dashboard.contains(pattern),
        "DashboardView should not contain per-view Chinese/English branching: \(pattern)"
    )
}

let requiredLocalizedKeys = [
    "Understanding requirements...",
    "Starting task execution...",
    "Working",
    "Working for %@",
    "Done in %@",
    "%lldm %llds",
    "%llds"
]

for key in requiredLocalizedKeys {
    require(
        localizable.contains("\"\(key)\""),
        "Localizable.xcstrings should contain key: \(key)"
    )
}

print("Language localization architecture verification passed")
