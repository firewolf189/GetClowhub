#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fail("could not read \(path)")
    }
    return text
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fail(message) }
}

@discardableResult
func run(_ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    do { try process.run() } catch {
        fail("could not launch \(arguments[0]): \(error)")
    }
    process.waitUntilExit()
    return process.terminationStatus
}

func compileAndRun(sources: [String], label: String) {
    let fm = FileManager.default
    let workDir = fm.temporaryDirectory.appendingPathComponent("verify-session-identity-\(UUID().uuidString)")
    try! fm.createDirectory(at: workDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: workDir) }
    let binary = workDir.appendingPathComponent("verify")
    var args = ["swiftc"]
    args += sources.map { root.appendingPathComponent($0).path }
    args += ["-o", binary.path]
    if run(args) != 0 {
        fail("\(label) failed to compile")
    }
    if run([binary.path]) != 0 {
        fail("\(label) failed")
    }
}

let dashboard = [
    "OpenClawInstaller/Features/Dashboard/DashboardTypography.swift",
    "OpenClawInstaller/Features/Dashboard/DashboardView.swift",
    "OpenClawInstaller/Features/Dashboard/Sidebar/DashboardSidebar.swift",
    "OpenClawInstaller/Features/Chat/Views/ChatView.swift",
    "OpenClawInstaller/Features/Chat/Views/ComposerChrome.swift",
    "OpenClawInstaller/Features/Chat/Views/ChatBubbleViews.swift",
    "OpenClawInstaller/Features/Agents/Views/AgentSettingsPanel.swift",
    "OpenClawInstaller/Features/Dashboard/TerminalPanel.swift",
    "OpenClawInstaller/Features/Sessions/Views/SessionDetailsPanel.swift",
].map(read).joined(separator: "\n")
let search = read("OpenClawInstaller/Features/Sessions/Models/ChatSessionSearch.swift")
let navigation = read("OpenClawInstaller/Features/Sessions/State/SessionNavigationState.swift")
let persistence = read("OpenClawInstaller/Features/Sessions/SessionPersistence.swift")
let viewModel = read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")
let helpers = read("OpenClawInstaller/Features/Chat/ChatHelpers.swift")
let message = read("OpenClawInstaller/Features/Chat/Models/ChatMessage.swift")
let gateway = read("OpenClawInstaller/Core/Gateway/GatewayClient.swift")
let snapshot = read("OpenClawInstaller/Core/Gateway/GatewayChatRecoverySnapshot.swift")
let reconciliation = read("OpenClawInstaller/Features/Chat/State/ChatRunReconciliation.swift")
let generator = read("scripts/generate_unified_i18n_resources.py")

require(
    search.contains("enum ChatSessionListFilter") &&
        search.contains("case active") &&
        search.contains("case archived") &&
        search.contains("case all") &&
        search.contains("filter: ChatSessionListFilter = .active"),
    "ChatSessionSearch must own the Cursor-style Active/Archived/All filter"
)
require(
    navigation.contains("@Published var sessionListFilter: ChatSessionListFilter") &&
        navigation.contains("dashboard.sessionListFilter") &&
        persistence.contains("filter.includes(isArchived: meta.isArchived)") &&
        viewModel.contains("func unarchiveSession(_ sessionId: UUID)") &&
        viewModel.contains("func setSessionListFilter(_ filter: ChatSessionListFilter)"),
    "sidebar filter state must persist and drive the session mirror"
)
require(
    dashboard.contains("sessionListFilter: sessionState.sessionListFilter") &&
        dashboard.contains("unarchiveSession: viewModel.unarchiveSession") &&
        dashboard.contains("setSessionListFilter: viewModel.setSessionListFilter") &&
        dashboard.contains("sessionListFilterMenu") &&
        dashboard.contains("actions.unarchiveSession(meta.id)") &&
        dashboard.contains("I18n.t(filter.titleKey)") &&
        dashboard.contains("I18n.format(\"dashboard.session.row.messageCount\"") &&
        dashboard.contains("Text(Self.shortRelative(meta.updatedAt))") &&
        dashboard.contains("return \"\\(min)m\"") &&
        dashboard.contains("return \"\\(min / 60)h\""),
    "sidebar chrome must expose the filter, unarchive, relative time, and message count"
)
require(
    message.contains("let gatewayEntryId: String?") &&
        message.contains("let idempotencyKey: String?") &&
        message.contains("func withGatewayIdentity(") &&
        message.contains("enum ChatMessageGatewayIdentityBinder") &&
        helpers.contains("let userIdempotencyKey = UUID().uuidString") &&
        helpers.contains("idempotencyKey: userIdempotencyKey") &&
        helpers.contains("gatewayEntryId: existing?.gatewayEntryId") &&
        helpers.contains("idempotencyKey: existing?.idempotencyKey") &&
        gateway.contains("parseGatewayHistoryMessage") &&
        snapshot.contains("struct GatewayHistoryMessageSnapshot") &&
        reconciliation.contains("applyGatewayIdentityBackfill("),
    "ChatMessage must store and backfill gateway entryId / user idempotencyKey"
)
for key in [
    "dashboard.session.action.unarchive",
    "dashboard.session.filter.active",
    "dashboard.session.filter.archived",
    "dashboard.session.filter.all",
    "dashboard.session.filter.tooltip",
    "dashboard.session.empty.archived",
    "dashboard.session.row.messageCount",
] {
    require(generator.contains("\"\(key)\":"), "generator should define \(key)")
}

compileAndRun(
    sources: [
        "OpenClawInstaller/Core/Gateway/GatewayConnectionState.swift",
        "OpenClawInstaller/Core/Gateway/GatewayChatEvent.swift",
        "OpenClawInstaller/Features/Chat/Models/ChatActivityEvent.swift",
        "OpenClawInstaller/Features/Chat/Models/ChatMessage.swift",
        "Tests/ChatMessageGatewayIdentityTests.swift",
    ],
    label: "ChatMessage gateway identity tests"
)

print("PASS: session list filter and message identity")
