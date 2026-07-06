import Foundation

// This guard exercises the real ChatSessionSearch app logic. `swift` can only
// interpret a single file, so we compile the app source together with an
// embedded behavioral driver via swiftc and run the result.

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appSources = [
    "OpenClawInstaller/Features/Sessions/Models/ChatSessionSearch.swift",
]

let driverSource = #"""
import Foundation

struct ChatSessionMetadata: Identifiable, Equatable {
    let id: UUID
    let agentId: String
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messageCount: Int
    var isPinned: Bool
    var isArchived: Bool
}

extension ChatSessionMetadata: ChatSessionSearchable {}

@main
struct GlobalSessionSearchVerification {
    static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }

    static func main() {
        let now = Date()
        let mainSession = ChatSessionMetadata(
            id: UUID(),
            agentId: "main",
            title: "Project Research",
            createdAt: now.addingTimeInterval(-400),
            updatedAt: now.addingTimeInterval(-100),
            messageCount: 3,
            isPinned: false,
            isArchived: false
        )
        let ux = ChatSessionMetadata(
            id: UUID(),
            agentId: "ux",
            title: "Project Search Overlay",
            createdAt: now.addingTimeInterval(-300),
            updatedAt: now.addingTimeInterval(-50),
            messageCount: 5,
            isPinned: false,
            isArchived: false
        )
        let archived = ChatSessionMetadata(
            id: UUID(),
            agentId: "writer",
            title: "Project Archive",
            createdAt: now.addingTimeInterval(-200),
            updatedAt: now,
            messageCount: 2,
            isPinned: false,
            isArchived: true
        )

        let results = ChatSessionSearch.search([mainSession, ux, archived], query: "project")
        guard results.map(\.id) == [ux.id, mainSession.id] else {
            fail("global search should return matching unarchived sessions from all agents, newest first")
        }

        let recent = ChatSessionSearch.search([mainSession, ux, archived], query: "")
        guard recent.map(\.id) == [ux.id, mainSession.id] else {
            fail("empty global search should show recent unarchived sessions from all agents")
        }

        print("Global session search verification passed")
    }
}
"""#

let fm = FileManager.default
let workDir = fm.temporaryDirectory
    .appendingPathComponent("verify_global_session_search-\(UUID().uuidString)")
try! fm.createDirectory(at: workDir, withIntermediateDirectories: true)
let driverURL = workDir.appendingPathComponent("driver.swift")
try! driverSource.write(to: driverURL, atomically: true, encoding: .utf8)
let binaryURL = workDir.appendingPathComponent("verify")

@discardableResult
func run(_ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    do { try process.run() } catch {
        fputs("FAIL: could not launch \(arguments[0]): \(error)\n", stderr)
        exit(1)
    }
    process.waitUntilExit()
    return process.terminationStatus
}

var compileArgs = ["swiftc"]
compileArgs += appSources.map { repoRoot.appendingPathComponent($0).path }
compileArgs += [driverURL.path, "-o", binaryURL.path]
if run(compileArgs) != 0 {
    fputs("FAIL: ChatSessionSearch app source + verification driver no longer compile\n", stderr)
    try? fm.removeItem(at: workDir)
    exit(1)
}
let status = run([binaryURL.path])
try? fm.removeItem(at: workDir)
exit(status)
