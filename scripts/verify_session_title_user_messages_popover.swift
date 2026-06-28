import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func assertContains(_ haystack: String, _ needle: String, _ message: String) {
    guard haystack.contains(needle) else {
        fatalError(message)
    }
}

func assertNotContains(_ haystack: String, _ needle: String, _ message: String) {
    guard !haystack.contains(needle) else {
        fatalError(message)
    }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let popover = read("OpenClawInstaller/Views/Dashboard/SessionTitleUserMessagesPopover.swift")
let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")

let titleToolbar = slice(
    dashboard,
    from: #".toolbar {"#,
    to: #".alert("Error""#
)
let chatView = slice(
    dashboard,
    from: "struct ChatView: View",
    to: "private struct ComposerAgentModelSelector: View"
)
let chatBubble = slice(
    dashboard,
    from: "struct ChatBubble: View",
    to: "// MARK: - Typewriter Text for Streaming"
)

assertContains(
    titleToolbar,
    "SessionTitleUserMessagesPopover(",
    "conversation title must use the locally owned hover popover component"
)
assertContains(
    titleToolbar,
    "messages: currentSessionUserMessages",
    "conversation title hover control must know whether user messages are available"
)
assertContains(
    titleToolbar,
    "onTapMessage: jumpToUserMessage",
    "conversation title popover should only call back to Dashboard when a user message is selected"
)
assertNotContains(
    titleToolbar,
    ".allowsHitTesting(false)",
    "conversation title must be interactive for hover popover behavior"
)

assertContains(
    dashboard,
    "private var currentSessionUserMessages: [ChatMessage]",
    "DashboardView must expose filtered user messages for the active session title popover"
)
assertContains(
    dashboard,
    ".filter { $0.role == .user",
    "title popover message source must filter to user messages only"
)

assertContains(
    project,
    "SessionTitleUserMessagesPopover.swift in Sources",
    "local title popover component must be compiled into the app target"
)

assertContains(
    popover,
    "struct SessionTitleUserMessagesPopover: View",
    "title user-message popover should live in its own focused component"
)
assertContains(
    popover,
    "@State private var isTitleHovering = false",
    "title hover state should be local to the title popover component"
)
assertContains(
    popover,
    "@State private var isPopoverHovering = false",
    "popover hover state should be local so moving from title into the panel keeps it open"
)
assertContains(
    popover,
    "@State private var isPopoverPresented = false",
    "popover presentation state should not live in DashboardView"
)
assertContains(
    popover,
    "@State private var popoverCloseTask: DispatchWorkItem?",
    "short close grace delay should be owned by the local title popover"
)
assertContains(
    popover,
    "RoundedRectangle(cornerRadius: 8, style: .continuous)",
    "conversation title must render inside a lightweight rounded rectangle"
)
assertContains(
    popover,
    "private struct SessionTitlePopoverHost<Label: View>: NSViewRepresentable",
    "toolbar title should use a narrow AppKit bridge to anchor a local popover"
)
assertContains(
    popover,
    "let popover = NSPopover()",
    "title user-message panel should be an AppKit popover anchored to the title view"
)
assertNotContains(
    popover,
    ".popover(",
    "title hover UI should not use SwiftUI popover state attached to DashboardView"
)
assertContains(
    popover,
    "popover.behavior = .transient",
    "title popover should close naturally when focus leaves it"
)
assertContains(
    popover,
    "schedulePresent(relativeTo: nsView, isPresented: $isPresented)",
    "title popover should not synchronously show from updateNSView"
)
assertContains(
    popover,
    "private var pendingPresentWork: DispatchWorkItem?",
    "title popover should cancel stale async show attempts when SwiftUI rebuilds the source view"
)
assertContains(
    popover,
    "DispatchQueue.main.async(execute: work)",
    "title popover should defer AppKit show until the next main run loop"
)
assertContains(
    popover,
    "guard isPresented.wrappedValue, !self.messages.isEmpty else { return }",
    "title popover should re-check binding state and messages before showing"
)
assertContains(
    popover,
    "guard sourceView.window != nil, !sourceView.bounds.isEmpty else",
    "title popover should only show from a source view attached to a window with stable bounds"
)
assertContains(
    popover,
    "isPresented.wrappedValue = false",
    "title popover should reset SwiftUI presentation state when the source view is unusable"
)
assertContains(
    popover,
    "popover.animates = false",
    "title popover should avoid toolbar hover animation churn"
)
assertContains(
    popover,
    "preferredEdge: .maxY",
    "title popover should be positioned by AppKit relative to the title view"
)
assertContains(
    popover,
    "if !isTitleHovering && !isPopoverHovering",
    "local close scheduling should keep the panel open while the pointer is over title or panel"
)
assertContains(
    popover,
    "onPopoverHoverChange(hovering)",
    "popover content should report hover locally instead of through DashboardView"
)
assertContains(
    popover,
    "ScrollView",
    "title popover content must be scrollable for long sessions"
)
assertContains(
    popover,
    "LazyVStack",
    "title popover content must render user messages as a list"
)
assertContains(
    popover,
    "ForEach(messages) { message in",
    "title popover must preserve message identity for future jump behavior"
)
assertContains(
    popover,
    "onTapMessage(message)",
    "title popover rows must expose a future message-selection hook"
)
assertContains(
    popover,
    ".frame(width: 360)",
    "title popover must use a stable readable width"
)
assertContains(
    popover,
    ".frame(maxHeight: 320)",
    "title popover must cap height so long sessions scroll"
)
assertContains(
    popover,
    "private struct SessionTitleLiquidGlassBackground: View",
    "title popover should use a named SwiftUI-native liquid-glass-inspired background"
)

let titlePopoverContent = slice(
    popover,
    from: "private struct SessionTitleUserMessagesPopoverContent: View",
    to: "private struct SessionTitleLiquidGlassBackground: View"
)
let liquidGlassBackground = slice(
    popover,
    from: "private struct SessionTitleLiquidGlassBackground: View",
    to: "private struct SessionTitleUserMessageRow: View"
)

assertContains(
    titlePopoverContent,
    ".background(SessionTitleLiquidGlassBackground(cornerRadius: 12))",
    "title popover content should apply the custom glass background as its outer surface"
)
assertNotContains(
    titlePopoverContent,
    ".background(.regularMaterial)",
    "title popover content should not use a plain regularMaterial background"
)
assertContains(
    liquidGlassBackground,
    ".fill(.ultraThinMaterial)",
    "liquid glass background should use a light native material base"
)
assertContains(
    liquidGlassBackground,
    "LinearGradient(",
    "liquid glass background should add a directional highlight layer"
)
assertContains(
    liquidGlassBackground,
    "RadialGradient(",
    "liquid glass background should add a localized lens highlight"
)
assertContains(
    liquidGlassBackground,
    ".strokeBorder(",
    "liquid glass background should draw subtle glass edges"
)
assertContains(
    liquidGlassBackground,
    ".shadow(color:",
    "liquid glass background should keep depth without adding a heavy opaque fill"
)
assertContains(
    popover,
    "private func schedulePopoverClose()",
    "title user-message popover must close via a short local grace delay"
)
assertContains(
    popover,
    "popoverCloseTask?.cancel()",
    "title user-message popover must cancel pending closes when pointer enters title or panel"
)

assertNotContains(
    dashboard,
    "SessionTitleFrameReporter",
    "DashboardView should not measure the toolbar title frame for a root overlay"
)
assertNotContains(
    dashboard,
    "sessionTitleUserMessagesFlyout",
    "DashboardView should not render the title user-message panel as a root overlay"
)
assertNotContains(
    dashboard,
    "updateSessionTitleHover",
    "DashboardView should not own title hover state"
)
assertNotContains(
    dashboard,
    "sessionTitleFlyoutCloseTask",
    "DashboardView should not own title popover close scheduling"
)
assertNotContains(
    dashboard,
    "isSessionTitleHovering",
    "DashboardView should not change root state for title hover"
)
assertNotContains(
    dashboard,
    "sessionTitleFrame",
    "DashboardView should not store title geometry for hover popover placement"
)

assertContains(
    chatView,
    "@State private var highlightedMessageId: UUID?",
    "ChatView must track the message selected from the title popover"
)
assertContains(
    chatView,
    "@State private var highlightedMessageFlashOn = false",
    "ChatView must keep a flashing phase for selected-message emphasis"
)
assertContains(
    chatView,
    "private func jumpToUserMessage(_ messageId: UUID)",
    "ChatView must expose a jump handler for title popover selections"
)
assertContains(
    chatView,
    "chatScrollProxy?.scrollTo(messageId, anchor: .center)",
    "jump handler must scroll the chat timeline to the selected user message"
)
assertContains(
    chatView,
    "triggerUserMessageHighlight(messageId)",
    "jump handler must start selected user message highlighting after scroll"
)
assertContains(
    chatView,
    ".onChange(of: requestedUserMessageJumpId)",
    "ChatView must respond to title popover jump requests from DashboardView"
)
assertContains(
    chatView,
    "for step in 0..<6",
    "selected user message should flash a few times after jumping"
)
assertContains(
    chatView,
    "isJumpHighlighted: highlightedMessageId == message.id && highlightedMessageFlashOn",
    "ChatBubble must receive the transient selected-message highlight state"
)

assertContains(
    chatBubble,
    "let isJumpHighlighted: Bool",
    "ChatBubble must accept an explicit jump-highlight flag"
)
assertContains(
    chatBubble,
    "Color.gray.opacity(0.42)",
    "jump highlight must use a deeper gray background"
)
assertContains(
    chatBubble,
    "isJumpHighlighted ? jumpHighlightBackgroundColor : bubbleBackgroundColor",
    "user bubble background must switch to the deep gray flash color while highlighted"
)

print("Session title user messages popover source verification passed")
