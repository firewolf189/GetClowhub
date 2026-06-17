#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboardURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let viewModelURL = root.appendingPathComponent("OpenClawInstaller/ViewModels/DashboardViewModel.swift")

let dashboard = try String(contentsOf: dashboardURL, encoding: .utf8)
let viewModel = try String(contentsOf: viewModelURL, encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

func slice(_ source: String, from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        return ""
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

let agentRow = slice(
    dashboard,
    from: "private struct AgentListRow: View",
    to: "private struct MarketplaceAgentRow: View"
)

require(!agentRow.isEmpty, "AgentListRow source block should be discoverable")
require(agentRow.contains("Image(systemName: \"chevron.right\")"), "agent row should use one chevron.right icon")
require(agentRow.contains(".rotationEffect(.degrees(isExpanded ? 90 : 0))"), "agent chevron should rotate down when expanded")
require(!agentRow.contains("isExpanded ? \"chevron.down\" : \"chevron.right\""), "agent row should not swap chevron.down/chevron.right")

require(dashboard.contains("struct PendingComposerMessage: Identifiable, Equatable"), "chat view should define a pending composer message model")
require(dashboard.contains("@State private var pendingComposerMessagesBySession"), "pending composer queue should be session-scoped")
require(dashboard.contains("enqueuePendingComposerMessage(text: text, attachments: files)"), "send while streaming should enqueue the composer text")
require(dashboard.contains("deletePendingComposerMessage"), "queued composer messages should support delete")
require(dashboard.contains("editPendingComposerMessage"), "queued composer messages should support edit")
require(dashboard.contains("drainPendingComposerQueueIfPossible()"), "queued messages should drain after the active response completes")
require(dashboard.contains("return hasText || hasFiles"), "send button should remain enabled while the model is streaming")
require(dashboard.contains("private var isInputLocked: Bool {\n        false\n    }"), "composer input should not lock during streaming")

require(dashboard.contains("InlineUserMessageEditor"), "user message edit-resend should render an inline editor")
require(dashboard.contains("onConfirmEditResend"), "chat bubble should confirm edit-resend before rewinding")
require(dashboard.contains("inlineMessageEditorTextView"), "inline editor should be identifiable so global composer shortcuts do not hijack Return")
require(viewModel.contains("replacementText: String? = nil"), "rewindToMessage should accept confirmed replacement text")
require(viewModel.contains("await self.sendChatMessage(editedText, attachments: message.attachments)"), "confirmed edit-resend should send edited text after truncation")

print("PASS: chat queue, inline edit-resend, and agent chevron source contracts verified")
