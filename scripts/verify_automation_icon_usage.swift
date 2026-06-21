import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let fileManager = FileManager.default
let assetSet = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Assets.xcassets")
    .appendingPathComponent("AutomationIcon.imageset")
let contents = assetSet.appendingPathComponent("Contents.json")
let daySVG = assetSet.appendingPathComponent("automation-day.svg")
let nightSVG = assetSet.appendingPathComponent("automation-night.svg")

expect(fileManager.fileExists(atPath: contents.path), "AutomationIcon asset catalog is missing")
expect(fileManager.fileExists(atPath: daySVG.path), "AutomationIcon light SVG is missing")
expect(fileManager.fileExists(atPath: nightSVG.path), "AutomationIcon dark SVG is missing")

let contentsText = read("OpenClawInstaller/Assets.xcassets/AutomationIcon.imageset/Contents.json")
expect(contentsText.contains("automation-day.svg"), "AutomationIcon does not reference the light SVG")
expect(contentsText.contains("automation-night.svg"), "AutomationIcon does not reference the dark SVG")
expect(contentsText.contains(#""appearance" : "luminosity""#), "AutomationIcon must switch by luminosity")

let dayText = read("OpenClawInstaller/Assets.xcassets/AutomationIcon.imageset/automation-day.svg")
let nightText = read("OpenClawInstaller/Assets.xcassets/AutomationIcon.imageset/automation-night.svg")
expect(dayText.contains(#"viewBox="0 0 256 256""#), "AutomationIcon light SVG should preserve the provided 256 viewBox")
expect(nightText.contains(#"viewBox="0 0 256 256""#), "AutomationIcon dark SVG should preserve the provided 256 viewBox")
expect(dayText.contains("M 60.269 30.771"), "AutomationIcon light SVG should use the provided automation path")
expect(nightText.contains("M 60.269 30.771"), "AutomationIcon dark SVG should use the provided automation path")
expect(dayText.contains("fill: rgb(0,0,0)") || dayText.contains("fill=\"#000000\""), "AutomationIcon light SVG should render black")
expect(nightText.contains("fill: rgb(255,255,255)") || nightText.contains("fill=\"#ffffff\""), "AutomationIcon dark SVG should render white")
expect(dayText.contains(#"<circle cx="45.084" cy="44.915" r="41.4""#), "AutomationIcon light outer border should be an explicit stroked circle")
expect(nightText.contains(#"<circle cx="45.084" cy="44.915" r="41.4""#), "AutomationIcon dark outer border should be an explicit stroked circle")
expect(dayText.contains(#"stroke-width="7.2""#), "AutomationIcon light outer border should stay visible in the sidebar")
expect(nightText.contains(#"stroke-width="7.2""#), "AutomationIcon dark outer border should stay visible in the sidebar")

let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
expect(dashboard.contains(#"navRow(.tasksLogs, title: String(localized: "Automation", bundle: languageManager.localizedBundle), systemImage: "checklist", assetImage: "AutomationIcon")"#), "Automation nav row must use the AutomationIcon asset")
expect(dashboard.contains("sidebarIcon(systemImage: systemImage, assetImage: assetImage)"), "sidebar rows must route through the shared icon renderer")
expect(dashboard.contains("Image(assetImage)"), "DashboardView must render sidebar asset images")
expect(dashboard.contains(".frame(width: 18, height: 18)"), "AutomationIcon should be constrained to the sidebar icon slot")

print("Automation icon usage verification passed")
