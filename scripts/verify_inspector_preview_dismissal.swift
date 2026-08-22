import Foundation

// Guards the "close the file preview in ONE click" invariant.
//
// Closing a chat-opened preview must land on exactly what the user had before
// the preview appeared:
//   * inspector was closed  -> collapse the whole inspector
//   * file list was showing -> return to the file list
//
// Two bugs made this take two clicks, both from deriving the answer at the
// wrong time or from the wrong state:
//   1. `collapseOnClose` was read AFTER `revealWorkspaceSidebar()`, so the
//      answer depended on where the reveal animation happened to be.
//   2. Opening a SECOND file from chat while the first preview owned the pane
//      re-derived `collapseOnClose` from "is the inspector visible" — it was,
//      but only because of the first preview — so the second file's close fell
//      back to the file list the user had never opened.

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

let dashboard = ["OpenClawInstaller/Features/Dashboard/DashboardTypography.swift", "OpenClawInstaller/Features/Dashboard/DashboardView.swift", "OpenClawInstaller/Features/Dashboard/Sidebar/DashboardSidebar.swift", "OpenClawInstaller/Features/Chat/Views/ChatView.swift", "OpenClawInstaller/Features/Chat/Views/ComposerChrome.swift", "OpenClawInstaller/Features/Chat/Views/ChatBubbleViews.swift"].map(read).joined(separator: "\n")
let pane = read("OpenClawInstaller/Features/Workspace/Views/Inspector/WorkspaceInspectorPane.swift")

// --- 1. The owner must decide the close behaviour BEFORE revealing ---
guard let captureRange = dashboard.range(of: "let collapseOnClose = !isWorkspaceSidebarExpanded"),
      let revealRange = dashboard.range(of: "revealWorkspaceSidebar()") else {
    fatalError("DashboardView no longer captures collapseOnClose / reveals the sidebar")
}
require(
    captureRange.lowerBound < revealRange.lowerBound,
    "collapseOnClose must be captured BEFORE revealWorkspaceSidebar(); reading it afterwards makes close behaviour depend on animation timing"
)

// --- 2. A chained preview must inherit the dismissal, not re-derive it ---
require(
    pane.contains("private var isChainedPreviewOpen: Bool"),
    "WorkspaceInspectorPane must expose isChainedPreviewOpen so a second chat-opened file keeps the first preview's dismissal"
)
require(
    pane.contains("guard !isTreeVisibleWithPreview else { return false }"),
    "isChainedPreviewOpen must be false once the file list is showing alongside the preview — the list then IS the user's context"
)
require(
    pane.contains("let dismissal: PreviewDismissal = isChainedPreviewOpen")
        && pane.contains("? previewDismissal"),
    "the .gchOpenWorkspaceFilePreview handler must inherit previewDismissal while a chat preview owns the pane"
)

// --- 3. The two dismissal outcomes must still exist and stay distinct ---
require(pane.contains("case collapseInspector"), "PreviewDismissal.collapseInspector missing")
require(pane.contains("case fileList"), "PreviewDismissal.fileList missing")

// --- 4. The owner must not pre-zero its lagging detail width before hiding ---
// `hideWorkspaceSidebar` early-returns (no collapse animation) when it believes
// there is no content to retain, so zeroing workspaceDetailWidth first can leave
// the inspector stuck open.
if let closeCallback = dashboard.range(of: "onCloseInspector:") {
    let tail = dashboard[closeCallback.upperBound...].prefix(160)
    require(
        !tail.contains("workspaceDetailWidth = 0"),
        "onCloseInspector must not zero workspaceDetailWidth before hideWorkspaceSidebar — that skips the collapse animation"
    )
}

// --- 5. The file must be handed over immediately, not after the animation ---
// Delaying the post until the reveal settled meant the inspector slid open still
// showing the file list and swapped to the document ~0.45s later: the list
// visibly flashed first (user-reported 2026-07-26).
if let onChangeRange = dashboard.range(of: "gchOpenWorkspaceFilePreview") {
    let handoff = String(dashboard[..<onChangeRange.upperBound].suffix(900))
    require(
        !handoff.contains("asyncAfter"),
        "the preview request must be posted synchronously — a delay makes the file list flash before the document"
    )
}
require(
    dashboard.contains("GCHPendingFilePreview.request = previewRequest"),
    "the request must also be parked for the first open, when the pane is not mounted yet to receive the notification"
)
require(
    pane.contains("if let pending = GCHPendingFilePreview.take()"),
    "the pane must drain the parked request on appear, and taking it must clear it so a later remount cannot reopen a stale file"
)

// --- 6. No leftover diagnostics from chasing this bug ---
for (name, source) in [("DashboardView", dashboard), ("WorkspaceInspectorPane", pane)] {
    require(!source.contains("[CloseProbe]"), "\(name) still contains [CloseProbe] instrumentation")
}

print("verify_inspector_preview_dismissal: PASS")
