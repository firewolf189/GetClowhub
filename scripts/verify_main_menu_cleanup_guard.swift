#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appDelegatePath = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("AppDelegate.swift")

guard let source = try? String(contentsOf: appDelegatePath, encoding: .utf8) else {
    fputs("FAIL: could not read \(appDelegatePath.path)\n", stderr)
    exit(1)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source[startRange.upperBound...].range(of: end) else {
        fputs("FAIL: could not slice AppDelegate.swift between \(start) and \(end)\n", stderr)
        exit(1)
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

let willUpdate: String
if source.contains("func applicationWillUpdate") {
    willUpdate = slice(
        from: "func applicationWillUpdate",
        to: "// MARK: - Main Menu Cleanup"
    )
} else {
    willUpdate = ""
}
let cleanup = slice(
    from: "private func cleanupMainMenu()",
    to: "func applicationWillTerminate"
)

require(
    !willUpdate.contains("cleanupMainMenu()"),
    "applicationWillUpdate must not repeatedly mutate the SwiftUI/AppKit main menu."
)
require(
    source.contains("private func removeItemIfPresent("),
    "AppDelegate should use an idempotent helper before removing NSMenuItem instances."
)
require(
    !cleanup.contains("mainMenu.removeItem(item)") &&
        !cleanup.contains("appMenu.removeItem(item)"),
    "cleanupMainMenu must not call removeItem(_:) with potentially stale NSMenuItem references."
)
require(
    cleanup.contains("removeItemIfPresent(item, from: mainMenu)") &&
        cleanup.contains("removeItemIfPresent(item, from: appMenu)"),
    "cleanupMainMenu should route menu item removals through the safe helper."
)
require(
    source.contains("menu.index(of: item)") &&
        source.contains("menu.removeItem(at: index)"),
    "safe menu removal should re-check the item's current index before removing it."
)

print("Main menu cleanup guard verification passed")
