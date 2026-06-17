import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboardURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/DashboardView.swift")

guard let dashboard = try? String(contentsOf: dashboardURL, encoding: .utf8) else {
    fatalError("Could not read DashboardView.swift")
}

func assertContains(_ needle: String, _ message: String) {
    guard dashboard.contains(needle) else {
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

let typography = slice(
    dashboard,
    from: "private enum DashboardTypography",
    to: "private enum DashboardSidebarMetrics"
)

guard typography.contains("static let message = Font.system(size: 14, weight: .regular)") else {
    fatalError("Assistant message text should use 14pt regular system typography")
}

guard typography.contains("static let userMessage = Font.system(size: 14, weight: .regular)") else {
    fatalError("User message text should match assistant message typography")
}

assertContains(
    "return requiresWebView(content) ? .webView : .native",
    "Complex Markdown such as tables should still upgrade to WKWebView"
)

print("Chat typography verification passed")
