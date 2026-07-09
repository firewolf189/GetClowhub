#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboardURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Features")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("DashboardView.swift")
let accessoryURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Features")
    .appendingPathComponent("Workspace")
    .appendingPathComponent("Views")
    .appendingPathComponent("Inspector")
    .appendingPathComponent("RightInspectorTitlebarAccessory.swift")
let projectURL = root
    .appendingPathComponent("OpenClawInstaller.xcodeproj")
    .appendingPathComponent("project.pbxproj")

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

func readRequired(_ url: URL, _ message: String) -> String {
    guard FileManager.default.fileExists(atPath: url.path) else {
        fail(message)
    }
    do {
        return try String(contentsOf: url, encoding: .utf8)
    } catch {
        fail("Could not read \(url.path): \(error)")
    }
}

let dashboard = readRequired(dashboardURL, "DashboardView.swift must exist.")
let accessory = readRequired(
    accessoryURL,
    "Right inspector titlebar accessory should live in Features/Workspace/Views/Inspector."
)
let project = readRequired(projectURL, "project.pbxproj must exist.")

let forbiddenDashboardSymbols = [
    "DashboardTitlebarAccessoryInstaller",
    "DashboardTitlebarAccessoryCoordinator",
    "RightOutputsTitlebarAccessory",
    "rightOutputsTitlebarAccessoryID"
]

for symbol in forbiddenDashboardSymbols {
    require(
        !dashboard.contains(symbol),
        "DashboardView.swift should not own right inspector titlebar accessory symbol \(symbol)."
    )
}

require(
    dashboard.contains("RightInspectorTitlebarAccessoryInstaller(") &&
        dashboard.contains("RightInspectorTitlebarAccessory("),
    "Dashboard should only compose the right inspector titlebar accessory."
)

require(
    accessory.contains("import SwiftUI") &&
        accessory.contains("import AppKit") &&
        accessory.contains("private let rightInspectorTitlebarAccessoryID") &&
        accessory.contains("struct RightInspectorTitlebarAccessoryInstaller<Accessory: View>: NSViewRepresentable") &&
        accessory.contains("final class RightInspectorTitlebarAccessoryCoordinator") &&
        accessory.contains("NSTitlebarAccessoryViewController") &&
        accessory.contains("static func dismantleNSView(_ nsView: NSView, coordinator: RightInspectorTitlebarAccessoryCoordinator)") &&
        accessory.contains("coordinator.remove()"),
    "Right inspector titlebar accessory should contain the narrow AppKit bridge and teardown lifecycle."
)

require(
    accessory.contains("guard let targetWindow else { return }") &&
        !accessory.contains("guard isVisible, let targetWindow else") &&
        accessory.contains("applyVisibility(") &&
        accessory.contains("targetWidth = isVisible ? max(width, 44) : 0") &&
        accessory.contains("hostingController.view.isHidden = !isVisible") &&
        accessory.contains("RightInspectorSplitMetrics.animationDuration"),
    "Right inspector titlebar accessory should hide/collapse in place while preserving the existing split animation timing."
)

require(
    accessory.contains("struct RightInspectorTitlebarAccessory: View") &&
        accessory.contains("Image(systemName: \"terminal\")") &&
        accessory.contains("Image(systemName: \"sidebar.right\")") &&
        accessory.contains(".unifiedTitlebarTooltip"),
    "Right inspector titlebar accessory view should keep the terminal and right sidebar controls."
)

require(
    project.contains("RightInspectorTitlebarAccessory.swift in Sources") &&
        project.contains("OpenClawInstaller/Features/Workspace/Views/Inspector/RightInspectorTitlebarAccessory.swift"),
    "RightInspectorTitlebarAccessory.swift should be part of the Xcode target."
)

print("Right inspector titlebar accessory boundary verification passed")
