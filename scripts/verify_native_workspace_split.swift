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

func sliceFrom(_ haystack: String, from start: String) -> String {
    guard let startRange = haystack.range(of: start) else {
        fatalError("Could not slice source from \(start)")
    }
    return String(haystack[startRange.lowerBound...])
}

let dashboard = read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let rightInspectorSplit = read("OpenClawInstaller/Features/Workspace/Views/Inspector/RightInspectorSplitView.swift")
let workspaceInspector = read("OpenClawInstaller/Features/Workspace/Views/Inspector/WorkspaceInspectorPane.swift")
let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")
let dashboardView = slice(dashboard, from: "struct DashboardView: View", to: "// MARK: - Sidebar")
let rightInspectorContentUpdateID = slice(
    dashboard,
    from: "private var rightInspectorContentUpdateID: AnyHashable",
    to: "private var selectedWorkspacePath"
)
let detailContentView = slice(dashboard, from: "struct DetailContentView: View", to: "// MARK: - Collab Drag Handle")
let chatView = slice(dashboard, from: "struct ChatView: View", to: "// MARK: - Chat Welcome View")
let rightInspectorSplitController = sliceFrom(
    rightInspectorSplit,
    from: "private final class RightInspectorSplitController: NSViewController"
)

assertContains(
    dashboardView,
    "} detail: {\n            RightInspectorSplitView(",
    "root DashboardView should still use the left system NavigationSplitView sidebar and place an AppKit split in detail"
)
assertContains(
    dashboardView,
    "RightInspectorSplitView(",
    "right Outputs column should be owned by an AppKit split container"
)
assertContains(
    dashboardView,
    "contentUpdateID: rightInspectorContentUpdateID",
    "right inspector sidebar toggles should not force the middle chat root to refresh"
)
assertContains(
    rightInspectorSplit,
    "struct RightInspectorSidebarWidthCoordinator",
    "right inspector should expose an AppKit width coordinator for local sidebar-detail animations"
)
assertContains(
    rightInspectorSplit,
    "rightInspectorSidebarWidthCoordinator",
    "right inspector should inject the width coordinator through the SwiftUI environment"
)
assertContains(
    workspaceInspector,
    "private struct WorkspaceInspectorContentSplit<Primary: View, Secondary: View>",
    "workspace inspector should keep the Outputs primary column in a stable local content split"
)
assertNotContains(
    rightInspectorSplit,
    "struct NestedWorkspaceSplitView<Primary: View, Secondary: View>",
    "Outputs content should not be hosted by the old nested AppKit split that can collapse the primary column"
)
assertNotContains(
    rightInspectorSplit,
    "private final class NestedWorkspaceSplitController: NSViewController",
    "the secondary project column should no longer depend on a second AppKit controller"
)
assertContains(
    dashboard,
    "private struct RightInspectorContentUpdateID: Hashable",
    "right inspector content identity should be an explicit value separate from layout state"
)
for forbiddenState in [
    "workspaceSidebarExpanded",
    "isWorkspaceSidebarOpening",
    "isWorkspaceSidebarClosing",
    "workspaceSidebarExpandRequestID",
    "workspaceSidebarCollapseRequestID",
    "workspaceDetailMode"
] {
    assertNotContains(
        rightInspectorContentUpdateID,
        forbiddenState,
        "right inspector content identity should not include sidebar layout state: \(forbiddenState)"
    )
}
assertNotContains(
    dashboardView,
    "@State private var workspaceDetailMode",
    "secondary project sidebar mode should be owned by the workspace inspector pane, not DashboardView"
)
assertNotContains(
    dashboardView,
    "@State private var workspaceSearchText",
    "secondary project sidebar search should be owned by the workspace inspector pane, not DashboardView"
)
assertNotContains(
    dashboardView,
    "@State private var workspaceEditingFilePath",
    "workspace file preview selection should be owned by the workspace inspector pane, not DashboardView"
)
assertContains(
    dashboardView,
    "workspaceSidebarPane(width:",
    "DashboardView should pass the unified Outputs pane into the AppKit split container"
)
assertContains(
    dashboardView,
    "private var activeWorkspaceRoot: WorkspaceSidebarRoot",
    "right workspace file tree should resolve its root from the active session project context"
)
assertContains(
    dashboardView,
    "currentSessionMetadata?.projectId",
    "right workspace file tree should use the current session project before falling back to the agent workspace"
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
    "RightInspectorSplitView(",
    "DashboardView should compose the reusable right inspector shell"
)
assertContains(
    rightInspectorSplit,
    "struct RightInspectorSplitView<Content: View, Sidebar: View>: NSViewControllerRepresentable",
    "right Outputs column should be bridged through a reusable AppKit inspector shell"
)
assertContains(
    rightInspectorSplit,
    "let contentUpdateID: AnyHashable",
    "right inspector split should accept a content identity separate from sidebar layout state"
)
assertContains(
    rightInspectorSplit,
    "private final class RightInspectorSplitController: NSViewController",
    "right Outputs column should be managed by a reusable constraint-driven AppKit controller"
)
assertNotContains(
    dashboard,
    "private final class DashboardWorkspaceSplitController: NSViewController",
    "DashboardView should not inline the reusable AppKit inspector controller"
)
assertNotContains(
    dashboard,
    "private struct DashboardWorkspaceSplitView<Content: View, Sidebar: View>: NSViewControllerRepresentable",
    "DashboardView should not inline the reusable AppKit inspector shell"
)
assertContains(
    rightInspectorSplit,
    "enum RightInspectorSplitMetrics",
    "right split should expose shared metrics for the titlebar accessory"
)
assertContains(
    rightInspectorSplit,
    "static let animationDuration: TimeInterval = 0.30",
    "right split and titlebar accessory should share one smoother animation duration"
)
assertContains(
    rightInspectorSplit,
    "sidebarWidthConstraint?.animator().constant",
    "AppKit inspector shell should animate the sidebar width constraint instead of jumping visible state"
)
assertContains(
    rightInspectorSplit,
    "private var isAnimatingSidebar = false",
    "right AppKit inspector controller should track sidebar animation state"
)
assertContains(
    rightInspectorSplit,
    "guard hasInstalledLayout, hasAppliedInitialLayout, !isAnimatingSidebar else { return }",
    "layout passes during sidebar animation should not force the inspector to its final width"
)
assertContains(
    rightInspectorSplitController,
    "private let layoutEpsilon: CGFloat = 0.5",
    "right AppKit inspector should tolerate sub-point layout differences before relayout"
)
assertContains(
    rightInspectorSplitController,
    "private func isSidebarWidthApplied(_ width: CGFloat) -> Bool",
    "right AppKit inspector should detect when the target width is already applied"
)
assertContains(
    rightInspectorSplitController,
    "guard !isSidebarWidthApplied(clampedWidth) else { return }",
    "right AppKit inspector should not force AppKit layout when sidebar width has not changed"
)
assertContains(
    rightInspectorSplitController,
    "if !isSidebarWidthApplied(targetWidth) {\n                setSidebarWidth(targetWidth)\n            }",
    "right AppKit inspector should avoid no-op non-animated layout flushes"
)
assertContains(
    rightInspectorSplit,
    "isAnimatingSidebar = true",
    "right AppKit inspector controller should mark animated transitions before changing width"
)
assertContains(
    rightInspectorSplit,
    "self.isAnimatingSidebar = false",
    "right AppKit inspector controller should clear animation state after width animation completes"
)
assertContains(
    rightInspectorSplitController,
    "private var sidebarAnimationGeneration = 0",
    "right AppKit inspector controller should invalidate stale animation completions"
)
assertContains(
    rightInspectorSplitController,
    "private var currentContentUpdateID: AnyHashable?",
    "right AppKit inspector controller should remember the last middle-content identity"
)
assertContains(
    rightInspectorSplitController,
    "if currentContentUpdateID != contentUpdateID {\n            contentHost.rootView = content\n            currentContentUpdateID = contentUpdateID\n        }",
    "right AppKit inspector controller should only replace the middle chat root when its content identity changes"
)
assertNotContains(
    rightInspectorSplitController,
    "\n        contentHost.rootView = content\n        let previousTargetWidth",
    "right sidebar layout updates should not unconditionally replace the middle chat root"
)
assertContains(
    rightInspectorSplitController,
    "private var onSidebarCollapseFinished: (() -> Void)?",
    "right AppKit inspector controller should own a collapse completion callback"
)
assertContains(
    rightInspectorSplitController,
    "private var onSidebarExpandFinished: (() -> Void)?",
    "right AppKit inspector controller should own an expand completion callback"
)
assertContains(
    rightInspectorSplitController,
    "private var lastExpandRequestID = 0",
    "right AppKit inspector controller should track the latest direct expand request"
)
assertContains(
    rightInspectorSplitController,
    "private var lastCollapseRequestID = 0",
    "right AppKit inspector controller should track the latest direct collapse request"
)
assertContains(
    rightInspectorSplitController,
    "private var locallyManagedSidebarWidth: CGFloat?",
    "right AppKit inspector controller should keep a local width override while the inspector-internal detail column animates"
)
assertContains(
    rightInspectorSplitController,
    "let shouldCollapseFromRequest = collapseRequestID != lastCollapseRequestID",
    "right sidebar should start closing from a direct AppKit request before SwiftUI commits collapsed state"
)
assertContains(
    rightInspectorSplitController,
    "let shouldExpandFromRequest = expandRequestID != lastExpandRequestID",
    "right sidebar should start opening from a direct AppKit request before SwiftUI commits expanded state"
)
assertContains(
    rightInspectorSplitController,
    "let isCollapsingSidebar = (shouldAnimate && currentIsSidebarExpanded && !isSidebarExpanded && hasAppliedInitialLayout) || (shouldCollapseFromRequest && hasAppliedInitialLayout)",
    "right sidebar collapse should be detected before replacing the SwiftUI sidebar root"
)
assertContains(
    rightInspectorSplitController,
    "let shouldDeferSidebarRootUpdate = isCollapsingSidebar || (isAnimatingSidebar && !currentIsSidebarExpanded)",
    "right sidebar should keep its existing content during follow-up updates while closing"
)
assertContains(
    rightInspectorSplitController,
    "if !shouldDeferSidebarRootUpdate {\n            sidebarHost.rootView = AnyView(sidebar.environment(\\.rightInspectorSidebarWidthCoordinator, sidebarWidthCoordinator))\n        }",
    "right sidebar should keep its existing content mounted while closing"
)
assertContains(
    rightInspectorSplitController,
    "let effectiveSidebarWidth = locallyManagedSidebarWidth ?? sidebarWidth",
    "right AppKit inspector controller should prefer the locally animated width over stale parent sidebarWidth updates"
)
assertContains(
    rightInspectorSplitController,
    "if let locallyManagedSidebarWidth, abs(sidebarWidth - locallyManagedSidebarWidth) <= layoutEpsilon",
    "right AppKit inspector controller should release the local width override after SwiftUI catches up to the animated width"
)
assertContains(
    rightInspectorSplitController,
    "self.sidebarHost.rootView = AnyView(sidebar.environment(\\.rightInspectorSidebarWidthCoordinator, self.sidebarWidthCoordinator))\n                    self.onSidebarCollapseFinished?()",
    "right sidebar should update its root and clear state only after the close animation finishes"
)
assertContains(
    rightInspectorSplitController,
    "if isAnimatingSidebar && !currentIsSidebarExpanded && isSidebarExpanded {\n            return\n        }",
    "right sidebar should not reverse a requested close if SwiftUI still reports the business state as expanded"
)
assertContains(
    rightInspectorSplitController,
    "if isAnimatingSidebar && currentIsSidebarExpanded && !isSidebarExpanded {\n            return\n        }",
    "right sidebar should not reverse a requested open if SwiftUI still reports the business state as collapsed"
)
assertContains(
    rightInspectorSplitController,
    "self.sidebarHost.rootView = AnyView(sidebar.environment(\\.rightInspectorSidebarWidthCoordinator, self.sidebarWidthCoordinator))\n                    self.onSidebarExpandFinished?()",
    "right sidebar should commit expanded state only after the open animation finishes"
)
assertContains(
    rightInspectorSplitController,
    "let animationID = sidebarAnimationGeneration",
    "right AppKit inspector controller should tag each sidebar animation"
)
assertContains(
    rightInspectorSplitController,
    "guard self.sidebarAnimationGeneration == animationID else { return }",
    "stale sidebar animation completions should not collapse or hide the current sidebar state"
)
assertContains(
    rightInspectorSplitController,
    "view.layoutSubtreeIfNeeded()",
    "right AppKit inspector controller should flush layout before animating the width constraint"
)
assertContains(
    rightInspectorSplitController,
    "let sourceWidth = sidebarWidthConstraint?.constant ?? 0",
    "right AppKit inspector controller should know the current rail width before deciding how to size hosted content during an animation"
)
assertContains(
    rightInspectorSplitController,
    "if targetWidth >= sourceWidth",
    "right AppKit inspector controller should only grow hosted content immediately; shrinking content width before the rail animation finishes makes the detail panel disappear abruptly"
)
assertContains(
    rightInspectorSplitController,
    "self.sidebarContentWidthConstraint?.constant = targetWidth",
    "right AppKit inspector controller should commit the hosted content width after the rail animation completes"
)
assertContains(
    rightInspectorSplitController,
    "animateSidebarWidth(to: targetWidth)",
    "right AppKit inspector controller should animate width changes while already expanded"
)
assertContains(
    rightInspectorSplitController,
    "private let sidebarRail = NSView()",
    "right sidebar should use an AppKit rail like an Xcode inspector"
)
assertContains(
    rightInspectorSplitController,
    "private let sidebarSeparator = NSBox()",
    "right sidebar rail should own a native separator line"
)
assertContains(
    rightInspectorSplitController,
    "private var dragStartSidebarWidth: CGFloat = 0",
    "right inspector resize should track the sidebar width at drag start"
)
assertContains(
    rightInspectorSplitController,
    "private let sidebarClipView = NSView()",
    "right sidebar rail should own a dedicated clipping view for SwiftUI content"
)
assertContains(
    rightInspectorSplitController,
    "sidebarRail.clipsToBounds = true",
    "right sidebar rail should clip separator and content during width animation"
)
assertContains(
    rightInspectorSplitController,
    "sidebarClipView.clipsToBounds = true",
    "right sidebar clip view should prevent SwiftUI content from flashing outside the rail"
)
assertContains(
    rightInspectorSplitController,
    "sidebarRail.addSubview(sidebarSeparator)",
    "right sidebar separator should be installed inside the rail"
)
assertContains(
    rightInspectorSplitController,
    "NSPanGestureRecognizer(target: self, action: #selector(handleSidebarResizePan(_:)))",
    "right inspector separator should support dragging to resize the sidebar like a native split"
)
assertContains(
    rightInspectorSplitController,
    "sidebarSeparator.addGestureRecognizer(resizePan)",
    "right inspector resize gesture should be attached to the visible separator"
)
assertContains(
    rightInspectorSplitController,
    "sidebarRail.addSubview(sidebarClipView)",
    "right sidebar clip view should be installed inside the rail"
)
assertContains(
    rightInspectorSplitController,
    "sidebarClipView.addSubview(sidebarHost.view)",
    "right sidebar SwiftUI host should live inside the clipping view"
)
assertContains(
    rightInspectorSplitController,
    "sidebarRail.widthAnchor.constraint(equalToConstant: 0)",
    "right sidebar width animation should target the whole inspector rail"
)
assertContains(
    rightInspectorSplitController,
    "contentHost.view.trailingAnchor.constraint(equalTo: sidebarRail.leadingAnchor)",
    "middle content and right inspector rail should share the same moving boundary"
)
assertContains(
    rightInspectorSplitController,
    "sidebarRail.trailingAnchor.constraint(equalTo: view.trailingAnchor)",
    "right inspector rail should stay pinned to the window edge"
)
assertContains(
    rightInspectorSplitController,
    "sidebarSeparator.leadingAnchor.constraint(equalTo: sidebarRail.leadingAnchor)",
    "right inspector separator should sit on the moving boundary"
)
assertContains(
    rightInspectorSplitController,
    "sidebarClipView.leadingAnchor.constraint(equalTo: sidebarSeparator.trailingAnchor)",
    "right inspector content should start after the separator"
)
assertContains(
    rightInspectorSplitController,
    "sidebarHost.view.leadingAnchor.constraint(equalTo: sidebarClipView.leadingAnchor)",
    "right sidebar SwiftUI host should be anchored inside the clip view"
)
assertContains(
    rightInspectorSplitController,
    "@objc private func handleSidebarResizePan(_ recognizer: NSPanGestureRecognizer)",
    "right inspector should implement a local AppKit resize handler"
)
assertContains(
    rightInspectorSplitController,
    "let proposedWidth = dragStartSidebarWidth - translation.x",
    "right inspector resize should grow when dragging its left separator leftward"
)
assertContains(
    rightInspectorSplitController,
    "locallyManagedSidebarWidth = clampedWidth",
    "right inspector drag resize should stay layout-local and not enter chat content identity"
)
assertContains(
    rightInspectorSplitController,
    "sidebarContentWidthConstraint?.constant",
    "right sidebar SwiftUI host width should be pre-sized separately from the animated rail"
)
assertContains(
    rightInspectorSplitController,
    "separatorWidthConstraint.priority = .fittingSizeCompression",
    "right inspector separator width should yield when the rail animates down to zero width"
)
assertNotContains(
    rightInspectorSplitController,
    "sidebarRail.isHidden",
    "right inspector rail should stay mounted at zero width so width animation remains smooth"
)
assertNotContains(
    rightInspectorSplitController,
    "sidebarHost.view.isHidden",
    "right sidebar should not toggle the SwiftUI host visibility during titlebar button animation"
)
assertNotContains(
    rightInspectorSplitController,
    "sidebarContainer",
    "right sidebar should use the fuller rail/clip/separator structure rather than the simpler B container"
)
assertNotContains(
    rightInspectorSplitController,
    "NSSplitViewItem",
    "right inspector shell should not use resident NSSplitViewItem state"
)
assertNotContains(
    rightInspectorSplitController,
    "splitView.setPosition",
    "right inspector shell should not jump the NSSplitView divider position"
)
assertNotContains(
    rightInspectorSplitController,
    "splitView.animator().setPosition",
    "right inspector shell should animate one width constraint instead of the split divider"
)
assertNotContains(
    rightInspectorSplitController,
    "canCollapse",
    "right inspector shell should not rely on split-item collapse behavior"
)
assertNotContains(
    rightInspectorSplitController,
    "prepareSidebarForExpansion",
    "right AppKit inspector should not relayout in a separate pre-expansion phase"
)
assertNotContains(
    rightInspectorSplitController,
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
let hasWorkspaceDetailPanel = slice(dashboardView, from: "private var hasWorkspaceDetailPanel: Bool", to: "    private func jumpToUserMessage")
let shouldRetainWorkspaceSidebarContent = slice(dashboardView, from: "private var shouldRetainWorkspaceSidebarContent: Bool", to: "    private var workspaceColumnIdealWidth")
assertNotContains(
    isWorkspaceSidebarExpanded,
    "!isWorkspaceSidebarClosing",
    "right sidebar close should not commit the visual expanded state before the AppKit collapse animation starts"
)
assertContains(
    hasWorkspaceDetailPanel,
    "workspaceDetailWidth > 0",
    "DashboardView should only track whether the inspector detail width is present"
)
assertContains(
    workspaceInspectorPane,
    "case .filePreview(let path):",
    "workspace inspector pane should own file preview detail state"
)
assertContains(
    workspaceInspectorPane,
    "case .projectTree:",
    "workspace inspector pane should own secondary project file tree state"
)
assertContains(
    shouldRetainWorkspaceSidebarContent,
    "workspaceSidebarExpanded || hasWorkspaceDetailPanel || isWorkspaceSidebarOpening || isWorkspaceSidebarClosing",
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
let timelineChatSurface = slice(dashboard, from: "private var timelineChatSurface: some View", to: "private func handleChatScrollPositionChange")
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

let workspaceFilePanel = slice(workspaceInspector, from: "private struct WorkspaceFilePanel: View", to: "    private var outputsEmptyState: some View")
let workspaceOutputsPaneHeader = slice(workspaceInspector, from: "private struct WorkspaceOutputsPaneHeader: View", to: "struct WorkspaceInspectorPane: View")
let workspaceInspectorPane = slice(workspaceInspector, from: "struct WorkspaceInspectorPane: View", to: "private struct WorkspaceFilePanel: View")
let projectFilesPanel = slice(workspaceInspector, from: "private struct ProjectFilesPanel: View", to: "private struct CommitTextField")
let openWorkspaceInFinderIcon = slice(workspaceInspector, from: "private struct OpenWorkspaceInFinderIcon: View", to: "private struct SecondaryProjectSidebarIcon: View")
let fileEditorPanel = slice(workspaceInspector, from: "private struct FileEditorPanel: View", to: "    // MARK: - Status Bar")
let editableWorkspaceFileTreePanel = slice(
    workspaceInspector,
    from: "private struct EditableWorkspaceFileTreePanel<EmptyState: View>: View",
    to: "private struct WorkspaceFileTreeRow: View"
)
for extractedType in [
    "struct WorkspaceInspectorPane: View",
    "struct WorkspaceFilePanel: View",
    "struct ProjectFilesPanel: View",
    "struct FileEditorPanel: View",
    "struct CodeEditorView: NSViewRepresentable",
    "struct QuickLookPreview: NSViewRepresentable"
] {
    assertNotContains(
        dashboard,
        extractedType,
        "right inspector implementation types should live under Views/Dashboard/Inspector instead of DashboardView.swift"
    )
}
assertContains(
    workspaceFilePanel,
    "let root: WorkspaceSidebarRoot",
    "WorkspaceFilePanel should receive an explicit root instead of deriving it from the agent"
)
assertNotContains(
    workspaceFilePanel,
    "DashboardViewModel.resolveAgentWorkspace(agentId)",
    "WorkspaceFilePanel should not fall back to the agent default workspace internally"
)
assertContains(
    projectFilesPanel,
    "workspaceRootHeader",
    "ProjectFilesPanel should show which project/workspace root is currently being rendered"
)
assertNotContains(
    workspaceFilePanel,
    "workspaceRootHeader",
    "Outputs list should not show the project tree root header unless the secondary project panel is open"
)
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
    "private var currentAgentWorkspacePath: String",
    "Open/Finder should target the current agent's local workspace directory"
)
assertContains(
    dashboard,
    "DashboardViewModel.resolveAgentWorkspace(viewModel.selectedAgentId)",
    "Open/Finder should resolve the workspace from the selected agent id"
)
assertContains(
    dashboard,
    "try? FileManager.default.createDirectory",
    "Open/Finder should ensure the current agent workspace exists before asking Finder to open it"
)
assertContains(
    workspaceInspector,
    "private struct SecondaryProjectSidebarIcon: View",
    "secondary project sidebar button should use the layered rounded-rectangle vector icon shown in the design reference"
)
assertContains(
    workspaceInspector,
    "private struct SecondaryProjectSidebarBackShape: Shape",
    "secondary project sidebar icon should draw the exposed rear rounded-rectangle outline as vector"
)
assertContains(
    workspaceInspector,
    "private struct SecondaryProjectSidebarFrontShape: Shape",
    "secondary project sidebar icon should draw the front rounded-rectangle card as vector"
)
assertContains(
    workspaceInspector,
    "private struct OpenWorkspaceInFinderIcon: View",
    "Open/Finder button should use the uploaded reference as a custom thin-stroke vector icon"
)
assertContains(
    workspaceOutputsPaneHeader,
    "OpenWorkspaceInFinderIcon(",
    "right workspace header should keep a dedicated Open/Finder icon"
)
assertContains(
    workspaceOutputsPaneHeader,
    "SecondaryProjectSidebarIcon(",
    "right workspace header should render the secondary project sidebar icon in the old search button position"
)
assertContains(
    workspaceInspector,
    "private struct WorkspaceHeaderIconButton<Icon: View>: View",
    "right workspace header icon buttons should share a full-frame hit target wrapper"
)
assertContains(
    workspaceOutputsPaneHeader,
    "WorkspaceHeaderIconButton(",
    "right workspace header should wrap icon-only buttons so transparent vector interiors remain clickable"
)
assertContains(
    workspaceInspector,
    ".contentShape(Rectangle())",
    "right workspace header icon buttons should make the full icon frame hit-testable"
)
assertBefore(
    workspaceOutputsPaneHeader,
    "OpenWorkspaceInFinderIcon(",
    "SecondaryProjectSidebarIcon(",
    "Open/Finder should sit before the secondary project sidebar button"
)
assertContains(
    workspaceInspectorPane,
    "@State private var detailMode: WorkspaceDetailMode = .none",
    "secondary project sidebar state should be owned inside the workspace inspector pane"
)
assertContains(
    workspaceInspectorPane,
    "@State private var targetDetailMode: WorkspaceDetailMode = .none",
    "secondary project sidebar should track the user's requested detail mode separately from the committed business state"
)
assertContains(
    workspaceInspectorPane,
    "toggleWorkspaceProjectFiles",
    "right workspace header should toggle the secondary project files panel instead of toggling search directly"
)
assertContains(
    workspaceInspectorPane,
    "if isProjectFilesVisible {",
    "secondary project sidebar button should close the project files panel when it is already visible or retained during animation"
)
assertNotContains(
    workspaceInspectorPane,
    "switch targetDetailMode {\n        case .projectTree:",
    "secondary project sidebar close behavior should not depend only on the committed target mode"
)
assertContains(
    workspaceInspector,
    "private enum WorkspaceDetailMode: Equatable",
    "right inspector detail area should switch between file preview and project tree modes"
)
assertContains(
    workspaceInspectorPane,
    "case .projectTree:",
    "secondary project sidebar should reuse the existing file preview/detail area"
)
assertContains(
    workspaceInspectorPane,
    "ProjectFilesPanel(",
    "secondary project sidebar should render the project file tree in the existing detail area"
)
assertContains(
    workspaceInspectorPane,
    "WorkspaceInspectorContentSplit(",
    "secondary project sidebar width changes should be handled inside the inspector content split"
)
assertContains(
    workspaceInspectorPane,
    "GeometryReader { proxy in",
    "workspace inspector content should measure the actual available sidebar width before laying out Outputs plus the secondary column"
)
assertContains(
    workspaceInspectorPane,
    "WorkspaceInspectorContentLayout(",
    "workspace inspector content should use a dedicated layout calculator for narrow-window width allocation"
)
assertContains(
    workspaceInspectorPane,
    "availableWidth: proxy.size.width",
    "workspace inspector layout should be based on the actual visible inspector width"
)
assertContains(
    workspaceInspector,
    "let targetTotalWidth = availableWidth",
    "workspace inspector content should stretch to the actual resized sidebar width instead of capping at the default 280+480 width"
)
assertContains(
    workspaceInspector,
    "let availableSecondaryWidth = max(0, targetTotalWidth - preferredPrimaryWidth)",
    "workspace inspector content should collapse the secondary column against the Outputs target width"
)
assertNotContains(
    workspaceInspector,
    "targetTotalWidth - minimumPrimaryWidth",
    "workspace inspector secondary column should not keep residual width after the outer inspector reaches the Outputs target width"
)
assertContains(
    workspaceInspector,
    "let targetSecondaryWidth = min(preferredSecondaryWidth, availableSecondaryWidth)",
    "workspace inspector secondary width should follow the outer AppKit sidebar animation instead of running an independent SwiftUI width animation"
)
assertNotContains(
    workspaceInspector,
    "let targetSecondaryWidth = availableSecondaryWidth >= minimumSecondaryWidth",
    "workspace inspector should not hold the secondary column above its minimum width while the outer sidebar is collapsing"
)
assertContains(
    workspaceInspector,
    "let primaryWidth = max(0, targetTotalWidth - targetSecondaryWidth)",
    "workspace inspector Outputs column should move with the animated secondary column instead of jumping between full-width and split layouts"
)
assertNotContains(
    workspaceInspector,
    "let secondaryWidth = max(0, targetTotalWidth - primaryWidth)",
    "workspace inspector secondary width should not be derived only from the remaining visible width because that ignores the animation progress"
)
assertContains(
    workspaceInspectorPane,
    "primaryWidth: layout.primaryWidth",
    "inspector content split should receive an explicit primary Outputs column width so the Outputs content is visible before the secondary column opens"
)
assertContains(
    workspaceInspectorPane,
    "totalWidth: layout.totalWidth",
    "inspector content split should fit the current visible inspector width instead of keeping an oversized fixed layout"
)
assertContains(
    workspaceInspectorPane,
    "secondaryWidth: layout.secondaryWidth",
    "secondary project sidebar should shrink when the visible inspector width is narrow"
)
assertContains(
    workspaceInspectorPane,
    "width: layout.secondaryContentWidth",
    "project tree content width should follow the clipped secondary column width"
)
assertNotContains(
    workspaceInspectorPane,
    "totalWidth: browserWidth + visualDetailWidth",
    "workspace inspector content should not keep a fixed 280+480 layout that can clip Outputs in narrow windows"
)
assertNotContains(
    workspaceInspectorPane,
    "sidebarWidthCoordinator.animateSidebarWidth(totalWidth)",
    "secondary project sidebar collapse should not clip the whole outer inspector while the nested column is shrinking"
)
assertContains(
    workspaceInspectorPane,
    "private func requestWorkspaceDetail(_ nextMode: WorkspaceDetailMode",
    "secondary project sidebar clicks should issue a detail-column animation request instead of directly committing the business mode"
)
assertContains(
    workspaceInspectorPane,
    "targetDetailMode = nextMode",
    "secondary project sidebar should record the latest requested mode before animation so stale completions cannot win"
)
assertContains(
    workspaceInspectorPane,
    "@State private var renderedDetailMode: WorkspaceDetailMode = .none",
    "secondary detail content should have a separate render mode so it can mount before business state commits"
)
assertNotContains(
    workspaceInspectorPane,
    "@State private var detailContentProgress: CGFloat = 0",
    "secondary detail content visibility should be controlled by clipped width, not a second opacity state"
)
assertContains(
    workspaceInspectorPane,
    "@State private var committedDetailWidth: CGFloat = 0",
    "secondary detail close should keep a committed parent width until the collapse animation finishes"
)
assertContains(
    workspaceInspectorPane,
    "renderedDetailMode = nextMode",
    "secondary detail content should mount before its open width animation starts"
)
assertContains(
    workspaceInspectorPane,
    "renderedDetailMode = .none",
    "secondary detail content should unmount only after the width animation finishes"
)
assertNotContains(
    workspaceInspectorPane,
    "animateDetailContentProgress(to: 0)",
    "secondary detail content should not disappear before the outer inspector collapse animation finishes"
)
assertNotContains(
    workspaceInspectorPane,
    ".opacity(detailContentProgress)",
    "secondary detail content should become visible through width clipping instead of opacity animation"
)
assertNotContains(
    workspaceInspectorPane,
    ".offset(x: (1 - detailContentProgress) * 10)",
    "secondary detail content should not run a separate slide animation while the column width is animating"
)
assertContains(
    workspaceInspectorPane,
    "@Environment(\\.rightInspectorSidebarWidthCoordinator)",
    "secondary project sidebar should coordinate the outer AppKit inspector width with its local clipped column animation"
)
assertContains(
    workspaceInspectorPane,
    "sidebarWidthCoordinator.animateSidebarWidth(browserWidth + sanitizedWidth)",
    "secondary project sidebar should push the outer inspector divider as soon as the local detail-width animation starts"
)
assertNotContains(
    workspaceInspectorPane,
    "withAnimation(.easeInOut(duration: RightInspectorSplitMetrics.animationDuration)) {\n            visualDetailWidth = sanitizedWidth\n        }",
    "secondary project sidebar should not run a separate SwiftUI width animation in parallel with the AppKit sidebar width animation"
)
assertContains(
    workspaceInspectorPane,
    "if sanitizedWidth > 0 {\n            visualDetailWidth = sanitizedWidth\n        }",
    "secondary detail open should prepare the inner detail width before the outer AppKit animation starts"
)
assertContains(
    workspaceInspectorPane,
    "if sanitizedWidth == 0 {\n                visualDetailWidth = 0\n            }",
    "secondary detail close should clear the inner detail width only after the outer AppKit animation finishes"
)
assertNotContains(
    workspaceInspectorPane,
    "if animated, sanitizedWidth > 0 {\n            sidebarWidthCoordinator.animateSidebarWidth(browserWidth + sanitizedWidth)",
    "secondary detail close should animate the outer inspector divider together with the local secondary column"
)
assertNotContains(
    workspaceInspectorPane,
    "let shouldCommitParentWidthImmediately = sanitizedWidth > 0",
    "secondary detail width should not publish positive or zero parent state before the animation completes"
)
assertNotContains(
    workspaceInspectorPane,
    "if shouldCommitParentWidthImmediately {\n            committedDetailWidth = sanitizedWidth",
    "secondary detail open should not commit positive parent width before the visible width animation completes"
)
assertNotContains(
    workspaceInspectorPane,
    "guard !shouldCommitParentWidthImmediately else { return }",
    "secondary detail width commit should not branch between open and close before the animation completes"
)
assertContains(
    workspaceInspectorPane,
    "DispatchQueue.main.asyncAfter(deadline: .now() + RightInspectorSplitMetrics.animationDuration) {\n            guard detailAnimationGeneration == animationID else { return }\n            if sanitizedWidth == 0 {\n                visualDetailWidth = 0\n            }\n            committedDetailWidth = sanitizedWidth\n            onDetailWidthChanged(committedDetailWidth)",
    "secondary detail width should commit to parent only after the outer width animation completes"
)
assertNotContains(
    workspaceInspectorPane,
    "onDetailWidthChanged(sanitizedWidth)\n        if animated",
    "secondary detail close should not publish zero width to DashboardView before the collapse animation completes"
)
assertContains(
    workspaceInspectorPane,
    "@State private var previewReturnMode: WorkspaceDetailMode = .none",
    "file previews opened from the secondary project tree should remember that closing returns to the tree"
)
assertContains(
    workspaceInspectorPane,
    "private func closeWorkspacePreview()",
    "file preview close should choose between returning to project tree and closing the detail column"
)
assertContains(
    workspaceInspectorPane,
    "requestWorkspaceDetail(returnMode)",
    "file preview close should return to the secondary project tree when the file was opened from that tree"
)
assertContains(
    workspaceInspectorPane,
    "detailMode = nextMode\n            completion?()",
    "secondary project sidebar should commit the business mode only after the width animation finishes"
)
assertNotContains(
    workspaceInspectorPane,
    "detailMode = nextMode\n        animateDetailWidth",
    "secondary project sidebar should not commit business state before starting its width animation"
)
assertNotContains(
    workspaceInspectorPane,
    "detailMode = .projectTree\n            retainedDetailMode = .projectTree",
    "secondary project sidebar should not commit project-tree business state before the width animation starts"
)
assertContains(
    workspaceInspectorPane,
    "@State private var detailAnimationGeneration = 0",
    "secondary project sidebar should tag local width animations so stale completions cannot overwrite current state"
)
assertContains(
    workspaceInspectorPane,
    "guard detailAnimationGeneration == animationID else { return }",
    "secondary project sidebar should ignore stale local animation completions"
)
assertNotContains(
    workspaceInspectorPane,
    "withAnimation(.easeInOut(duration: RightInspectorSplitMetrics.animationDuration))",
    "secondary project sidebar should not run a second SwiftUI animation while the outer AppKit width reveals clipped content"
)
assertContains(
    projectFilesPanel,
    "TextField(I18n.t(\"workspace.files.filterPlaceholder\"), text: $searchText)",
    "project tree search should move inside the secondary project files panel"
)
assertContains(
    openWorkspaceInFinderIcon,
    "StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)",
    "Open/Finder vector icon should use a thinner custom stroke"
)
assertNotContains(
    workspaceOutputsPaneHeader,
    "Image(systemName: \"magnifyingglass\")",
    "right workspace header should no longer use the search button as a top-level control"
)
assertContains(
    dashboard,
    "private func workspaceSidebarPane(width: CGFloat) -> some View",
    "right Outputs header and content should live in one AppKit split pane"
)
let workspaceSidebarPane = slice(dashboard, from: "private func workspaceSidebarPane(width: CGFloat) -> some View", to: "    private func toggleWorkspaceSidebar")
assertContains(
    workspaceSidebarPane,
    "WorkspaceInspectorPane(",
    "right split pane should delegate local Outputs/project-file state to a child inspector pane"
)
assertContains(
    workspaceSidebarPane,
    ".frame(maxWidth: .infinity, alignment: .top)",
    "right workspace pane should fill the actual AppKit sidebar width instead of fixing itself to the ideal width"
)
assertNotContains(
    workspaceSidebarPane,
    ".frame(width: width",
    "right workspace pane should not force an oversized fixed width that hides Outputs in narrow windows"
)
assertContains(
    workspaceInspectorPane,
    "WorkspaceOutputsPaneHeader(",
    "workspace inspector pane should own the Outputs header row"
)
assertContains(
    workspaceInspectorPane,
    "WorkspaceFilePanel(",
    "workspace inspector pane should own the Outputs file content"
)
assertContains(
    workspaceInspector,
    "let primaryWidth: CGFloat",
    "WorkspaceInspectorContentSplit should accept an explicit primary column width"
)
assertContains(
    workspaceInspector,
    "let totalWidth: CGFloat",
    "WorkspaceInspectorContentSplit should accept an explicit total width for the local inspector container"
)
assertContains(
    workspaceInspector,
    ".frame(width: totalWidth, alignment: .topLeading)",
    "WorkspaceInspectorContentSplit should pin the local container width to the primary plus secondary column widths"
)
assertContains(
    workspaceInspector,
    ".frame(width: primaryWidth)",
    "WorkspaceInspectorContentSplit should keep the primary Outputs column stable with an explicit width"
)
assertContains(
    workspaceInspector,
    ".fill(Color(NSColor.separatorColor))",
    "WorkspaceInspectorContentSplit should draw a real separator between Outputs and the secondary file column"
)
assertNotContains(
    workspaceInspector,
    ".fill(Color.clear)\n                .frame(width: 1)\n                .shadow(color: .black.opacity(0.15)",
    "secondary file panels should not fake their separator with an invisible rectangle and shadow"
)
assertContains(
    workspaceInspector,
    "private struct WorkspaceFileTreeRow: View",
    "Outputs and project file lists should share one row component"
)
assertContains(
    workspaceInspector,
    "private struct EditableWorkspaceFileTreePanel<EmptyState: View>: View",
    "Outputs and project file lists should share one editable tree component"
)
assertContains(
    workspaceFilePanel,
    "EditableWorkspaceFileTreePanel(",
    "Outputs should render through the shared editable file tree"
)
assertContains(
    projectFilesPanel,
    "EditableWorkspaceFileTreePanel(",
    "Project files should render through the shared editable file tree"
)
for sharedOperation in [
    "private func beginNewItem(parent: String, isFolder: Bool)",
    "private func performNewItem(name inputName: String)",
    "private func performRename(oldPath: String, newName inputName: String)",
    "private func performDelete(path: String)",
    "private func performPaste(into directory: String)"
] {
    assertContains(
        editableWorkspaceFileTreePanel,
        sharedOperation,
        "file tree operation \(sharedOperation) should live in the shared editable tree component"
    )
}
assertContains(
    workspaceInspectorPane,
    "sidebarWidthCoordinator.animateSidebarWidth(browserWidth + sanitizedWidth)",
    "secondary column expand and collapse should both drive the outer AppKit sidebar width animation first"
)
assertNotContains(
    workspaceInspectorPane,
    "if animated, sanitizedWidth > 0",
    "secondary column collapse should not skip the outer AppKit width animation"
)
assertNotContains(
    fileEditorPanel,
    "@Binding var isFullscreen",
    "file editor should not keep a fullscreen binding for a non-functional header button"
)
assertNotContains(
    fileEditorPanel,
    "isFullscreen",
    "file editor should not retain fullscreen toggle logic"
)
assertNotContains(
    fileEditorPanel,
    "arrow.up.left.and.arrow.down.right",
    "file editor should remove the non-functional expand header button"
)
assertNotContains(
    fileEditorPanel,
    "arrow.down.right.and.arrow.up.left",
    "file editor should remove the non-functional collapse header button"
)
assertContains(
    fileEditorPanel,
    "Image(systemName: viewMode == .preview ? \"square.and.pencil\" : \"eye\")",
    "editable files should use a standard edit/preview toggle icon"
)
assertNotContains(
    fileEditorPanel,
    "Image(systemName: viewMode == .preview ? \"pencil.line\" : \"eye\")",
    "editable files should not use the old blue pencil-line edit icon"
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
