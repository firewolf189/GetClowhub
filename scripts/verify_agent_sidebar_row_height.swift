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

let dashboard = read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let projectFolderRow = read("OpenClawInstaller/Features/Workspace/Views/ProjectWorkspace/AgentProjectFolderRow.swift")
let sidebarRowContent = slice(dashboard, from: "private func sidebarRowContent", to: "private func sidebarIcon")
// Agent rows are now rendered through the shared SidebarCollapsibleRow
// (AgentListRow was replaced in the collapsible-sidebar refactor).
let agentSidebarRow = slice(dashboard, from: "private func agentSidebarRow", to: "private func canDeleteAgent")
let collapsibleRowContent = slice(
    dashboard,
    from: "struct SidebarCollapsibleRow<Icon: View, Actions: View, Children: View>: View",
    to: "private var chevron: some View"
)

expect(
    sidebarRowContent.contains(".padding(.vertical, 7)"),
    "main sidebar rows should keep the current selected-background height"
)
expect(
    agentSidebarRow.contains("rowHeight: 24") && agentSidebarRow.contains("verticalPadding: 4"),
    "agent rows should stay at 24pt content + 4pt vertical padding = the 32pt height that matches main sidebar rows"
)
expect(
    projectFolderRow.contains("rowHeight: 24") && projectFolderRow.contains("verticalPadding: 4"),
    "project rows should stay at 24pt content + 4pt vertical padding = the same 32pt height as agent and session rows"
)
expectAppearsInOrder(
    collapsibleRowContent,
    [
        ".frame(height: rowHeight)",
        ".padding(.horizontal, 8)",
        ".padding(.vertical, verticalPadding)",
        ".frame(maxWidth: .infinity, alignment: .leading)",
        ".contentShape(Rectangle())",
        ".background(",
        ".onTapGesture",
        ".onHover"
    ],
    "collapsible agent row should size its content to rowHeight and include the vertical padding inside the selected background so the highlighted row height matches main sidebar rows"
)

print("Agent sidebar row height verification passed")
