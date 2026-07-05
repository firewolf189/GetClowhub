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

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
// Agent session rows now expand/collapse inside SidebarCollapsibleRow.
// Ghosting during collapse is prevented by clipping the animated child
// block (and the whole row container) instead of an asymmetric transition.
let collapsibleRowBody = slice(
    dashboard,
    from: "struct SidebarCollapsibleRow<Icon: View, Actions: View, Children: View>: View",
    to: "private var rowContent: some View"
)
let expandedChildrenBlock = slice(
    collapsibleRowBody,
    from: "if isExpanded {",
    to: ".animation(Self.expansionAnimation, value: isExpanded)"
)

assertContains(
    expandedChildrenBlock,
    ".transition(Self.childTransition)",
    "session rows should keep a soft insertion transition when expanding"
)
assertContains(
    expandedChildrenBlock,
    ".clipped()",
    "collapsing agent session rows must clip the animated child block so old titles cannot ghost outside the row"
)
assertContains(
    collapsibleRowBody,
    ".animation(Self.expansionAnimation, value: isExpanded)",
    "expansion animation should be driven by the isExpanded state"
)
let afterAnimation = slice(
    collapsibleRowBody,
    from: ".animation(Self.expansionAnimation, value: isExpanded)",
    to: "}"
)
assertContains(
    afterAnimation,
    ".clipped()",
    "the whole collapsible row container must also be clipped during collapse to avoid ghosting"
)

print("Agent session collapse ghosting checks passed")
