import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appURL = root.appendingPathComponent("OpenClawInstaller/App/OpenClawInstallerApp.swift")

guard let source = try? String(contentsOf: appURL, encoding: .utf8) else {
    fatalError("Could not read OpenClawInstallerApp.swift")
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func block(startingWith signature: String, in text: String) -> String {
    guard let start = text.range(of: signature) else {
        fatalError("Could not find \(signature)")
    }

    var depth = 0
    var hasEnteredBody = false
    var index = start.lowerBound

    while index < text.endIndex {
        let char = text[index]
        if char == "{" {
            depth += 1
            hasEnteredBody = true
        } else if char == "}" {
            depth -= 1
            if hasEnteredBody && depth == 0 {
                return String(text[start.lowerBound...index])
            }
        }
        index = text.index(after: index)
    }

    fatalError("Could not extract block for \(signature)")
}

let viewModeBlock = block(startingWith: "enum ViewMode", in: source)
// The switch over viewMode was extracted from `body` into `routedContent`.
let routedContentBlock = block(startingWith: "private var routedContent: some View", in: source)
let determineInitialViewBlock = block(startingWith: "private func determineInitialView()", in: source)

require(
    viewModeBlock.contains("case checking"),
    "MainContentView should have a checking startup mode before routing."
)
require(
    routedContentBlock.contains("case .checking:"),
    "MainContentView should render a checking state instead of flashing the install landing page."
)
require(
    determineInitialViewBlock.contains("await services.systemEnvironment.performFullCheck()"),
    "Startup routing should still perform the environment check before choosing a screen."
)
require(
    determineInitialViewBlock.contains("if services.systemEnvironment.openclawInfo != nil") &&
        determineInitialViewBlock.contains("viewMode = .dashboard"),
    "Startup routing should open Dashboard directly when OpenClaw is already installed."
)
require(
    determineInitialViewBlock.contains("else") &&
        determineInitialViewBlock.contains("viewMode = .initial"),
    "Startup routing should keep the install landing page for machines without OpenClaw."
)
require(
    !determineInitialViewBlock.contains("Always start on the initial landing page"),
    "Startup routing should not document or preserve the old always-initial behavior."
)

print("Direct dashboard launch verification passed")
