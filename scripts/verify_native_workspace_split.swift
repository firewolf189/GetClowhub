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
let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")
let dashboardView = slice(dashboard, from: "struct DashboardView: View", to: "// MARK: - Sidebar")
let detailContentView = slice(dashboard, from: "struct DetailContentView: View", to: "// MARK: - Collab Drag Handle")
let chatView = slice(dashboard, from: "struct ChatView: View", to: "// MARK: - Chat Welcome View")
let dashboardWorkspaceSplitController = slice(
    dashboard,
    from: "private final class DashboardWorkspaceSplitController: NSViewController",
    to: "private let rightOutputsTitlebarAccessoryID"
)

assertContains(
    dashboardView,
    "} detail: {\n            DashboardWorkspaceSplitView(",
    "root DashboardView should still use the left system NavigationSplitView sidebar and place an AppKit split in detail"
)
assertContains(
    dashboardView,
    "DashboardWorkspaceSplitView(",
    "right Outputs column should be owned by an AppKit split container"
)
assertContains(
    dashboardView,
    "workspaceSidebarPane(width:",
    "DashboardView should pass the unified Outputs pane into the AppKit split container"
)
assertContains(
    dashboardView,
    "@State private var isWorkspaceSidebarClosing = false",
    "DashboardView should keep Outputs content mounted while a close animation is in progress"
)
assertContains(
    dashboardView,
    "@State private var workspaceSidebarCollapseRequestID = 0",
    "DashboardView should request an AppKit collapse animation before committing collapsed state"
)
assertContains(
    dashboardView,
    "@State private var isWorkspaceSidebarOpening = false",
    "DashboardView should track opening animation before committing expanded state"
)
assertContains(
    dashboardView,
    "@State private var workspaceSidebarExpandRequestID = 0",
    "DashboardView should request an AppKit expand animation before committing expanded state"
)
assertContains(
    dashboardView,
    "@State private var pendingWorkspaceSidebarCloseReset = false",
    "DashboardView should defer destructive Outputs sidebar reset until the close animation finishes"
)
assertContains(
    dashboardView,
    "collapseRequestID: workspaceSidebarCollapseRequestID",
    "right Outputs split should receive direct collapse requests from the titlebar button"
)
assertContains(
    dashboardView,
    "expandRequestID: workspaceSidebarExpandRequestID",
    "right Outputs split should receive direct expand requests from the titlebar button"
)
assertContains(
    dashboardView,
    "onSidebarExpandFinished: completeWorkspaceSidebarOpen",
    "right Outputs split should notify DashboardView after the open animation finishes"
)
assertContains(
    dashboardView,
    "onSidebarCollapseFinished: completeWorkspaceSidebarClose",
    "right Outputs split should notify DashboardView after the close animation finishes"
)
assertNotContains(
    dashboardView,
    ".inspector(isPresented:",
    "right Outputs column should not use SwiftUI inspector when using the AppKit split approach"
)
assertNotContains(
    dashboardView,
    ".inspectorColumnWidth(",
    "right Outputs sizing should be handled by the AppKit split controller"
)
assertNotContains(
    dashboardView,
    "} content: {",
    "root DashboardView should not keep a three-column NavigationSplitView content column for Outputs"
)
assertNotContains(
    dashboardView,
    "private var workspaceSplitColumn: some View",
    "Outputs should no longer be rendered as a manual trailing NavigationSplitView column"
)
assertContains(
    dashboard,
    "private struct DashboardWorkspaceSplitView<Content: View, Sidebar: View>: NSViewControllerRepresentable",
    "right Outputs column should be bridged through an AppKit inspector shell"
)
assertContains(
    dashboard,
    "private final class DashboardWorkspaceSplitController: NSViewController",
    "right Outputs column should be managed by a constraint-driven AppKit controller"
)
assertContains(
    dashboard,
    "private let sidebarAnimationDuration: TimeInterval = 0.30",
    "right split and titlebar accessory should share one smoother animation duration"
)
assertContains(
    dashboard,
    "sidebarWidthConstraint?.animator().constant",
    "AppKit inspector shell should animate the sidebar width constraint instead of jumping visible state"
)
assertContains(
    dashboard,
    "private var isAnimatingSidebar = false",
    "right AppKit inspector controller should track sidebar animation state"
)
assertContains(
    dashboard,
    "guard hasInstalledLayout, hasAppliedInitialLayout, !isAnimatingSidebar else { return }",
    "layout passes during sidebar animation should not force the inspector to its final width"
)
assertContains(
    dashboard,
    "isAnimatingSidebar = true",
    "right AppKit inspector controller should mark animated transitions before changing width"
)
assertContains(
    dashboard,
    "self.isAnimatingSidebar = false",
    "right AppKit inspector controller should clear animation state after width animation completes"
)
assertContains(
    dashboardWorkspaceSplitController,
    "private var sidebarAnimationGeneration = 0",
    "right AppKit inspector controller should invalidate stale animation completions"
)
assertContains(
    dashboardWorkspaceSplitController,
    "private var onSidebarCollapseFinished: (() -> Void)?",
    "right AppKit inspector controller should own a collapse completion callback"
)
assertContains(
    dashboardWorkspaceSplitController,
    "private var onSidebarExpandFinished: (() -> Void)?",
    "right AppKit inspector controller should own an expand completion callback"
)
assertContains(
    dashboardWorkspaceSplitController,
    "private var lastExpandRequestID = 0",
    "right AppKit inspector controller should track the latest direct expand request"
)
assertContains(
    dashboardWorkspaceSplitController,
    "private var lastCollapseRequestID = 0",
    "right AppKit inspector controller should track the latest direct collapse request"
)
assertContains(
    dashboardWorkspaceSplitController,
    "let shouldCollapseFromRequest = collapseRequestID != lastCollapseRequestID",
    "right sidebar should start closing from a direct AppKit request before SwiftUI commits collapsed state"
)
assertContains(
    dashboardWorkspaceSplitController,
    "let shouldExpandFromRequest = expandRequestID != lastExpandRequestID",
    "right sidebar should start opening from a direct AppKit request before SwiftUI commits expanded state"
)
assertContains(
    dashboardWorkspaceSplitController,
    "let isCollapsingSidebar = (shouldAnimate && currentIsSidebarExpanded && !isSidebarExpanded && hasAppliedInitialLayout) || (shouldCollapseFromRequest && hasAppliedInitialLayout)",
    "right sidebar collapse should be detected before replacing the SwiftUI sidebar root"
)
assertContains(
    dashboardWorkspaceSplitController,
    "let shouldDeferSidebarRootUpdate = isCollapsingSidebar || (isAnimatingSidebar && !currentIsSidebarExpanded)",
    "right sidebar should keep its existing content during follow-up updates while closing"
)
assertContains(
    dashboardWorkspaceSplitController,
    "if !shouldDeferSidebarRootUpdate {\n            sidebarHost.rootView = sidebar\n        }",
    "right sidebar should keep its existing content mounted while closing"
)
assertContains(
    dashboardWorkspaceSplitController,
    "self.sidebarHost.rootView = sidebar\n                self.onSidebarCollapseFinished?()",
    "right sidebar should update its root and clear state only after the close animation finishes"
)
assertContains(
    dashboardWorkspaceSplitController,
    "if isAnimatingSidebar && !currentIsSidebarExpanded && isSidebarExpanded {\n            return\n        }",
    "right sidebar should not reverse a requested close if SwiftUI still reports the business state as expanded"
)
assertContains(
    dashboardWorkspaceSplitController,
    "if isAnimatingSidebar && currentIsSidebarExpanded && !isSidebarExpanded {\n            return\n        }",
    "right sidebar should not reverse a requested open if SwiftUI still reports the business state as collapsed"
)
assertContains(
    dashboardWorkspaceSplitController,
    "self.sidebarHost.rootView = sidebar\n                    self.onSidebarExpandFinished?()",
    "right sidebar should commit expanded state only after the open animation finishes"
)
assertContains(
    dashboardWorkspaceSplitController,
    "let animationID = sidebarAnimationGeneration",
    "right AppKit inspector controller should tag each sidebar animation"
)
assertContains(
    dashboardWorkspaceSplitController,
    "guard self.sidebarAnimationGeneration == animationID else { return }",
    "stale sidebar animation completions should not collapse or hide the current sidebar state"
)
assertContains(
    dashboardWorkspaceSplitController,
    "view.layoutSubtreeIfNeeded()",
    "right AppKit inspector controller should flush layout before animating the width constraint"
)
assertContains(
    dashboardWorkspaceSplitController,
    "animateSidebarWidth(to: targetWidth)",
    "right AppKit inspector controller should animate width changes while already expanded"
)
assertContains(
    dashboardWorkspaceSplitController,
    "private let sidebarRail = NSView()",
    "right sidebar should use an AppKit rail like an Xcode inspector"
)
assertContains(
    dashboardWorkspaceSplitController,
    "private let sidebarSeparator = NSBox()",
    "right sidebar rail should own a native separator line"
)
assertContains(
    dashboardWorkspaceSplitController,
    "private let sidebarClipView = NSView()",
    "right sidebar rail should own a dedicated clipping view for SwiftUI content"
)
assertContains(
    dashboardWorkspaceSplitController,
    "sidebarRail.clipsToBounds = true",
    "right sidebar rail should clip separator and content during width animation"
)
assertContains(
    dashboardWorkspaceSplitController,
    "sidebarClipView.clipsToBounds = true",
    "right sidebar clip view should prevent SwiftUI content from flashing outside the rail"
)
assertContains(
    dashboardWorkspaceSplitController,
    "sidebarRail.addSubview(sidebarSeparator)",
    "right sidebar separator should be installed inside the rail"
)
assertContains(
    dashboardWorkspaceSplitController,
    "sidebarRail.addSubview(sidebarClipView)",
    "right sidebar clip view should be installed inside the rail"
)
assertContains(
    dashboardWorkspaceSplitController,
    "sidebarClipView.addSubview(sidebarHost.view)",
    "right sidebar SwiftUI host should live inside the clipping view"
)
assertContains(
    dashboardWorkspaceSplitController,
    "sidebarRail.widthAnchor.constraint(equalToConstant: 0)",
    "right sidebar width animation should target the whole inspector rail"
)
assertContains(
    dashboardWorkspaceSplitController,
    "contentHost.view.trailingAnchor.constraint(equalTo: sidebarRail.leadingAnchor)",
    "middle content and right inspector rail should share the same moving boundary"
)
assertContains(
    dashboardWorkspaceSplitController,
    "sidebarRail.trailingAnchor.constraint(equalTo: view.trailingAnchor)",
    "right inspector rail should stay pinned to the window edge"
)
assertContains(
    dashboardWorkspaceSplitController,
    "sidebarSeparator.leadingAnchor.constraint(equalTo: sidebarRail.leadingAnchor)",
    "right inspector separator should sit on the moving boundary"
)
assertContains(
    dashboardWorkspaceSplitController,
    "sidebarClipView.leadingAnchor.constraint(equalTo: sidebarSeparator.trailingAnchor)",
    "right inspector content should start after the separator"
)
assertContains(
    dashboardWorkspaceSplitController,
    "sidebarHost.view.leadingAnchor.constraint(equalTo: sidebarClipView.leadingAnchor)",
    "right sidebar SwiftUI host should be anchored inside the clip view"
)
assertContains(
    dashboardWorkspaceSplitController,
    "sidebarContentWidthConstraint?.constant",
    "right sidebar SwiftUI host width should be pre-sized separately from the animated rail"
)
assertContains(
    dashboardWorkspaceSplitController,
    "separatorWidthConstraint.priority = .fittingSizeCompression",
    "right inspector separator width should yield when the rail animates down to zero width"
)
assertNotContains(
    dashboardWorkspaceSplitController,
    "sidebarRail.isHidden",
    "right inspector rail should stay mounted at zero width so width animation remains smooth"
)
assertNotContains(
    dashboardWorkspaceSplitController,
    "sidebarHost.view.isHidden",
    "right sidebar should not toggle the SwiftUI host visibility during titlebar button animation"
)
assertNotContains(
    dashboardWorkspaceSplitController,
    "sidebarContainer",
    "right sidebar should use the fuller rail/clip/separator structure rather than the simpler B container"
)
assertNotContains(
    dashboardWorkspaceSplitController,
    "NSSplitViewItem",
    "right inspector shell should not use resident NSSplitViewItem state"
)
assertNotContains(
    dashboardWorkspaceSplitController,
    "splitView.setPosition",
    "right inspector shell should not jump the NSSplitView divider position"
)
assertNotContains(
    dashboardWorkspaceSplitController,
    "splitView.animator().setPosition",
    "right inspector shell should animate one width constraint instead of the split divider"
)
assertNotContains(
    dashboardWorkspaceSplitController,
    "canCollapse",
    "right inspector shell should not rely on split-item collapse behavior"
)
assertNotContains(
    dashboardWorkspaceSplitController,
    "prepareSidebarForExpansion",
    "right AppKit inspector should not relayout in a separate pre-expansion phase"
)
assertNotContains(
    dashboardWorkspaceSplitController,
    ".isCollapsed",
    "right AppKit inspector should use zero width instead of collapsed state for opening and closing"
)
assertContains(
    dashboard,
    "widthConstraint?.animator().constant",
    "right titlebar accessory bridge should update its AppKit width constraint through animation"
)
assertContains(
    dashboard,
    "height: CGFloat = 44",
    "right titlebar accessory should occupy the full toolbar row height"
)
assertContains(
    dashboardView,
    "ToolbarItem(placement: .navigation)",
    "conversation title should move into the window toolbar near the system left-sidebar button"
)
assertNotContains(
    dashboardView,
    ".animation(.spring(response: 0.36, dampingFraction: 0.88), value: workspaceSidebarExpanded)",
    "right sidebar width should not also be animated by the SwiftUI root animation"
)
assertNotContains(
    dashboardView,
    ".animation(.spring(response: 0.36, dampingFraction: 0.88), value: workspaceEditingFilePath)",
    "right sidebar editor-width changes should be animated by the AppKit split controller only"
)
let revealWorkspaceSidebar = slice(dashboardView, from: "private func revealWorkspaceSidebar()", to: "    private func hideWorkspaceSidebar")
let hideWorkspaceSidebar = slice(dashboardView, from: "private func hideWorkspaceSidebar", to: "    private func completeWorkspaceSidebarClose")
let completeWorkspaceSidebarOpen = slice(dashboardView, from: "private func completeWorkspaceSidebarOpen()", to: "    private func completeWorkspaceSidebarClose")
let completeWorkspaceSidebarClose = slice(dashboardView, from: "private func completeWorkspaceSidebarClose()", to: "    private func clearWorkspaceSidebarTransientState")
let isWorkspaceSidebarExpanded = slice(dashboardView, from: "private var isWorkspaceSidebarExpanded: Bool", to: "    private var shouldRetainWorkspaceSidebarContent")
assertNotContains(
    isWorkspaceSidebarExpanded,
    "!isWorkspaceSidebarClosing",
    "right sidebar close should not commit the visual expanded state before the AppKit collapse animation starts"
)
assertContains(
    dashboardView,
    "workspaceSidebarExpanded || workspaceEditingFilePath != nil || isWorkspaceSidebarOpening || isWorkspaceSidebarClosing",
    "right sidebar content should stay mounted while opening or closing animations run"
)
assertNotContains(
    revealWorkspaceSidebar,
    "withAnimation(",
    "right sidebar reveal should not wrap the AppKit split transition in a second SwiftUI animation"
)
assertNotContains(
    hideWorkspaceSidebar,
    "withAnimation(",
    "right sidebar hide should not wrap the AppKit split transition in a second SwiftUI animation"
)
assertContains(
    revealWorkspaceSidebar,
    "isWorkspaceSidebarOpening = true",
    "right sidebar reveal should start a visual open before committing expanded state"
)
assertContains(
    revealWorkspaceSidebar,
    "workspaceSidebarExpandRequestID += 1",
    "right sidebar reveal should request AppKit expand without first committing expanded state"
)
assertNotContains(
    revealWorkspaceSidebar,
    "workspaceSidebarExpanded = true",
    "right sidebar reveal should not commit expanded state before the open animation finishes"
)
assertContains(
    completeWorkspaceSidebarOpen,
    "workspaceSidebarExpanded = true",
    "right sidebar open completion should commit expanded state after animation"
)
assertContains(
    completeWorkspaceSidebarOpen,
    "isWorkspaceSidebarOpening = false",
    "right sidebar open completion should clear opening animation state"
)
assertContains(
    hideWorkspaceSidebar,
    "isWorkspaceSidebarClosing = true",
    "right sidebar hide should start a visual close before clearing sidebar content"
)
assertContains(
    hideWorkspaceSidebar,
    "workspaceSidebarCollapseRequestID += 1",
    "right sidebar hide should request AppKit collapse without first committing collapsed state"
)
assertNotContains(
    hideWorkspaceSidebar,
    "workspaceSidebarExpanded = false",
    "right sidebar hide should not commit collapsed state before the close animation finishes"
)
assertNotContains(
    hideWorkspaceSidebar,
    "workspaceEditingFilePath = nil",
    "right sidebar hide should not clear editor content before the close animation finishes"
)
assertContains(
    completeWorkspaceSidebarClose,
    "workspaceSidebarExpanded = false",
    "right sidebar close completion should commit the collapsed state after animation"
)
assertContains(
    completeWorkspaceSidebarClose,
    "clearWorkspaceSidebarTransientState()",
    "right sidebar close completion should clear editor/search state after animation"
)
assertNotContains(
    dashboardView,
    "ToolbarItem(placement: .primaryAction)",
    "right Outputs controls should not use the main toolbar primaryAction placement"
)
assertContains(
    dashboardView,
    "DashboardTitlebarAccessoryInstaller(",
    "right Outputs controls should be installed into the window titlebar"
)
assertContains(
    dashboardView,
    "RightOutputsTitlebarAccessory(",
    "right Outputs toggle should be rendered by a titlebar accessory"
)
assertContains(
    dashboardView,
    "isTerminalOpen: terminalOpen",
    "right titlebar accessory should receive terminal open state"
)
assertContains(
    dashboardView,
    "toggleTerminal:",
    "right titlebar accessory should receive a terminal toggle action"
)
assertContains(
    dashboard,
    "private struct DashboardTitlebarAccessoryInstaller",
    "DashboardView should keep a narrow AppKit bridge for titlebar-only Outputs controls"
)
assertContains(
    dashboard,
    "window.titlebarAccessoryViewControllers",
    "titlebar accessory bridge should install into the existing window header"
)
assertContains(
    dashboard,
    "private struct RightOutputsTitlebarAccessory",
    "custom Outputs titlebar toggle should live outside the inspector content"
)
assertNotContains(
    dashboard,
    "titlebarAccessoryWidthAdjustment",
    "right titlebar accessory must not share the Outputs pane width metric"
)
assertContains(
    dashboard,
    "private var rightTitlebarAccessoryWidth: CGFloat {\n        guard isChatTabActive else { return 0 }\n        return 78\n    }",
    "right titlebar accessory should stay as a fixed two-button toolbar width"
)
assertContains(
    detailContentView,
    "let workspaceSidebarController: WorkspaceSidebarController",
    "DetailContentView should receive workspace control state from the root shell"
)
assertContains(
    detailContentView,
    ".environment(\\.workspaceSidebarController, workspaceSidebarController)",
    "ChatView should continue receiving the workspace sidebar controller"
)
let timelineChatSurface = slice(chatView, from: "private var timelineChatSurface: some View", to: "    private var chatScrollIndicator")
let chatContent = slice(chatView, from: "private var chatContent: some View", to: "    var body: some View")
assertContains(
    chatContent,
    "if terminalOpen {",
    "bottom terminal open condition should be mounted at the ChatView root"
)
assertContains(
    chatContent,
    "terminalPanel",
    "bottom terminal panel should be mounted at the ChatView root so it appears for empty and populated chats"
)
assertNotContains(
    timelineChatSurface,
    "if terminalOpen {",
    "bottom terminal panel should not be limited to the populated-message timeline surface"
)
assertNotContains(
    detailContentView,
    "workspaceSidebarColumn(width:",
    "DetailContentView should not embed the workspace sidebar inside the main content HStack"
)
assertNotContains(
    detailContentView,
    "private var conversationHeader: some View",
    "conversation header should not occupy vertical space inside the main content pane"
)

