import Foundation

// Guards "open a file, see it render ONCE".
//
// Two defects made a file preview render twice (2026-07-26):
//   1. `updateNSView` reloaded the document on EVERY SwiftUI update of the
//      panel. Opening a file produced one load in makeNSView plus one reload
//      from the first update — two visible renders, measured.
//   2. The markdown document pulled marked.min.js from a CDN and parsed in JS,
//      so the page first painted unparsed and re-rendered when the request
//      returned — and never rendered at all on a blocked network. It also meant
//      every file preview phoned out.
//
// Both are easy to reintroduce: an unguarded `updateNSView` looks harmless, and
// a <script src> is the shortest path to a markdown renderer.

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

func slice(_ text: String, from start: String, to end: String) -> String {
    guard let startRange = text.range(of: start),
          let endRange = text[startRange.upperBound...].range(of: end) else {
        fputs("FAIL: could not slice from \(start) to \(end)\n", stderr)
        exit(1)
    }
    return String(text[startRange.lowerBound..<endRange.lowerBound])
}

let pane = read("OpenClawInstaller/Features/Workspace/Views/Inspector/WorkspaceInspectorPane.swift")

let markdownPreview = slice(pane, from: "private struct MarkdownPreviewView", to: "// MARK: - HTML Preview")
let htmlPreview = slice(pane, from: "private struct HTMLPreviewView", to: "private struct QuickLookPreview")
let quickLook = slice(pane, from: "private struct QuickLookPreview", to: "/// Payload for `.gchOpenWorkspaceFilePreview`")

// --- 1. No preview may reload unconditionally from updateNSView ---
require(
    markdownPreview.contains("guard coordinator.loadedMarkdown != markdown || coordinator.loadedIsDark != isDark else {"),
    "markdown preview must skip the reload when neither content nor appearance changed"
)
require(
    htmlPreview.contains("guard coordinator.loadedURL != fileURL else { return }"),
    "html preview must skip the reload when the file has not changed"
)
require(
    quickLook.contains("guard (nsView.previewItem as? URL) != url else { return }"),
    "QuickLook must not re-assign the same preview item (it restarts the render)"
)

// --- 2. The document must be self-contained ---
require(
    !markdownPreview.contains("<script"),
    "the markdown preview document must not run scripts — parse natively before loading"
)
require(
    !markdownPreview.contains("cdn.") && !markdownPreview.contains("https://"),
    "the markdown preview must not fetch anything remote: it renders late (or never) on a blocked network"
)
require(
    markdownPreview.contains("MarkdownHTML.convertMarkdown(markdown)"),
    "markdown should be converted with the same native converter the chat uses"
)
require(
    !markdownPreview.contains("marked.parse"),
    "marked.js must not come back"
)

print("workspace preview single-render guards hold")
