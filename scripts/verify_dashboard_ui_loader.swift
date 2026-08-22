#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

let requiredPaths = [
    "OpenClawInstaller/Features/Dashboard/DashboardTypography.swift",
    "OpenClawInstaller/Features/Dashboard/DashboardView.swift",
    "OpenClawInstaller/Features/Dashboard/Sidebar/DashboardSidebar.swift",
    "OpenClawInstaller/Features/Chat/Views/ChatView.swift",
    "OpenClawInstaller/Features/Chat/Views/ComposerChrome.swift",
    "OpenClawInstaller/Features/Chat/Views/ChatBubbleViews.swift",
    "OpenClawInstaller/Features/Agents/Views/AgentSettingsPanel.swift",
    "OpenClawInstaller/Features/Dashboard/TerminalPanel.swift",
    "OpenClawInstaller/Features/Sessions/Views/SessionDetailsPanel.swift",
]

let lib = root.appendingPathComponent("scripts/lib/dashboard_ui.swift")
guard let libSource = try? String(contentsOf: lib, encoding: .utf8) else {
    fail("missing scripts/lib/dashboard_ui.swift")
}
for path in requiredPaths {
    guard libSource.contains("\"\(path)\"") else {
        fail("canonical dashboard UI loader is missing \(path)")
    }
}

/// Scripts that mention DashboardView.swift but are allowed to read it
/// without concatenating Chat/Sidebar (they lock the split itself).
let allowSingleFile: Set<String> = [
    "verify_dashboard_module_split.swift",
    "verify_dashboard_ui_loader.swift",
]

let scriptsDir = root.appendingPathComponent("scripts")
guard let files = try? FileManager.default.contentsOfDirectory(atPath: scriptsDir.path) else {
    fail("could not list scripts/")
}

let movedNeedles = [
    "struct ChatView: View",
    "struct SidebarView: View",
    "agentSidebarRow",
    "ComposerInputCardBoundsKey",
    "struct ChatBubble: View",
    "struct ThinkingIndicator",
    "composerSuggestionOverlay",
    "sessionRows(",
    "struct SessionDetailsPanel",
    "struct AgentSettingsPanel",
    "struct TerminalPanelView",
]

var offenders: [String] = []
for name in files.sorted() where name.hasPrefix("verify_") && name.hasSuffix(".swift") {
    if allowSingleFile.contains(name) { continue }
    let source = (try? String(
        contentsOf: scriptsDir.appendingPathComponent(name),
        encoding: .utf8
    )) ?? ""
    let looksAtMovedTypes = movedNeedles.contains { source.contains($0) }
    guard looksAtMovedTypes else { continue }
    let missing = requiredPaths.filter { !source.contains($0) }
    if !missing.isEmpty {
        offenders.append("\(name) missing \(missing.joined(separator: ", "))")
    }
}

if !offenders.isEmpty {
    fail("dashboard UI verifies must concat the split sources:\n" + offenders.joined(separator: "\n"))
}

print("PASS: dashboard UI loader")
