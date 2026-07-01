import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func exists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let assetBase = "OpenClawInstaller/Assets.xcassets"
let pluginBase = "\(assetBase)/PluginIcon.imageset"

for path in [
    "\(pluginBase)/Contents.json",
    "\(pluginBase)/plugin-day.svg",
    "\(pluginBase)/plugin-night.svg"
] {
    expect(exists(path), "\(path) is missing")
}

let pluginContents = read("\(pluginBase)/Contents.json")
expect(pluginContents.contains("plugin-day.svg"), "PluginIcon should reference the light SVG")
expect(pluginContents.contains("plugin-night.svg"), "PluginIcon should reference the dark SVG")
expect(pluginContents.contains(#""appearance" : "luminosity""#), "PluginIcon should switch by luminosity")

let pluginDay = read("\(pluginBase)/plugin-day.svg")
let pluginNight = read("\(pluginBase)/plugin-night.svg")
expect(pluginDay.contains(#"viewBox="0 0 24 24""#), "PluginIcon light SVG should use a crisp 24pt viewBox")
expect(pluginNight.contains(#"viewBox="0 0 24 24""#), "PluginIcon dark SVG should use a crisp 24pt viewBox")
expect(pluginDay.contains(##"fill="#151515""##), "PluginIcon light SVG should render dark")
expect(pluginNight.contains(##"fill="#ffffff""##), "PluginIcon dark SVG should render light")
expect(pluginDay.contains("C7.1 18.2 4.5 15.6 4.5 12.4"), "PluginIcon should use the custom plug body path")

let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let workspaceFolderIcon = read("OpenClawInstaller/Views/Shared/WorkspaceFolderIcon.swift")
let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")
expect(workspaceFolderIcon.contains("struct WorkspaceFolderIcon: View"), "shared folder icon component should exist")
expect(workspaceFolderIcon.contains("struct ClosedWorkspaceFolderShape: Shape"), "closed folder icon should be drawn as a SwiftUI Shape")
expect(workspaceFolderIcon.contains("struct OpenWorkspaceFolderShape: Shape"), "open folder icon should be drawn as a SwiftUI Shape")
expect(workspaceFolderIcon.contains("func path(in rect: CGRect) -> Path"), "folder icon shapes should render with Path")
expect(workspaceFolderIcon.contains("Path { path in"), "folder icon should draw explicit vector paths")
expect(workspaceFolderIcon.contains("StrokeStyle("), "folder icon should use stroked SF-like line art")
expect(workspaceFolderIcon.contains("lineCap: .round"), "folder icon strokes should use rounded caps")
expect(workspaceFolderIcon.contains("lineJoin: .round"), "folder icon strokes should use rounded joins")
expect(!workspaceFolderIcon.contains("Image(systemName:"), "shared folder icon should not render unavailable SF Symbols")
expect(!workspaceFolderIcon.contains("WorkspaceFolderOpenIcon") && !workspaceFolderIcon.contains("WorkspaceFolderClosedIcon"), "shared folder icon should not depend on asset catalog folder icons")
expect(!exists("\(assetBase)/WorkspaceFolderClosedIcon.imageset/folder-closed.png"), "closed folder icon should not depend on a PNG asset")
expect(!exists("\(assetBase)/WorkspaceFolderOpenIcon.imageset/folder-open.png"), "open folder icon should not depend on a PNG asset")
expect(workspaceFolderIcon.contains(".foregroundStyle(.secondary)"), "shared folder icon should use semantic color for light/dark mode")
expect(!workspaceFolderIcon.contains(".foregroundColor(.black)") && !workspaceFolderIcon.contains(".foregroundColor(.white)"), "shared folder icon should not hardcode light/dark colors")
expect(workspaceFolderIcon.contains(".frame(width: size, height: size)"), "shared folder icon should expose a reusable size")
expect(project.contains("WorkspaceFolderIcon.swift in Sources"), "WorkspaceFolderIcon should be part of the app target sources")
expect(dashboard.contains("private func workspaceItemIcon(item: FileItem, isExpanded: Bool) -> some View"), "WorkspaceFilePanel should render folders through a shared helper")
expect(dashboard.contains("WorkspaceFolderIcon(isExpanded: isExpanded, size: 20)"), "expanded folders should use the shared folder icon component")
expect(dashboard.contains("projectItemIcon(item: item, isExpanded: false)"), "search result directory rows should use the closed shared folder icon")
expect(dashboard.contains("WorkspaceFolderIcon(isExpanded: false, size: 20)"), "attachment directory previews should use the shared closed folder icon at 20pt")

let workspacePanel = slice(dashboard, from: "private struct WorkspaceFilePanel: View", to: "private struct CommitTextField")
expect(
    !workspacePanel.contains(#"Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(for: item.name))"#),
    "WorkspaceFilePanel should not use the old filled SF Symbol folder"
)

let attachmentPreview = slice(dashboard, from: "struct AttachmentPreview: View", to: "// MARK: - Success Toast")
expect(
    !attachmentPreview.contains(#""folder.fill""#),
    "AttachmentPreview should not use the old filled SF Symbol folder"
)

print("Sidebar plugin and folder icon verification passed")
