#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let overlayPath = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Shared")
    .appendingPathComponent("CursorDotOverlay.swift")
let dashboardPath = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("DashboardView.swift")
let projectPath = root
    .appendingPathComponent("OpenClawInstaller.xcodeproj")
    .appendingPathComponent("project.pbxproj")

func read(_ url: URL) -> String {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fputs("FAIL: could not read \(url.path)\n", stderr)
        exit(1)
    }
    return text
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fputs("FAIL: could not slice source between \(start) and \(end)\n", stderr)
        exit(1)
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let overlay = read(overlayPath)
let dashboard = read(dashboardPath)
let project = read(projectPath)
let chatScrollContent = slice(
    dashboard,
    from: "private func chatScrollContent(proxy: ScrollViewProxy) -> some View",
    to: "/// Filtered slash commands based on current input"
)
let chatBubble = slice(
    dashboard,
    from: "struct ChatBubble: View",
    to: "private struct InlineUserMessageEditor: View"
)

require(
    overlay.contains("struct CursorDotOverlay: View") &&
        overlay.contains("struct CursorDotOverlayModifier: ViewModifier"),
    "Cursor dot should expose a reusable SwiftUI overlay and modifier."
)
require(
    overlay.contains("struct CursorDotConfiguration") &&
        overlay.contains("dotSize: CGFloat = 5") &&
        overlay.contains("ringSize: CGFloat = 20") &&
        overlay.contains("smoothing: CGFloat = 0.18"),
    "Cursor dot configuration should keep the fixed 5px dot, 20px ring, and trailing motion."
)
require(
    overlay.contains("NSViewRepresentable") &&
        overlay.contains("NSTrackingArea") &&
        overlay.contains("mouseMoved(with event: NSEvent)") &&
        overlay.contains("NSCursor.hide()") &&
        overlay.contains("NSCursor.unhide()"),
    "Cursor dot should use a narrow AppKit bridge for pointer tracking and native cursor visibility."
)
require(
    overlay.contains("func cursorDotDisabledRegion") &&
        overlay.contains("CursorDotDisabledPreferenceKey") &&
        overlay.contains("disabledFrames"),
    "Expensive message/WebView regions should be able to opt out of the cursor-dot overlay."
)
require(
    !overlay.contains("ringHoverSize") &&
        !overlay.contains("ringHoverColor") &&
        !overlay.contains("ringHoverFill") &&
        !overlay.contains("isHoveringTarget") &&
        !overlay.contains("CursorDotHoverPreferenceKey") &&
        !overlay.contains("cursorDotHoverTarget"),
    "Cursor dot should stay at the fixed default size and must not define hover expansion state."
)
require(
    !overlay.contains("contentView.hitTest") &&
        !overlay.contains("accessibilityRole()") &&
        !overlay.contains("isInteractiveTarget(at:") &&
        !overlay.contains("usesNativeCursor(at:"),
    "Cursor tracking should not run automatic AppKit hit-test or accessibility scans on every mouse move."
)
require(
    overlay.contains(".allowsHitTesting(false)") &&
        overlay.contains("TimelineView(.animation)") &&
        overlay.contains("accessibilityHidden(true)"),
    "Cursor visuals should not intercept clicks, should animate smoothly, and should stay hidden from accessibility."
)
require(
    dashboard.contains(".cursorDotOverlay(isEnabled: true)"),
    "Dashboard should install the cursor-dot overlay."
)
require(
    !dashboard.contains(".cursorDotHoverTarget()"),
    "Dashboard controls should not request cursor-dot hover expansion."
)
require(
    chatScrollContent.contains(".cursorDotDisabledRegion()"),
    "The central chat message scroll region should use the normal system cursor."
)
require(
    !chatBubble.contains(".cursorDotDisabledRegion()"),
    "Individual ChatBubble rows should not each emit cursor disabled frames; disable the central message region once."
)
require(
    project.contains("CursorDotOverlay.swift in Sources") &&
        project.contains("CursorDotOverlay.swift"),
    "Xcode project should include CursorDotOverlay.swift in the Shared group and app target sources."
)

print("Cursor dot overlay verification passed")
