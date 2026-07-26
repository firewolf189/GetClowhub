import Foundation

// The right inspector must read and behave like the left NavigationSplitView
// column (user report 2026-07-26: "右侧的 sidebar 样式和交互应该跟左侧一样").
//
// Three differences existed, all verified on screen before/after:
//   1. Surface. The pane was chat-white; the left column is a very light grey.
//      Materials do not get there — the closest (.sidebar, withinWindow) renders
//      #DEDFE0 against the left column's #F7F7F7 — so the sampled tone is
//      painted directly, per appearance.
//   2. A drawn 1pt separator. The left edge has none; separation is the tone
//      change alone. NSBox needed BOTH its layer colour and its own border
//      cleared — clearing one left the hairline visible.
//   3. Resizing. The pan gesture sat on the 1pt separator with no cursor
//      feedback: technically draggable, practically not. It now lives on a
//      wider overlay strip that owns `NSCursor.resizeLeftRight`.

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
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

let split = read("OpenClawInstaller/Features/Workspace/Views/Inspector/RightInspectorSplitView.swift")
let pane = read("OpenClawInstaller/Features/Workspace/Views/Inspector/WorkspaceInspectorPane.swift")

// --- 1. The pane paints the sidebar tone, in both appearances ---
require(
    split.contains("private final class SidebarBackdropView: NSView"),
    "the inspector needs a backdrop that paints the sidebar tone"
)
require(
    split.contains("srgbRed: 0.973") && split.contains("srgbRed: 0.118"),
    "both the light and dark sidebar tones must be defined"
)
require(
    split.contains("override func viewDidChangeEffectiveAppearance()"),
    "a dynamic NSColor baked into a CGColor does not follow a light/dark switch — re-apply it"
)
require(
    !split.contains("NSColor(white: 0.9"),
    "use sRGB components: NSColor(white:) is calibrated grey and renders visibly darker on a P3 display"
)

// The tree surfaces must let that tone through; document surfaces stay opaque.
require(
    pane.components(separatedBy: ".background(Color.clear)").count >= 3,
    "the file tree panels must be transparent so the sidebar tone shows through"
)
require(
    pane.contains(".background(Color(NSColor.windowBackgroundColor))"),
    "the document preview should keep its own opaque surface"
)

// --- 2. No drawn line on this edge (the left column has none) ---
require(
    split.contains("sidebarSeparator.layer?.backgroundColor = NSColor.clear.cgColor")
        && split.contains("sidebarSeparator.borderWidth = 0"),
    "the separator must be invisible: NSBox draws its own border on top of the layer colour"
)

// --- 3. Resizing feels like the native divider ---
require(
    split.contains("private final class SidebarResizeHandleView: NSView"),
    "resizing needs a grab strip wider than the 1pt separator"
)
require(
    split.contains("sidebarResizeHandle.addGestureRecognizer(resizePan)")
        && !split.contains("sidebarSeparator.addGestureRecognizer"),
    "the pan gesture belongs on the handle, not on the hairline"
)
require(
    split.contains("addCursorRect(bounds, cursor: .resizeLeftRight)")
        && split.contains("NSCursor.resizeLeftRight.set()"),
    "the handle must show the resize cursor (cursor rect plus tracking area, so it works before the window is key)"
)
require(
    split.contains("let handleShouldHide = clampedWidth <= 0"),
    "a collapsed pane has no divider — the handle must not leave a resize cursor over the chat"
)

print("right-inspector sidebar parity guards hold")
