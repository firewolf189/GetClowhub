import Foundation

// Math must render from assets INSIDE the app.
//
// Until 2026-07-26 the chat's WebView document loaded MathJax from jsdelivr plus
// a polyfill.io script. Consequences:
//   * formulas never rendered on a blocked/slow network (jsdelivr is unreliable
//     from mainland China — the same reason zenmux needed a HK proxy),
//   * the WebView measured its height before the async renderer had run, so math
//     bubbles were mis-sized,
//   * polyfill.io is a domain with a known supply-chain incident, and WebKit
//     needs no ES6 polyfill in the first place.
//
// Replacement: KaTeX in Resources/KaTeX, inlined into the document only when the
// content actually contains math. It renders synchronously during page parse.

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

let markdownHTML = read("OpenClawInstaller/Features/Chat/Markdown/MarkdownHTML.swift")
let webView = read("OpenClawInstaller/Features/Chat/Markdown/SelectableMarkdownView.swift")
let pane = read("OpenClawInstaller/Features/Workspace/Views/Inspector/WorkspaceInspectorPane.swift")
let pbxproj = read("OpenClawInstaller.xcodeproj/project.pbxproj")

// --- 1. The assets ship with the app ---
let assets = [
    "OpenClawInstaller/Resources/KaTeX/katex.min.js",
    "OpenClawInstaller/Resources/KaTeX/auto-render.min.js",
    "OpenClawInstaller/Resources/KaTeX/katex-inline.css",
    "OpenClawInstaller/Resources/KaTeX/KaTeX-LICENSE",
]
for asset in assets {
    require(
        FileManager.default.fileExists(atPath: root.appendingPathComponent(asset).path),
        "missing bundled math asset: \(asset)"
    )
}
require(
    pbxproj.contains("/* KaTeX */ = {isa = PBXFileReference; lastKnownFileType = folder; path = KaTeX;")
        && pbxproj.contains("/* KaTeX in Resources */"),
    "the KaTeX folder must be registered as a copied resource, or the app ships without it"
)

// Fonts must be embedded in the CSS: `loadHTMLString` has no base URL, so a
// relative fonts/ reference would silently fall back to system glyphs.
let css = read("OpenClawInstaller/Resources/KaTeX/katex-inline.css")
require(css.contains("data:font/woff2;base64,"), "KaTeX fonts must be inlined as data URIs")
require(!css.contains("url(fonts/"), "KaTeX CSS must not reference font files relatively")

// --- 2. No document may fetch a renderer at display time ---
for (name, source) in [("MarkdownHTML", markdownHTML), ("WorkspaceInspectorPane", pane)] {
    require(!source.contains("cdn.jsdelivr.net"), "\(name) must not load anything from jsdelivr")
    require(!source.contains("polyfill.io/v3"), "\(name) must not load polyfill.io (supply-chain incident, and unnecessary)")
    require(!source.contains("<script src="), "\(name) must not pull remote scripts into a rendered document")
}
require(
    !markdownHTML.contains("window.MathJax"),
    "the MathJax configuration should be gone along with MathJax itself"
)

// --- 3. Inlined only when there IS math (360 KB of fonts otherwise) ---
require(
    markdownHTML.contains("static func containsMath(_ content: String) -> Bool"),
    "MarkdownHTML should expose the math pre-check"
)
require(
    markdownHTML.components(separatedBy: "guard MarkdownHTML.containsMath(markdown), isAvailable else { return \"\" }").count == 3,
    "both the style and script tags must be gated on the content actually containing math"
)
require(
    markdownHTML.contains("\\(MathRenderAssets.styleTag(for: markdown))")
        && markdownHTML.contains("\\(MathRenderAssets.scriptTag(for: markdown))"),
    "the chat document should inject the bundled math assets"
)
require(
    pane.contains("MathRenderAssets.styleTag(for: markdown)")
        && pane.contains("MathRenderAssets.scriptTag(for: markdown)"),
    "the file preview should render math with the same bundled assets"
)

// --- 4. A single `$` is NOT a math delimiter (currency) ---
require(
    !markdownHTML.contains("{left: \"$\", right: \"$\""),
    "single-$ inline math turns prices like \"$5 … $10\" into LaTeX errors mid-sentence"
)
require(
    markdownHTML.contains("{left: \"$$\", right: \"$$\", display: true}"),
    "display math should keep the $$ delimiter"
)

// --- 5. Streaming body patches must re-render math ---
require(
    webView.contains("window.__gchRenderMath"),
    "after replacing document.body.innerHTML the delta path must re-render math"
)
require(
    !webView.contains("MathJax.typesetPromise"),
    "the MathJax re-typeset call should be gone"
)

// --- 6. Math documents must not evict the ordinary HTML cache ---
require(
    webView.contains("guard !html.contains(\"__gchRenderMath\") else { return }"),
    "a math document carries ~660 KB inline; caching those would evict every ordinary message from the 8 MB budget"
)

print("bundled math renderer guards hold: KaTeX ships with the app, nothing is fetched at render time")
