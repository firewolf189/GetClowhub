import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fail(message) }
}

let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("OpenClawInstaller/Views/Dashboard/SelectableMarkdownView.swift")
let source = try String(contentsOf: sourceURL)

require(
    source.contains("markdownHTMLCache.countLimit") &&
        source.contains("markdownHTMLCache.totalCostLimit"),
    "HTML cache should have explicit count and total-cost limits"
)
require(
    source.contains("markdownHeightCache.countLimit"),
    "height cache should have an explicit count limit"
)
require(
    source.contains("setCachedMarkdownHTML("),
    "HTML cache writes should route through a cost-aware helper"
)
require(
    !source.contains("markdownHTMLCache.setObject(html as NSString, forKey: cacheKey)") &&
        !source.contains("markdownHTMLCache.setObject(fullHTML as NSString, forKey: cacheKey)"),
    "HTML cache writes should include cost instead of unbounded setObject calls"
)

print("Markdown WebView caches are bounded")
