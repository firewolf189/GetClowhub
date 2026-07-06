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

func optionalSlice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        return ""
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let dashboard = read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let assistantRenderer = read("OpenClawInstaller/Features/Chat/Markdown/AssistantMessageRenderer.swift")

let agentSidebarRow = slice(
    dashboard,
    from: "private func agentSidebarRow(_ agent: AgentOption) -> some View",
    to: "private func agentRowWithContextMenu(_ agent: AgentOption) -> some View"
)
let toggleAgentSelection = slice(
    dashboard,
    from: "private func toggleAgentSelection(_ agent: AgentOption)",
    to: "private func createSession(for agent: AgentOption)"
)
let sessionRowTap = slice(
    dashboard,
    from: "private func sessionRows(",
    to: ".contextMenu {"
)
let chatBubble = slice(
    dashboard,
    from: "struct ChatBubble: View",
    to: "// MARK: - Typewriter Text for Streaming"
)

assertContains(
    agentSidebarRow,
    "isExpanded: expandedAgentIds.contains(agent.id)",
    "expanded agent sessions should render from expansion state alone"
)
assertNotContains(
    agentSidebarRow,
    "isExpanded: expandedAgentIds.contains(agent.id) && viewModel.selectedAgentId == agent.id",
    "expanding/collapsing an agent should not require selecting that agent"
)
assertNotContains(
    agentSidebarRow,
    "isExpanded: expandedAgentIds.contains(agent.id) && selectedTab == .chat",
    "expanding/collapsing an agent should not require switching to the chat tab"
)
assertNotContains(
    toggleAgentSelection,
    "viewModel.selectedAgentId = agent.id",
    "clicking an agent row should not switch the right-side conversation"
)
assertNotContains(
    toggleAgentSelection,
    "selectedTab = .chat",
    "clicking an agent row should not force the chat tab"
)
assertContains(
    sessionRowTap,
    "viewModel.switchSession(to: meta.id)",
    "clicking a concrete session should still switch the right-side conversation"
)
assertContains(
    sessionRowTap,
    "selectedTab = .chat",
    "clicking a concrete session should still move the detail pane to chat"
)

assertContains(
    chatBubble,
    "AssistantMessageContentView(",
    "assistant bubbles should route through the hybrid native/WK renderer"
)
assertNotContains(
    chatBubble,
    "SelectableMarkdownView(content: message.content)",
    "assistant bubbles should not mount WKWebView for every assistant message by default"
)
assertContains(
    assistantRenderer,
    "private static func requiresWebView",
    "hybrid renderer should centralize the complex-content fallback decision"
)
assertContains(
    assistantRenderer,
    "NativeSelectableMarkdownView(",
    "hybrid renderer should use native direct-selection text for ordinary assistant content"
)
assertContains(
    assistantRenderer,
    "case .webViewFallback:\n            SelectableMarkdownView(",
    "hybrid renderer should retain WKWebView for complex assistant content"
)
assertContains(
    assistantRenderer,
    "containsMarkdownTable",
    "hybrid renderer should treat markdown tables as complex content"
)
assertContains(
    assistantRenderer,
    "containsMathSyntax",
    "hybrid renderer should treat math syntax as complex content"
)
assertContains(
    assistantRenderer,
    "containsHTMLBlock",
    "hybrid renderer should treat raw HTML blocks as complex content"
)

print("Agent click and hybrid rendering verification passed")
