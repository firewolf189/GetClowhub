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
let closedFolderBase = "\(assetBase)/WorkspaceFolderClosedIcon.imageset"
let openFolderBase = "\(assetBase)/WorkspaceFolderOpenIcon.imageset"

for path in [
    "\(pluginBase)/Contents.json",
    "\(pluginBase)/plugin-day.svg",
    "\(pluginBase)/plugin-night.svg",
    "\(closedFolderBase)/Contents.json",
    "\(closedFolderBase)/folder-closed-day.svg",
    "\(closedFolderBase)/folder-closed-night.svg",
    "\(openFolderBase)/Contents.json",
    "\(openFolderBase)/folder-open-day.svg",
    "\(openFolderBase)/folder-open-night.svg"
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

for (base, dayName, nightName) in [
    (closedFolderBase, "folder-closed-day.svg", "folder-closed-night.svg"),
    (openFolderBase, "folder-open-day.svg", "folder-open-night.svg")
] {
    let contents = read("\(base)/Contents.json")
    expect(contents.contains(dayName), "\(base) should reference the light SVG")
    expect(contents.contains(nightName), "\(base) should reference the dark SVG")
    expect(contents.contains(#""appearance" : "luminosity""#), "\(base) should switch by luminosity")
}

let closedDay = read("\(closedFolderBase)/folder-closed-day.svg")
let closedNight = read("\(closedFolderBase)/folder-closed-night.svg")
let openDay = read("\(openFolderBase)/folder-open-day.svg")
let openNight = read("\(openFolderBase)/folder-open-night.svg")
expect(closedDay.contains(##"stroke="#4f5750""##), "closed folder light SVG should use a dark outline")
expect(closedNight.contains(##"stroke="#f2f2f2""##), "closed folder dark SVG should use a light outline")
expect(openDay.contains(##"stroke="#4f5750""##), "open folder light SVG should use a dark outline")
expect(openNight.contains(##"stroke="#f2f2f2""##), "open folder dark SVG should use a light outline")
expect(closedDay.contains(#"d="M4 8.2"#), "closed folder should use the custom closed-folder outline")
expect(openDay.contains(#"d="M3.6 10.2"#), "open folder should use the custom open-folder front outline")

let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let workspaceFolderIcon = read("OpenClawInstaller/Views/Shared/WorkspaceFolderIcon.swift")
let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")
expect(
    dashboard.contains(#"navRow(.plugins, title: String(localized: "Plugins", bundle: languageManager.localizedBundle), systemImage: "puzzlepiece.fill", assetImage: "PluginIcon")"#),
    "Plugins nav row should use PluginIcon"
)
expect(workspaceFolderIcon.contains("struct WorkspaceFolderIcon: View"), "shared folder icon component should exist")
expect(workspaceFolderIcon.contains(#"Image(isExpanded ? "WorkspaceFolderOpenIcon" : "WorkspaceFolderClosedIcon")"#), "shared folder icon should render the asset catalog folder icons")
expect(workspaceFolderIcon.contains(".frame(width: size, height: size)"), "shared folder icon should expose a reusable size")
expect(project.contains("WorkspaceFolderIcon.swift in Sources"), "WorkspaceFolderIcon should be part of the app target sources")
expect(dashboard.contains("private func workspaceItemIcon(item: FileItem, isExpanded: Bool) -> some View"), "WorkspaceFilePanel should render custom folder assets through a helper")
expect(dashboard.contains("WorkspaceFolderIcon(isExpanded: isExpanded, size: 20)"), "expanded folders should use the shared folder icon component")
expect(dashboard.contains("workspaceItemIcon(item: item, isExpanded: false)"), "search result directory rows should use the closed-folder asset")
expect(dashboard.contains("WorkspaceFolderIcon(isExpanded: false, size: 20)"), "attachment directory previews should use the shared closed-folder asset at 20pt")

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
expect(
    attachmentPreview.contains("private var attachmentTypeLabel: String"),
    "AttachmentPreview should show a compact file type label"
)
expect(
    attachmentPreview.contains("HStack(alignment: .center, spacing: 10)"),
    "AttachmentPreview non-image chips should use a tighter horizontal upload-card layout"
)
expect(
    attachmentPreview.contains(".fill(Color.primary.opacity(0.045))"),
    "AttachmentPreview should use the subtle gray upload-card background"
)
expect(
    attachmentPreview.contains(".stroke(Color.secondary.opacity(0.12), lineWidth: 1)"),
    "AttachmentPreview should use a subtle gray border"
)
expect(
    attachmentPreview.contains(".frame(width: 206, height: 56)"),
    "AttachmentPreview non-image chips should be compact low-profile horizontal cards"
)
expect(
    dashboard.contains(".padding(.top, attachedFiles.isEmpty ? 8 : 2)"),
    "Composer input should reduce the gap below attachments"
)

print("Sidebar plugin and folder icon verification passed")