let workspaceFilePanel = slice(dashboard, from: "private struct WorkspaceFilePanel: View", to: "    private var outputsEmptyState: some View")
assertNotContains(
    workspaceFilePanel,
    "Text(\"Outputs\")",
    "WorkspaceFilePanel should not create its own Outputs header; the title belongs to the existing window header"
)
assertNotContains(
    workspaceFilePanel,
    "Image(systemName: \"tray.full.fill\")",
    "WorkspaceFilePanel should not duplicate the Outputs titlebar icon inside the content column"
)
assertContains(
    dashboard,
    "private func workspaceSidebarPane(width: CGFloat) -> some View",
    "right Outputs header and content should live in one AppKit split pane"
)
let workspaceSidebarPane = slice(dashboard, from: "private func workspaceSidebarPane(width: CGFloat) -> some View", to: "    private func workspaceExpandedSidebar")
assertContains(
    workspaceSidebarPane,
    "WorkspaceOutputsPaneHeader(",
    "right split pane should own the Outputs header row"
)
assertContains(
    workspaceSidebarPane,
    "workspaceExpandedSidebar(width: width)",
    "right split pane should own the Outputs file content"
)

assertNotContains(
    dashboard,
    "private var workspaceInspectorContent: some View",
    "AppKit split mode should not keep a SwiftUI inspector content wrapper"
)
assertNotContains(
    dashboard,
    "WorkspaceInspectorHeader(",
    "right sidebar content should not create its own header row"
)

