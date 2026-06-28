import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fail(message) }
}

let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let source = try String(contentsOf: sourceURL)

require(
    !source.contains("ChatScrollContentMetricsKey") &&
        !source.contains("ChatScrollViewportHeightKey"),
    "chat scroll should not continuously publish geometry preference metrics"
)
require(
    !source.contains("updateChatScrollMetricsIfNeeded(") &&
        !source.contains("updateChatScrollViewportHeightIfNeeded("),
    "chat scroll should not write geometry metrics back into @State"
)
require(
    !source.contains("chatScrollOffset") &&
        !source.contains("chatScrollViewportHeight") &&
        !source.contains("chatScrollContentHeight"),
    "chat scroll offset/height state should be removed with the preference metrics"
)
require(
    source.contains("showTransientChatScrollIndicator()"),
    "scroll indicator feedback should remain as a lightweight transient affordance"
)

print("Chat scroll geometry feedback loop is reduced")
