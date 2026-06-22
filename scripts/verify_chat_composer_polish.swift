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

func assertBefore(_ haystack: String, _ first: String, _ second: String, _ message: String) {
    guard
        let firstRange = haystack.range(of: first),
        let secondRange = haystack.range(of: second),
        firstRange.lowerBound < secondRange.lowerBound
    else {
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
let config = read("OpenClawInstaller/Views/Dashboard/ConfigTabView.swift")
let metrics = read("OpenClawInstaller/Views/Dashboard/OutputsSidebarLayoutMetrics.swift")
let layoutScript = read("scripts/verify_outputs_sidebar_layout.swift")
let rightOutputsTitlebarAccessory = slice(dashboard, from: "private struct RightOutputsTitlebarAccessory: View", to: "// MARK: - Sidebar")

assertContains(
    dashboard,
    #"String(localized: "No matching skills", bundle: LanguageManager.shared.localizedBundle)"#,
    "skills empty-state label must use the active language bundle"
)
assertContains(
    dashboard,
    #"String(localized: "No matching agents", bundle: LanguageManager.shared.localizedBundle)"#,
    "agents empty-state label must use the active language bundle"
)
assertContains(
    dashboard,
    #"String(localized: "Ask Anything", bundle: LanguageManager.shared.localizedBundle)"#,
    "composer placeholder must use the active language bundle"
)
assertContains(
    dashboard,
    #"String(localized: "New chat", bundle: LanguageManager.shared.localizedBundle)"#,
    "empty session fallback title must be localized"
)
assertContains(
    dashboard,
    #"String(localized: "Delete", bundle: LanguageManager.shared.localizedBundle)"#,
    "session-row delete affordance help must be localized"
)

assertBefore(
    dashboard,
    #"navRow(.tasksLogs, title: String(localized: "Automation""#,
    #"navRow(.market, title: String(localized: "AgentsMarket""#,
    "AgentsMarket row must appear directly after Automation"
)
assertNotContains(
    dashboard,
    #"navRow(.outputs"#,
    "left sidebar must not render an Outputs navigation row"
)
assertContains(
    dashboard,
    #".id("chatTop")"#,
    "timeline branch must keep chatTop anchor"
)
assertContains(
    dashboard,
    #".id("chatBottom")"#,
    "timeline branch must keep chatBottom anchor"
)
assertContains(
    dashboard,
    #"Color.clear"#,
    "scroll anchors should be invisible clear views"
)

assertContains(
    dashboard,
    #"RoundedRectangle(cornerRadius: 10, style: .continuous)"#,
    "chat bubbles must use tightened desktop-style 10pt corners"
)
assertContains(
    dashboard,
    #"private var bubbleBackgroundColor: SwiftUI.Color"#,
    "chat bubbles must centralize visible gray fills"
)
assertContains(
    dashboard,
    #"Color.gray.opacity(0.14)"#,
    "user chat bubbles must use visible gray fills"
)
assertContains(
    dashboard,
    #"Color(NSColor.controlBackgroundColor)"#,
    "assistant chat bubbles must use a system gray fill"
)
assertContains(
    dashboard,
    #"let codeBg = isDark ? "rgba(255,255,255,0.16)" : "rgba(0,0,0,0.10)""#,
    "code blocks must remain visibly distinct inside gray chat bubbles"
)
assertContains(
    dashboard,
    #"Button(action: { performCopy(message.content) })"#,
    "copy toolbar must remain available for gray bubble content"
)

assertContains(
    dashboard,
    #"overlayPreferenceValue(ComposerInputCardBoundsKey.self)"#,
    "composer selector panels must be an overlay"
)
assertContains(
    dashboard,
    #"overlayPreferenceValue(ComposerSelectorButtonBoundsKey.self)"#,
    "composer selector button must anchor overlay placement"
)
assertContains(
    dashboard,
    #"ComposerAgentModelPanel("#,
    "composer must use the custom agent/model panel"
)
assertContains(
    dashboard,
    #"composerSelectorShowsModels"#,
    "composer selector must support the adjacent model panel state"
)

assertContains(metrics, "collapsedWidth: CGFloat = 0", "closed Outputs sidebar must reserve zero width")
assertNotContains(metrics, "titlebarAccessoryWidthAdjustment", "titlebar accessory width must not be coupled to the Outputs split pane width")
assertContains(layoutScript, "narrow windows close Outputs without leaving a trailing strip", "Outputs layout verification must cover narrow-window closed strip behavior")
assertContains(dashboard, "DashboardWorkspaceSplitView(", "Outputs sidebar must use the AppKit right split container")
assertContains(dashboard, "private final class DashboardWorkspaceSplitController: NSSplitViewController", "Outputs sidebar split must be owned by AppKit")
assertContains(dashboard, "private let sidebarAnimationDuration: TimeInterval = 0.22", "right split and titlebar accessory must share one animation duration")
assertContains(dashboard, "splitView.animator().setPosition", "Outputs sidebar must animate the AppKit split divider")
assertContains(dashboard, "private var isAnimatingSidebar = false", "Outputs sidebar animation should be tracked inside the AppKit split controller")
assertContains(dashboard, "guard hasInstalledSplitItems, hasAppliedInitialLayout, !isAnimatingSidebar else { return }", "layout passes during Outputs animation must not snap the middle pane to the final width")
assertContains(dashboard, "sidebarItem.canCollapse = true", "Outputs sidebar split item must be allowed to fully collapse")
assertContains(dashboard, "sidebarItem.isCollapsed = true", "Outputs sidebar split item must fully collapse without leaving a trailing strip")
assertNotContains(dashboard, ".inspector(isPresented:", "Outputs sidebar must not use SwiftUI inspector in AppKit split mode")
assertNotContains(dashboard, "private var workspaceInspectorContent: some View", "Outputs sidebar must not keep a SwiftUI inspector wrapper")
assertNotContains(dashboard, "private var workspaceSplitColumn: some View", "Outputs sidebar must not use a manual trailing split column")
assertContains(dashboard, "private func workspaceSidebarPane(width: CGFloat) -> some View", "Outputs header and content must live in one AppKit split pane")
assertContains(dashboard, "WorkspaceOutputsPaneHeader(", "Outputs split pane must own the title/search/open header")
assertContains(dashboard, "ToolbarItem(placement: .navigation)", "conversation title must live in the window toolbar")
assertNotContains(dashboard, "ToolbarItem(placement: .primaryAction)", "Outputs toggle must not use the main toolbar primaryAction placement")
assertContains(dashboard, "DashboardTitlebarAccessoryInstaller(", "Outputs controls must be installed into the existing titlebar header")
assertContains(dashboard, "RightOutputsTitlebarAccessory(", "Outputs toggle must stay in the titlebar accessory")
assertNotContains(dashboard, #"Image(systemName: "tray.full.fill")"#, "right sidebar header must not show the removed blue tray icon")
assertContains(dashboard, ".animation(.spring(response: 0.36, dampingFraction: 0.88), value: workspaceSidebarExpanded)", "Outputs sidebar expansion must animate")
assertNotContains(dashboard, "private var chatTopChrome", "ChatView must not own the conversation header")
assertNotContains(dashboard, "private var conversationHeader: some View", "conversation header must not consume vertical space inside the chat content")
assertNotContains(dashboard, "WorkspaceInspectorHeader(", "right sidebar content must not create a second header row")
assertContains(dashboard, "private struct RightOutputsTitlebarAccessory: View", "right sidebar toggle must live in the existing titlebar header")
assertNotContains(rightOutputsTitlebarAccessory, #"Text("Outputs")"#, "right titlebar accessory must not resize as a second Outputs header")
assertContains(rightOutputsTitlebarAccessory, #"Image(systemName: "sidebar.right")"#, "right sidebar collapse must use the standard inspector sidebar icon")
assertContains(rightOutputsTitlebarAccessory, ".font(.system(size: 18, weight: .medium))", "right sidebar titlebar icon must visually match the system left-sidebar toolbar icon size")
assertContains(rightOutputsTitlebarAccessory, ".frame(width: 34, height: 34)", "right sidebar titlebar icon must use the same apparent button footprint as the left toolbar icon")
assertNotContains(rightOutputsTitlebarAccessory, #"Image(systemName: "xmark")"#, "right sidebar collapse must not use a generic close icon")
assertContains(dashboard, "private func shouldShowOutputItem", "right sidebar must filter the workspace to output artifacts")
assertContains(dashboard, "\"USER.md\", \"BOOTSTRAP.md\", \"HEARTBEAT.md\", \"TOOLS.md\"", "Outputs filtering must exclude user/context documents")

assertContains(config, "struct GatewaySettingsGroup", "Gateway settings group must exist")
assertContains(config, "Text(\"Gateway\")", "Gateway heading must be shown")
assertContains(config, "GatewayConfigSection(viewModel: viewModel, showsTitle: false)", "Gateway config title must not duplicate inside the grouped container")
assertContains(config, "ModelConfigSection(viewModel: viewModel)", "custom API provider controls must remain in the Gateway group")

assertContains(dashboard, "if isHovering {", "session rows must expose hover-only actions")
assertContains(dashboard, "Button(action: isDeleteConfirming ? onDeleteConfirm : onDeleteIntent)", "session-row delete action must be separate from row navigation")

print("Chat composer polish source verification passed")
