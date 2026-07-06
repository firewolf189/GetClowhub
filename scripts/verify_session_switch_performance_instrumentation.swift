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

let dashboard = read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let viewModel = read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")
let store = read("OpenClawInstaller/Features/Sessions/Services/ChatSessionStore.swift")

assertContains(
    viewModel,
    #"private let sessionSwitchPerfLog = Logger(subsystem: "com.openclaw.installer", category: "SessionSwitchPerformance")"#,
    "view model should have a dedicated session switch performance logger"
)
assertContains(
    store,
    #"private let perfLog = Logger(subsystem: "com.openclaw.installer", category: "SessionSwitchPerformance")"#,
    "session store should log cold-load performance to the shared category"
)
let assistantRenderer = read("OpenClawInstaller/Features/Chat/Markdown/AssistantMessageRenderer.swift")
assertContains(
    assistantRenderer,
    #"let chatRenderPerfLog = Logger(subsystem: "com.openclaw.installer", category: "SessionSwitchPerformance")"#,
    "chat render code should log render-side performance to the shared category"
)
assertContains(
    dashboard,
    "chatRenderPerfLog.info(",
    "chat view should log render-side performance to the shared logger"
)
assertContains(
    viewModel,
    "let switchStart = ContinuousClock.now",
    "session switching should capture a start timestamp"
)
assertContains(
    viewModel,
    #"source=inactive_stash"#,
    "session switching should identify inactive-stash warm loads"
)
assertContains(
    viewModel,
    #"source=memory_cache"#,
    "session switching should identify LRU cache loads"
)
assertContains(
    viewModel,
    #"source=cold_disk_start"#,
    "session switching should identify cold disk loads"
)
assertContains(
    viewModel,
    #"source=cold_disk_finish"#,
    "session switching should log cold load completion"
)
assertContains(
    store,
    #"loadSessionAsync start"#,
    "session store should log async load start"
)
assertContains(
    store,
    #"loadSessionAsync finish"#,
    "session store should log async load finish"
)
assertContains(
    dashboard,
    "renderObservationStartBySession",
    "chat view should track render observation start by session"
)
assertContains(
    dashboard,
    #"phase=messages_count_changed"#,
    "chat view should log when the rendered message count changes"
)
assertContains(
    dashboard,
    #"phase=scheduled_bottom_scroll"#,
    "chat view should log scheduled bottom scroll checkpoints"
)

print("Session switch performance instrumentation checks passed")
