#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let dashboard = try read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let sidebar = try read("OpenClawInstaller/Features/Dashboard/Sidebar/DashboardSidebar.swift")
let typography = try read("OpenClawInstaller/Features/Dashboard/DashboardTypography.swift")
let chatView = try read("OpenClawInstaller/Features/Chat/Views/ChatView.swift")
let composer = try read("OpenClawInstaller/Features/Chat/Views/ComposerChrome.swift")
let bubbles = try read("OpenClawInstaller/Features/Chat/Views/ChatBubbleViews.swift")
let chatVM = try read("OpenClawInstaller/Features/Chat/ViewModels/ChatViewModel.swift")
let helpers = try read("OpenClawInstaller/Features/Chat/ChatHelpers.swift")
let dashboardVM = try read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")

try require(
    typography.contains("enum DashboardTypography") &&
        typography.contains("enum DashboardSidebarMetrics"),
    "typography tokens must live in DashboardTypography.swift"
)
try require(
    sidebar.contains("struct SidebarView: View") &&
        sidebar.contains("struct ChatSessionRow: View") &&
        !dashboard.contains("struct SidebarView: View"),
    "sidebar chrome must live in DashboardSidebar.swift"
)
try require(
    chatView.contains("struct ChatView: View") &&
        !dashboard.contains("struct ChatView: View"),
    "ChatView must live in Features/Chat/Views/ChatView.swift"
)
try require(
    composer.contains("struct ComposerModelSelector: View") &&
        bubbles.contains("struct ChatBubble: View") &&
        !dashboard.contains("struct ChatBubble: View"),
    "composer chrome and bubbles must not remain in DashboardView.swift"
)
try require(
    helpers.contains("extension ChatViewModel") &&
        helpers.contains("func sendChatMessage(_ text: String, attachments: [URL] = []) async") &&
        helpers.contains("func cancelChat(_ msgId: UUID)"),
    "the send/cancel/stream pipeline must be a ChatViewModel extension"
)
try require(
    chatVM.contains("final class ChatViewModel: ObservableObject") &&
        chatVM.contains("func attach(dashboard: DashboardViewModel)") &&
        dashboardVM.contains("chatViewModel.attach(dashboard: self)") &&
        dashboardVM.contains("await chatViewModel.sendChatMessage(text, attachments: attachments)"),
    "DashboardViewModel must attach itself and trampoline sendChatMessage into ChatViewModel"
)
let reconciliation = try read("OpenClawInstaller/Features/Chat/State/ChatRunReconciliation.swift")
let inFlight = try read("OpenClawInstaller/Features/Dashboard/InFlightRuns.swift")
try require(
    reconciliation.contains("extension ChatViewModel") &&
        inFlight.contains("extension ChatViewModel") &&
        dashboardVM.contains("chatViewModel.recoverInFlightRunsOnLaunch()") &&
        dashboardVM.contains("chatViewModel.scheduleChatRunReconciliation(messageId: messageId)"),
    "run reconciliation and crash-recovery persistence must live on ChatViewModel"
)
try require(
    dashboardVM.contains("chatViewModel.attach(dashboard: self)") &&
        dashboardVM.range(of: "chatViewModel.attach(dashboard: self)")!.lowerBound
        < dashboardVM.range(of: "recoverInFlightRunsOnLaunch()")!.lowerBound,
    "in-flight recovery must run after ChatViewModel is attached"
)
try require(
    chatVM.contains("let chatRunLifecycleCoordinator: ChatRunLifecycleCoordinator") &&
        chatVM.contains("let attachmentProcessor: AttachmentProcessor") &&
        !dashboardVM.contains("let chatRunLifecycleCoordinator = ChatRunLifecycleCoordinator()") &&
        !dashboardVM.contains("let attachmentProcessor = AttachmentProcessor()"),
    "run coordinator and attachment processor must be stored on ChatViewModel"
)
try require(
    chatVM.contains("injectedGateway = dashboard.gatewayClient") &&
        !chatVM.contains("var gatewayClient: GatewayClient { host.gatewayClient }"),
    "ChatViewModel must hold the shared GatewayClient injected at attach"
)
try require(
    chatVM.contains("func findMessage(byId msgId: UUID)") &&
        chatVM.contains("func clearTaskTracking(_ msgId: UUID)") &&
        chatVM.contains("taskState.removeRun(messageId: msgId)") &&
        chatVM.contains("chatRunLifecycleCoordinator.scheduleAutomaticBackground(") &&
        !chatVM.contains("host.findMessage") &&
        !chatVM.contains("host.clearTaskTracking") &&
        !chatVM.contains("host.recomputeIsSendingMessage") &&
        !chatVM.contains("host.scheduleAutomaticBackground") &&
        dashboardVM.contains("chatViewModel.clearTaskTracking(msgId)") &&
        dashboardVM.contains("chatViewModel.findMessage(byId: msgId)") &&
        dashboardVM.contains("chatViewModel.recomputeIsSendingMessage()") &&
        dashboardVM.contains("chatViewModel.scheduleAutomaticBackground(for: messageId)"),
    "chat-local run/message helpers must be implemented on ChatViewModel with Dashboard trampolines"
)
try require(
    chatVM.contains("func retryChatConnection(for messageId: UUID)") &&
        chatVM.contains("func handleGatewayConnectionState(_ state: GatewayConnectionState)") &&
        chatVM.contains("taskState.requestTransportRecoveryRetry()") &&
        dashboardVM.contains("chatViewModel.retryChatConnection(for: messageId)") &&
        dashboardVM.contains("chatViewModel.handleGatewayConnectionState(state)") &&
        dashboardVM.contains("gatewayClient.$connectionState") &&
        !dashboardVM.contains("private func handleGatewayConnectionState"),
    "transport retry and connection-state application live on ChatViewModel; Dashboard only observes"
)

print("PASS: dashboard module split")
