import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func expectAppearsInOrder(_ haystack: String, _ needles: [String], _ message: String) {
    var lowerBound = haystack.startIndex
    for needle in needles {
        guard let range = haystack[lowerBound...].range(of: needle) else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
        lowerBound = range.upperBound
    }
}

let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let sidebarRowContent = slice(dashboard, from: "private func sidebarRowContent", to: "private func sidebarIcon")
let agentSidebarRow = slice(dashboard, from: "private func agentSidebarRow", to: "private func sidebarItemHighlightColor")
let agentListRow = slice(dashboard, from: "private struct AgentListRow: View", to: "// MARK: - Pulsing Dot")

expect(
    sidebarRowContent.contains(".padding(.vertical, 7)"),
    "main sidebar rows should keep the current selected-background height"
)
expect(
    agentListRow.contains(".frame(height: 24)") && agentListRow.contains(".padding(.vertical, 4)"),
    "agent row content should stay at its current 32pt visual content height"
)
expect(
    !agentSidebarRow.contains(".padding(.horizontal, 8)\n            .padding(.vertical, 3)\n            .frame(maxWidth: .infinity, alignment: .leading)\n            .background("),
    "agent row external spacing must not be inside the selected background"
)
expectAppearsInOrder(
    agentSidebarRow,
    [
        ".padding(.horizontal, 8)",
        ".frame(maxWidth: .infinity, alignment: .leading)",
        ".background(",
        ".contentShape(Rectangle())",
        ".onTapGesture",
        ".onHover",
        ".padding(.vertical, 3)"
    ],
    "agent row vertical spacing should sit outside the selected background so the selected row height matches main sidebar rows"
)

print("Agent sidebar row height verification passed")