let rightOutputsTitlebarAccessory = slice(dashboard, from: "private struct RightOutputsTitlebarAccessory: View", to: "// MARK: - Sidebar")
assertNotContains(
    rightOutputsTitlebarAccessory,
    "Text(\"Outputs\")",
    "window titlebar accessory should stay as a fixed toggle, not a second resizing Outputs header"
)
assertContains(
    rightOutputsTitlebarAccessory,
    "let isTerminalOpen: Bool",
    "right titlebar accessory should know when the bottom terminal is open"
)
assertContains(
    rightOutputsTitlebarAccessory,
    "let toggleTerminal: () -> Void",
    "right titlebar accessory should expose a terminal toggle action"
)
assertContains(
    rightOutputsTitlebarAccessory,
    "Image(systemName: \"terminal\")",
    "right titlebar accessory should include a terminal button"
)
assertBefore(
    rightOutputsTitlebarAccessory,
    "Image(systemName: \"terminal\")",
    "Image(systemName: \"sidebar.right\")",
    "terminal button should sit to the left of the right sidebar button"
)
assertContains(
    rightOutputsTitlebarAccessory,
    "Image(systemName: \"sidebar.right\")",
    "Outputs titlebar accessory should use the standard right-sidebar icon"
)
assertContains(
    rightOutputsTitlebarAccessory,
    ".font(.system(size: 18, weight: .medium))",
    "right sidebar titlebar icon should visually match the system left-sidebar toolbar icon size"
)
assertContains(
    rightOutputsTitlebarAccessory,
    ".frame(width: 34, height: 34)",
    "right sidebar titlebar icon should use the same apparent button footprint as the left toolbar icon"
)
assertNotContains(
    rightOutputsTitlebarAccessory,
    "Image(systemName: \"xmark\")",
    "Outputs titlebar accessory should not use a generic close icon for sidebar collapse"
)

assertContains(
    project,
    "MACOSX_DEPLOYMENT_TARGET = 14.0;",
    "macOS deployment target should stay at the current project baseline"
)
assertNotContains(
    project,
    "MACOSX_DEPLOYMENT_TARGET = 13.0;",
    "macOS 13 deployment target should be removed when using SwiftUI inspector"
)

print("Native workspace split source verification passed")
