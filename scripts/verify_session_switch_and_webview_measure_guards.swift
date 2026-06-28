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

func slice(_ text: String, from start: String, to end: String) -> String {
    guard let startRange = text.range(of: start),
          let endRange = text.range(of: end, range: startRange.upperBound..<text.endIndex) else {
        fatalError("Could not slice \(start) -> \(end)")
    }
    return String(text[startRange.lowerBound..<endRange.lowerBound])
}

let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let viewModel = read("OpenClawInstaller/ViewModels/DashboardViewModel.swift")
let selectableMarkdown = read("OpenClawInstaller/Views/Dashboard/SelectableMarkdownView.swift")
let switchSession = slice(
    viewModel,
    from: "func switchSession(to sessionId: UUID)",
    to: "/// Switch to a session that may belong to a different agent."
)
let measureHeight = slice(
    selectableMarkdown,
    from: "private func measureHeight(webView: WKWebView, attempt: Int)",
    to: "/// Re-measure height"
)

assertContains(
    switchSession,
    #"if oldSid == sessionId"#,
    "switchSession should skip when the target session is already active"
)
assertContains(
    switchSession,
    #"switchSession skipped reason=same_session"#,
    "same-session skips should be logged for performance diagnosis"
)
assertContains(
    switchSession,
    #"return"#,
    "same-session guard should return before flushing/reassigning messages"
)

assertContains(
    measureHeight,
    "let frameWidth = webView.bounds.width",
    "WebView measurement should inspect native frame width before JS height measurement"
)
assertContains(
    measureHeight,
    "guard frameWidth > 10 else",
    "WebView measurement should defer when native width is not ready"
)
assertContains(
    measureHeight,
    #"phase=webview_measure_deferred"#,
    "width-not-ready deferrals should be logged separately from JS measurement retries"
)
assertContains(
    measureHeight,
    "DispatchQueue.main.asyncAfter(deadline: .now() + 0.12)",
    "width-not-ready deferral should use a short layout retry instead of repeated JS measurement"
)

print("Session switch and WebView measurement guard checks passed")
