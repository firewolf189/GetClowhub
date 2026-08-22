#!/usr/bin/env swift

import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let workDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("verify_dingtalk_channel_config-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
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

let management = read("OpenClawInstaller/Features/Channels/Core/ChannelManagement.swift")
guard management.contains("DingTalkChannelConfig.defaultAccountConfig"),
      management.contains("sanitizeRejectedDingTalkKeysIfNeeded"),
      management.contains("DingTalkChannelConfig.resolvedConfigKey(in: channels)"),
      management.contains("resolvedChannelWriteKey"),
      !management.contains("\"enableAICard\": false") else {
    fail("channel add/load must stop writing rejected DingTalk keys and reuse an existing DingTalk object")
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = [
    "swiftc",
    repoRoot.appendingPathComponent("OpenClawInstaller/Features/Channels/Models/DingTalkChannelConfig.swift").path,
    repoRoot.appendingPathComponent("Tests/DingTalkChannelConfigTests.swift").path,
    "-o",
    binary.path,
]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fail("DingTalkChannelConfig tests failed to compile")
}

let run = Process()
run.executableURL = binary
try run.run()
run.waitUntilExit()
guard run.terminationStatus == 0 else {
    fail("DingTalkChannelConfig tests failed")
}

print("PASS: dingtalk channel config")
