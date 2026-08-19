import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let workDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("verify_cron_conversation-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
let binary = workDir.appendingPathComponent("verify")

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

func read(_ path: String) -> String {
    let url = repoRoot.appendingPathComponent(path)
    guard let value = try? String(contentsOf: url, encoding: .utf8) else {
        fail("could not read \(path)")
    }
    return value
}

let management = read("OpenClawInstaller/Features/Cron/CronManagement.swift")
let sheet = read("OpenClawInstaller/Features/Cron/Views/CronTabView.swift")
guard management.contains("bindCronConversation"),
      management.contains("openCronConversation"),
      management.contains("hydrateCronConversation"),
      sheet.contains(#".tag("conversation")"#),
      sheet.contains("openCronConversation") else {
    fail("cron jobs must bind a stable chat session and offer Open chat")
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = [
    "swiftc",
    repoRoot.appendingPathComponent("OpenClawInstaller/Features/Cron/Models/CronJobInfo.swift").path,
    repoRoot.appendingPathComponent("Tests/CronConversationBindingTests.swift").path,
    "-o",
    binary.path,
]
try! process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fail("CronConversationBinding tests no longer compile")
}

let run = Process()
run.executableURL = binary
try! run.run()
run.waitUntilExit()
try? FileManager.default.removeItem(at: workDir)
exit(run.terminationStatus)
