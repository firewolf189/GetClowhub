#!/usr/bin/env swift
import Foundation

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) throws -> String {
    let url = root.appendingPathComponent(path)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CheckFailure(description: "Missing expected file: \(path)")
    }
    return try String(contentsOf: url, encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw CheckFailure(description: message)
    }
}

do {
    let models = try read("OpenClawInstaller/Features/Chat/Models/ChatTimelineModels.swift")
    let chatView = try read("OpenClawInstaller/Features/Chat/Views/ChatView.swift")
    let timeline = try read("OpenClawInstaller/Features/Chat/Views/ChatTimelineSurface.swift")

    try require(
        models.contains("enum ChatTimelineScrollTarget"),
        "ChatTimelineScrollTarget should own the send/session bottom-scroll id."
    )
    try require(
        models.contains("return \"loading-\\(last.id)\""),
        "Loading placeholders must scroll to the loading- prefixed row id."
    )
    try require(
        timeline.contains(".id(\"loading-\\(loadingMsg.id)\")"),
        "ChatTimelineSurface loading rows must keep the loading- id prefix."
    )
    try require(
        chatView.contains("ChatTimelineScrollTarget.bottomAnchorId(from: currentMessages)"),
        "ChatView must scroll using the last real timeline row, not only chatBottom."
    )
    try require(
        chatView.contains("Do not scroll here: sendChatMessage has not appended"),
        "followChatBottomFromUserAction must not scroll before the new rows exist."
    )

    let helpers = try read("OpenClawInstaller/Features/Chat/ChatHelpers.swift")
    let rehydrate = try read("OpenClawInstaller/Features/Chat/State/GatewayTranscriptRehydrate.swift")
    guard let sendStart = helpers.range(of: "func sendChatMessage(_ text: String, attachments: [URL] = []) async") else {
        throw CheckFailure(description: "sendChatMessage missing")
    }
    let afterName = helpers.index(sendStart.lowerBound, offsetBy: 1)
    let nextFunc = helpers.range(of: "\n    func ", range: afterName..<helpers.endIndex)
    let sendBody = String(helpers[sendStart.lowerBound..<(nextFunc?.lowerBound ?? helpers.endIndex)])
    let placeholderAt = sendBody.range(of: "taskStatus: .loading")?.lowerBound
    let rehydrateAt = sendBody.range(of: "GatewayTranscriptRehydrate.ensurePriorTurnsPresent")?.lowerBound
    try require(
        placeholderAt != nil && rehydrateAt != nil && placeholderAt! < rehydrateAt!,
        "send must append the loading placeholder before jsonl rehydrate"
    )
    try require(
        sendBody.contains("Task.detached(priority: .userInitiated)"),
        "jsonl rehydrate must not run on the main actor during send"
    )
    try require(
        sendBody.contains("await Task.yield()"),
        "send must yield so SwiftUI can paint the new rows before disk work"
    )
    try require(
        rehydrate.contains("isLiveTranscriptFileName") &&
            rehydrate.contains("isResetArchiveFileName") &&
            rehydrate.contains("dropLast(6)"),
        "rehydrate must ignore *.trajectory.jsonl when scanning session files"
    )

    let followSliceStart = "private func followChatBottomFromUserAction()"
    guard let start = chatView.range(of: followSliceStart) else {
        throw CheckFailure(description: "followChatBottomFromUserAction missing")
    }
    let followBody = String(chatView[start.lowerBound...]).prefix(600)
    try require(
        !followBody.contains("scrollToBottomIfAllowed()"),
        "followChatBottomFromUserAction must not call scrollToBottomIfAllowed before append."
    )

    print("verify_send_message_no_white_flash: ok")
} catch {
    fputs("verify_send_message_no_white_flash: \(error)\n", stderr)
    exit(1)
}
