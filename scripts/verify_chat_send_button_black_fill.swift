import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func require(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let dashboard = read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let composer = read("OpenClawInstaller/Features/Chat/Views/ChatComposerView.swift")

let fillColor = slice(
    dashboard,
    from: "private var sendButtonFillColor: SwiftUI.Color",
    to: "    private var sendButtonIconColor: SwiftUI.Color"
)
let iconColor = slice(
    dashboard,
    from: "private var sendButtonIconColor: SwiftUI.Color",
    to: "    /// Whether the input area"
)

require(
    fillColor.contains("canSend || shouldShowStopButton"),
    "send and stop states must share the same active fill branch"
)
require(
    fillColor.contains("? Color.black"),
    "send and stop buttons must use black active fill"
)
require(
    fillColor.contains(": Color(NSColor.quaternaryLabelColor)"),
    "disabled send button fill must stay muted"
)
require(
    !fillColor.contains("Color.primary.opacity(0.62)") && !fillColor.contains("Color.accentColor"),
    "send button active fill must not use low-contrast gray or accent blue"
)
require(
    iconColor.contains("? Color(NSColor.windowBackgroundColor)"),
    "active send and stop icons must stay readable on black fill"
)
require(
    composer.contains(#"Image(systemName: shouldShowStopButton ? "square.fill" : "arrow.up")"#),
    "composer primary button must still switch between send and stop icons"
)

print("Chat send button black fill verification passed")
