import SwiftUI
import AppKit
import WebKit
import Quartz
import Foundation

struct WorkspaceSidebarRoot: Equatable, Hashable {
    let displayName: String
    let path: String
    let isProjectBound: Bool
}

private enum WorkspaceDetailMode: Equatable {
    case none
    case filePreview(String)
    case projectTree
}

private struct WorkspaceOutputsPaneHeader: View {
    let isProjectFilesVisible: Bool
    let openFolder: () -> Void
    let toggleProjectFiles: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(I18n.t("workspace.outputs.title"))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            WorkspaceHeaderIconButton(action: openFolder, help: I18n.t("workspace.outputs.openInFinder")) {
                OpenWorkspaceInFinderIcon()
                    .foregroundColor(.secondary)
            }

            WorkspaceHeaderIconButton(
                action: toggleProjectFiles,
                help: isProjectFilesVisible ? I18n.t("workspace.outputs.hideProjectFiles") : I18n.t("workspace.outputs.showProjectFiles")
            ) {
                SecondaryProjectSidebarIcon()
                    .foregroundColor(isProjectFilesVisible ? .accentColor : .secondary)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 44)
    }
}

private struct WorkspaceHeaderIconButton<Icon: View>: View {
    let action: () -> Void
    let help: String
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.clear
                icon()
            }
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .unifiedTooltip(UnifiedTooltipContent(title: help))
    }
}

private struct OpenWorkspaceInFinderIcon: View {
    var body: some View {
        let stroke = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
        ZStack {
            OpenWorkspaceInFinderOutlineShape()
                .stroke(style: stroke)
                .opacity(0.78)
            OpenWorkspaceInFinderFoldShape()
                .stroke(style: stroke)
                .opacity(0.78)
        }
        .frame(width: 22, height: 22)
    }
}

private struct OpenWorkspaceInFinderOutlineShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 22
        let scaleY = rect.height / 22

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scaleX, y: rect.minY + y * scaleY)
        }

        var path = Path()
        path.move(to: point(7.5, 4.5))
        path.addLine(to: point(13.5, 4.5))
        path.addLine(to: point(17.5, 8.5))
        path.addLine(to: point(17.5, 17.5))
        path.addQuadCurve(to: point(16, 19), control: point(17.5, 19))
        path.addLine(to: point(6, 19))
        path.addQuadCurve(to: point(4.5, 17.5), control: point(4.5, 19))
        path.addLine(to: point(4.5, 6))
        path.addQuadCurve(to: point(6, 4.5), control: point(4.5, 4.5))
        path.closeSubpath()
        return path
    }
}

private struct OpenWorkspaceInFinderFoldShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 22
        let scaleY = rect.height / 22

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scaleX, y: rect.minY + y * scaleY)
        }

        var path = Path()
        path.move(to: point(13.5, 4.75))
        path.addLine(to: point(13.5, 8.5))
        path.addLine(to: point(17.25, 8.5))
        return path
    }
}

private struct SecondaryProjectSidebarIcon: View {
    var body: some View {
        let stroke = StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round)
        ZStack {
            SecondaryProjectSidebarBackShape()
                .stroke(style: stroke)
                .opacity(0.62)

            SecondaryProjectSidebarFrontShape()
                .stroke(style: stroke)
                .opacity(0.92)
        }
        .frame(width: 22, height: 22)
    }
}

private struct SecondaryProjectSidebarBackShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 22
        let scaleY = rect.height / 22

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scaleX, y: rect.minY + y * scaleY)
        }

        var path = Path()
        path.move(to: point(8.5, 4.45))
        path.addQuadCurve(to: point(10.45, 3.35), control: point(9.1, 3.65))
        path.addLine(to: point(15.75, 3.35))
        path.addQuadCurve(to: point(18.65, 6.25), control: point(18.65, 3.35))
        path.addLine(to: point(18.65, 15.1))
        path.addQuadCurve(to: point(15.75, 18), control: point(18.65, 18))
        path.addLine(to: point(14.25, 18))
        return path
    }
}

private struct SecondaryProjectSidebarFrontShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 22
        let scaleY = rect.height / 22
        let roundedRect = CGRect(
            x: rect.minX + 3.65 * scaleX,
            y: rect.minY + 6.85 * scaleY,
            width: 9.85 * scaleX,
            height: 12.95 * scaleY
        )
        return Path(roundedRect: roundedRect, cornerRadius: 2.7 * min(scaleX, scaleY))
    }
}

struct WorkspaceInspectorPane: View {
    let root: WorkspaceSidebarRoot
    let browserWidth: CGFloat
    let editorWidth: CGFloat
    let onDetailWidthChanged: (CGFloat) -> Void
    let openFolder: () -> Void

    @Environment(\.rightInspectorSidebarWidthCoordinator) private var sidebarWidthCoordinator

    @State private var editingFilePath: String?
    @State private var detailMode: WorkspaceDetailMode = .none
    @State private var targetDetailMode: WorkspaceDetailMode = .none
    @State private var previewReturnMode: WorkspaceDetailMode = .none
    @State private var editingFileDirty = false
    @State private var searchText = ""
    @State private var visualDetailWidth: CGFloat = 0
    @State private var committedDetailWidth: CGFloat = 0
    @State private var renderedDetailMode: WorkspaceDetailMode = .none
    @State private var detailAnimationGeneration = 0

    private var isProjectFilesVisible: Bool {
        detailMode == .projectTree || targetDetailMode == .projectTree || renderedDetailMode == .projectTree
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceOutputsPaneHeader(
                isProjectFilesVisible: isProjectFilesVisible,
                openFolder: openFolder,
                toggleProjectFiles: toggleWorkspaceProjectFiles
            )

            Divider()

            GeometryReader { proxy in
                let layout = WorkspaceInspectorContentLayout(
                    availableWidth: proxy.size.width,
                    preferredPrimaryWidth: browserWidth,
                    preferredSecondaryWidth: visualDetailWidth
                )

                WorkspaceInspectorContentSplit(
                    totalWidth: layout.totalWidth,
                    primaryWidth: layout.primaryWidth,
                    secondaryWidth: layout.secondaryWidth
                ) {
                    WorkspaceFilePanel(
                        root: root,
                        editingFilePath: $editingFilePath,
                        onOpenFile: openWorkspaceFile,
                        onCloseFile: closeWorkspaceDetail,
                        editingFileDirty: editingFileDirty,
                        width: layout.primaryWidth
                    )
                } secondary: {
                    detailPanel(width: layout.secondaryContentWidth)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .onAppear {
            syncDetailWidth(visualDetailWidth, animated: false)
        }
        .onChange(of: root) { _ in
            clearWorkspaceDetail(animated: false)
        }
    }

    @ViewBuilder
    private func detailPanel(width: CGFloat) -> some View {
        Group {
            switch renderedDetailMode {
            case .filePreview(let path):
                FileEditorPanel(
                    filePath: path,
                    onClose: closeWorkspacePreview,
                    onDirtyChanged: { dirty in
                        editingFileDirty = dirty
                    }
                )
                .id(path)
            case .projectTree:
                ProjectFilesPanel(
                    root: root,
                    selectedFilePath: $editingFilePath,
                    searchText: $searchText,
                    width: width,
                    onOpenFile: openWorkspaceFile
                )
            case .none:
                EmptyView()
            }
        }
    }

    private func openWorkspaceFile(_ path: String) {
        editingFilePath = path
        previewReturnMode = isProjectFilesVisible ? .projectTree : .none
        editingFileDirty = false
        requestWorkspaceDetail(.filePreview(path))
    }

    private func closeWorkspaceDetail() {
        clearWorkspaceDetail(animated: true)
    }

    private func toggleWorkspaceProjectFiles() {
        if isProjectFilesVisible {
            clearWorkspaceDetail(animated: true)
        } else {
            editingFilePath = nil
            previewReturnMode = .none
            editingFileDirty = false
            requestWorkspaceDetail(.projectTree)
        }
    }

    private func clearWorkspaceDetail(animated: Bool) {
        targetDetailMode = .none
        editingFilePath = nil
        previewReturnMode = .none
        editingFileDirty = false

        if animated {
            requestWorkspaceDetail(.none) {
                searchText = ""
            }
        } else {
            detailMode = .none
            renderedDetailMode = .none
            visualDetailWidth = 0
            committedDetailWidth = 0
            searchText = ""
            syncDetailWidth(0, animated: false)
        }
    }

    private func closeWorkspacePreview() {
        let returnMode = previewReturnMode
        editingFilePath = nil
        previewReturnMode = .none
        editingFileDirty = false

        if returnMode == .projectTree {
            requestWorkspaceDetail(returnMode)
        } else {
            clearWorkspaceDetail(animated: true)
        }
    }

    private func requestWorkspaceDetail(_ nextMode: WorkspaceDetailMode, completion: (() -> Void)? = nil) {
        targetDetailMode = nextMode

        if nextMode == .none {
            if renderedDetailMode == .none {
                renderedDetailMode = detailMode
            }
        } else {
            if renderedDetailMode != nextMode {
                renderedDetailMode = nextMode
            }
        }

        let targetWidth: CGFloat = nextMode == .none ? 0 : editorWidth
        animateDetailWidth(to: targetWidth) {
            detailMode = nextMode
            completion?()
            if nextMode == .none {
                renderedDetailMode = .none
            } else {
                renderedDetailMode = nextMode
            }
        }
    }

    private func animateDetailWidth(to targetWidth: CGFloat, completion: (() -> Void)? = nil) {
        let sanitizedWidth = max(0, targetWidth)
        detailAnimationGeneration += 1
        let animationID = detailAnimationGeneration

        if sanitizedWidth > 0 {
            visualDetailWidth = sanitizedWidth
        }
        syncDetailWidth(sanitizedWidth, animated: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + RightInspectorSplitMetrics.animationDuration) {
            guard detailAnimationGeneration == animationID else { return }
            if sanitizedWidth == 0 {
                visualDetailWidth = 0
            }
            committedDetailWidth = sanitizedWidth
            onDetailWidthChanged(committedDetailWidth)
            completion?()
        }
    }

    private func syncDetailWidth(_ detailWidth: CGFloat, animated: Bool) {
        let sanitizedWidth = max(0, detailWidth)

        if animated {
            sidebarWidthCoordinator.animateSidebarWidth(browserWidth + sanitizedWidth)
        }

        if !animated {
            committedDetailWidth = sanitizedWidth
            onDetailWidthChanged(committedDetailWidth)
        }
    }
}

private struct WorkspaceInspectorContentLayout {
    let totalWidth: CGFloat
    let primaryWidth: CGFloat
    let secondaryWidth: CGFloat
    let secondaryContentWidth: CGFloat

    init(
        availableWidth: CGFloat,
        preferredPrimaryWidth: CGFloat,
        preferredSecondaryWidth: CGFloat
    ) {
        let availableWidth = max(0, availableWidth)
        let preferredPrimaryWidth = max(0, preferredPrimaryWidth)
        let preferredSecondaryWidth = max(0, preferredSecondaryWidth)

        guard preferredSecondaryWidth > 0 else {
            let primaryWidth = min(preferredPrimaryWidth, availableWidth)
            self.totalWidth = primaryWidth
            self.primaryWidth = primaryWidth
            self.secondaryWidth = 0
            self.secondaryContentWidth = 0
            return
        }

        let targetTotalWidth = availableWidth
        let availableSecondaryWidth = max(0, targetTotalWidth - preferredPrimaryWidth)
        let targetSecondaryWidth = min(preferredSecondaryWidth, availableSecondaryWidth)
        let primaryWidth = max(0, targetTotalWidth - targetSecondaryWidth)
        let secondaryWidth = targetSecondaryWidth

        self.totalWidth = primaryWidth + secondaryWidth
        self.primaryWidth = primaryWidth
        self.secondaryWidth = secondaryWidth
        self.secondaryContentWidth = max(0, secondaryWidth - (secondaryWidth > 0 ? 1 : 0))
    }
}

private struct WorkspaceInspectorContentSplit<Primary: View, Secondary: View>: View {
    let totalWidth: CGFloat
    let primaryWidth: CGFloat
    let secondaryWidth: CGFloat
    let primary: Primary
    let secondary: Secondary

    init(
        totalWidth: CGFloat,
        primaryWidth: CGFloat,
        secondaryWidth: CGFloat,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.totalWidth = totalWidth
        self.primaryWidth = primaryWidth
        self.secondaryWidth = secondaryWidth
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        HStack(spacing: 0) {
            primary
                .frame(width: primaryWidth)
                .frame(maxHeight: .infinity, alignment: .top)

            if secondaryWidth > 0 {
                Rectangle()
                    .fill(Color(NSColor.separatorColor))
                    .frame(width: 1)

                secondary
                    .frame(width: max(secondaryWidth - 1, 0), alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipped()
            }
        }
        .frame(width: totalWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }
}

private struct WorkspaceFilePanel: View {
    let root: WorkspaceSidebarRoot
    @Binding var editingFilePath: String?
    let onOpenFile: (String) -> Void
    let onCloseFile: () -> Void
    let editingFileDirty: Bool
    let width: CGFloat

    private static let hiddenAgentConfigFileNames: Set<String> = [
        "AGENTS.md", "IDENTITY.md", "SOUL.md", "MEMORY.md",
        "USER.md", "BOOTSTRAP.md", "HEARTBEAT.md", "TOOLS.md"
    ]
    private static let outputContainerTokens: Set<String> = [
        "output", "outputs", "artifact", "artifacts", "result", "results",
        "report", "reports", "generated", "generation", "export", "exports",
        "log", "logs", "patch", "patches", "diff", "diffs",
        "screenshot", "screenshots"
    ]
    private static let outputFileTokens: Set<String> = [
        "output", "outputs", "artifact", "result", "results", "report",
        "review", "audit", "summary", "generated", "patch", "diff", "log",
        "screenshot", "image", "figure"
    ]
    private static let standaloneOutputExtensions: Set<String> = [
        "pdf", "patch", "diff", "log"
    ]

    private var workspacePath: String { root.path }

    var body: some View {
        EditableWorkspaceFileTreePanel(
            rootPath: workspacePath,
            selectedFilePath: $editingFilePath,
            editingFileDirty: editingFileDirty,
            width: width,
            searchText: .constant(""),
            searchDepthLimit: nil,
            expandRootOnAppear: false,
            isHiddenItemName: isHiddenWorkspaceItem,
            shouldShowItem: shouldShowOutputItem,
            onOpenFile: onOpenFile,
            onCloseSelectedFile: onCloseFile
        ) {
            outputsEmptyState
        }
    }

    private var outputsEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.65))
            Text(I18n.t("workspace.outputs.empty"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func isHiddenWorkspaceItem(name: String) -> Bool {
        name.hasPrefix(".") || Self.hiddenAgentConfigFileNames.contains(name)
    }

    private func shouldShowOutputItem(_ item: FileItem) -> Bool {
        if item.isDirectory {
            return isOutputContainerName(item.name)
                || isInsideOutputContainer(item.path)
                || directoryContainsOutputArtifact(item.path, remainingDepth: 3)
        }

        return isOutputFile(name: item.name, path: item.path)
    }

    private func isOutputFile(name: String, path: String) -> Bool {
        if isInsideOutputContainer(path) { return true }
        if Self.outputFileTokens.contains(where: { name.lowercased().contains($0) }) { return true }

        let ext = (name as NSString).pathExtension.lowercased()
        return Self.standaloneOutputExtensions.contains(ext)
    }

    private func isOutputContainerName(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return Self.outputContainerTokens.contains { normalized.contains($0) }
    }

    private func isInsideOutputContainer(_ path: String) -> Bool {
        let relativePath = path.replacingOccurrences(of: workspacePath + "/", with: "")
        let components = relativePath.split(separator: "/").map(String.init)
        guard components.count > 1 else { return false }
        return components.dropLast().contains { isOutputContainerName($0) }
    }

    private func directoryContainsOutputArtifact(_ directory: String, remainingDepth: Int) -> Bool {
        guard remainingDepth > 0 else { return false }
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory) else { return false }

        for name in names {
            if isHiddenWorkspaceItem(name: name) { continue }
            let fullPath = (directory as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)

            if isDir.boolValue {
                if isOutputContainerName(name) || directoryContainsOutputArtifact(fullPath, remainingDepth: remainingDepth - 1) {
                    return true
                }
            } else if isOutputFile(name: name, path: fullPath) {
                return true
            }
        }

        return false
    }
}

private struct ProjectFilesPanel: View {
    let root: WorkspaceSidebarRoot
    @Binding var selectedFilePath: String?
    @Binding var searchText: String
    let width: CGFloat
    let onOpenFile: (String) -> Void

    @FocusState private var isSearchFocused: Bool

    private static let hiddenNames: Set<String> = [
        ".git", ".svn", ".hg", ".DS_Store", "node_modules", ".build",
        "DerivedData", ".next", ".turbo", ".cache", "dist", "build"
    ]

    private var workspacePath: String { root.path }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            workspaceRootHeader
            searchField
            Divider()

            EditableWorkspaceFileTreePanel(
                rootPath: workspacePath,
                selectedFilePath: $selectedFilePath,
                editingFileDirty: false,
                width: width,
                searchText: $searchText,
                searchDepthLimit: 5,
                expandRootOnAppear: true,
                isHiddenItemName: isHiddenProjectItem,
                shouldShowItem: { _ in true },
                onOpenFile: onOpenFile,
                onCloseSelectedFile: {}
            ) {
                emptyState
            }
        }
        .frame(width: width)
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: root) { _ in searchText = "" }
    }

    private var workspaceRootHeader: some View {
        HStack(spacing: 8) {
            SecondaryProjectSidebarIcon()
                .foregroundColor(root.isProjectBound ? .accentColor : .secondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(root.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(root.isProjectBound ? root.path : I18n.format("workspace.files.fallbackPath", root.path))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            TextField(I18n.t("workspace.files.filterPlaceholder"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isSearchFocused)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("common.action.clear", fallback: "Clear")))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onAppear {
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.65))
            Text(I18n.t("workspace.files.empty"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func isHiddenProjectItem(name: String) -> Bool {
        name.hasPrefix(".") || Self.hiddenNames.contains(name)
    }
}

private struct EditableWorkspaceFileTreePanel<EmptyState: View>: View {
    let rootPath: String
    @Binding var selectedFilePath: String?
    let editingFileDirty: Bool
    let width: CGFloat
    @Binding var searchText: String
    let searchDepthLimit: Int?
    let expandRootOnAppear: Bool
    let isHiddenItemName: (String) -> Bool
    let shouldShowItem: (FileItem) -> Bool
    let onOpenFile: (String) -> Void
    let onCloseSelectedFile: () -> Void
    let emptyState: EmptyState

    @State private var expandedFolders: Set<String> = []
    @State private var renamingPath: String?
    @State private var renamingText = ""
    @State private var newItemParent: String?
    @State private var newItemIsFolder = false
    @State private var newItemName = ""
    @State private var clipboardPath: String?
    @State private var clipboardIsCut = false
    @State private var deleteConfirmPath: String?
    @State private var refreshTrigger = 0

    private static var newItemPlaceholderName: String { "__new_item_placeholder__" }

    init(
        rootPath: String,
        selectedFilePath: Binding<String?>,
        editingFileDirty: Bool,
        width: CGFloat,
        searchText: Binding<String>,
        searchDepthLimit: Int?,
        expandRootOnAppear: Bool,
        isHiddenItemName: @escaping (String) -> Bool,
        shouldShowItem: @escaping (FileItem) -> Bool,
        onOpenFile: @escaping (String) -> Void,
        onCloseSelectedFile: @escaping () -> Void,
        @ViewBuilder emptyState: () -> EmptyState
    ) {
        self.rootPath = rootPath
        self._selectedFilePath = selectedFilePath
        self.editingFileDirty = editingFileDirty
        self.width = width
        self._searchText = searchText
        self.searchDepthLimit = searchDepthLimit
        self.expandRootOnAppear = expandRootOnAppear
        self.isHiddenItemName = isHiddenItemName
        self.shouldShowItem = shouldShowItem
        self.onOpenFile = onOpenFile
        self.onCloseSelectedFile = onCloseSelectedFile
        self.emptyState = emptyState()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                let query = normalizedSearchText
                if query.isEmpty {
                    let visibleItems = buildVisibleItems(root: rootPath, depth: 0)
                    if visibleItems.isEmpty {
                        emptyState
                    } else {
                        ForEach(visibleItems, id: \.item.path) { entry in
                            fileRowView(item: entry.item, depth: entry.depth)
                        }
                    }
                    if newItemParent == rootPath {
                        newItemInputRow(depth: 0)
                    }
                } else {
                    let results = searchFiles(root: rootPath, query: query)
                    if results.isEmpty {
                        emptySearchState
                    } else {
                        ForEach(results, id: \.path) { item in
                            searchResultRow(item)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .id(refreshTrigger)
        .frame(width: width)
        .background(Color(NSColor.windowBackgroundColor))
        .alert(I18n.t("common.action.delete"), isPresented: Binding<Bool>(
            get: { deleteConfirmPath != nil },
            set: { if !$0 { deleteConfirmPath = nil } }
        )) {
            Button(I18n.t("common.action.delete"), role: .destructive) {
                if let path = deleteConfirmPath {
                    performDelete(path: path)
                }
                deleteConfirmPath = nil
            }
            Button(I18n.t("common.action.cancel"), role: .cancel) {
                deleteConfirmPath = nil
            }
        } message: {
            if let path = deleteConfirmPath {
                Text(I18n.format("workspace.files.deleteConfirm", (path as NSString).lastPathComponent))
            }
        }
        .onAppear {
            if expandRootOnAppear {
                expandedFolders.insert(rootPath)
            }
        }
        .onChange(of: rootPath) { newRootPath in
            expandedFolders = expandRootOnAppear ? [newRootPath] : []
            renamingPath = nil
            newItemParent = nil
            deleteConfirmPath = nil
            clipboardPath = nil
            refreshTrigger += 1
        }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var emptySearchState: some View {
        Text(I18n.t("workspace.files.noMatches"))
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
    }

    private struct DepthItem {
        let item: FileItem
        let depth: Int
    }

    private func buildVisibleItems(root: String, depth: Int) -> [DepthItem] {
        var result: [DepthItem] = []
        for item in listDirectory(root) {
            result.append(DepthItem(item: item, depth: depth))
            if item.isDirectory && expandedFolders.contains(item.path) {
                result.append(contentsOf: buildVisibleItems(root: item.path, depth: depth + 1))
                if newItemParent == item.path {
                    result.append(DepthItem(
                        item: FileItem(
                            name: Self.newItemPlaceholderName,
                            path: item.path + "/__new_item__",
                            isDirectory: false
                        ),
                        depth: depth + 1
                    ))
                }
            }
        }
        return result
    }

    @ViewBuilder
    private func fileRowView(item: FileItem, depth: Int) -> some View {
        if item.name == Self.newItemPlaceholderName {
            newItemInputRow(depth: depth)
        } else {
            fileRowContent(item: item, depth: depth, relativePath: nil)
        }
    }

    private func fileRowContent(item: FileItem, depth: Int, relativePath: String?) -> some View {
        let isExpanded = expandedFolders.contains(item.path)
        let isSelected = selectedFilePath == item.path
        let isDirtyFile = isSelected && editingFileDirty
        let isRenaming = renamingPath == item.path

        return Group {
            if isRenaming {
                renameRow(item: item, depth: depth, isExpanded: isExpanded)
            } else {
                Button(action: { activate(item: item, isExpanded: isExpanded) }) {
                    WorkspaceFileTreeRow(
                        item: item,
                        depth: depth,
                        isExpanded: isExpanded,
                        isSelected: isSelected,
                        isDirty: isDirtyFile,
                        relativePath: relativePath
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    fileContextMenu(item: item)
                }
            }
        }
    }

    private func renameRow(item: FileItem, depth: Int, isExpanded: Bool) -> some View {
        HStack(spacing: 6) {
            if item.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 16)
            } else {
                Spacer().frame(width: 16)
            }

            WorkspaceFileItemIcon(item: item, isExpanded: isExpanded)

            CommitTextField(
                text: $renamingText,
                onCommit: { value in performRename(oldPath: item.path, newName: value) },
                onCancel: { renamingPath = nil; refreshTrigger += 1 }
            )
            .frame(height: 22)

            Spacer()
        }
        .padding(.leading, CGFloat(depth) * 16 + 12)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.15))
        .cornerRadius(4)
    }

    @ViewBuilder
    private func fileContextMenu(item: FileItem) -> some View {
        Button {
            let parent = item.isDirectory ? item.path : (item.path as NSString).deletingLastPathComponent
            beginNewItem(parent: parent, isFolder: false)
        } label: {
            Label(I18n.t("workspace.files.newFile"), systemImage: "doc.badge.plus")
        }

        Button {
            let parent = item.isDirectory ? item.path : (item.path as NSString).deletingLastPathComponent
            beginNewItem(parent: parent, isFolder: true)
        } label: {
            Label(I18n.t("workspace.files.newFolder"), systemImage: "folder.badge.plus")
        }

        Divider()

        Button {
            renamingText = item.name
            renamingPath = item.path
            refreshTrigger += 1
        } label: {
            Label(I18n.t("common.action.rename"), systemImage: "pencil")
        }

        Divider()

        Button {
            clipboardPath = item.path
            clipboardIsCut = true
        } label: {
            Label(I18n.t("workspace.files.cut"), systemImage: "scissors")
        }

        Button {
            clipboardPath = item.path
            clipboardIsCut = false
        } label: {
            Label(I18n.t("workspace.files.copy"), systemImage: "doc.on.doc")
        }

        if item.isDirectory, let clip = clipboardPath, !clip.isEmpty {
            Button {
                performPaste(into: item.path)
            } label: {
                Label(I18n.t("workspace.files.paste"), systemImage: "doc.on.clipboard")
            }
        }

        Divider()

        Button(role: .destructive) {
            deleteConfirmPath = item.path
        } label: {
            Label(I18n.t("common.action.delete"), systemImage: "trash")
        }
    }

    private func newItemInputRow(depth: Int) -> some View {
        HStack(spacing: 6) {
            Spacer().frame(width: 16)
            Image(systemName: newItemIsFolder ? "folder.badge.plus" : "doc.badge.plus")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
            CommitTextField(
                text: $newItemName,
                placeholder: newItemIsFolder ? "Folder name" : "File name",
                onCommit: { value in performNewItem(name: value) },
                onCancel: { cancelNewItem() }
            )
            .frame(height: 22)
        }
        .padding(.leading, CGFloat(depth) * 16 + 12)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
    }

    private func searchResultRow(_ item: FileItem) -> some View {
        let relativePath = item.path.replacingOccurrences(of: rootPath + "/", with: "")
        return fileRowContent(
            item: item,
            depth: 0,
            relativePath: relativePath == item.name ? nil : relativePath
        )
    }

    private func activate(item: FileItem, isExpanded: Bool) {
        if item.isDirectory {
            withAnimation(.easeInOut(duration: 0.15)) {
                if normalizedSearchText.isEmpty {
                    if isExpanded {
                        expandedFolders.remove(item.path)
                    } else {
                        expandedFolders.insert(item.path)
                    }
                } else {
                    expandAncestors(for: item.path)
                    searchText = ""
                }
            }
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                onOpenFile(item.path)
            }
        }
    }

    private func beginNewItem(parent: String, isFolder: Bool) {
        newItemParent = parent
        newItemIsFolder = isFolder
        newItemName = ""
        expandedFolders.insert(parent)
        searchText = ""
        refreshTrigger += 1
    }

    private func cancelNewItem() {
        newItemParent = nil
        newItemName = ""
        refreshTrigger += 1
    }

    private func performNewItem(name inputName: String) {
        guard let parent = newItemParent else { return }
        let name = inputName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { cancelNewItem(); return }
        let fullPath = (parent as NSString).appendingPathComponent(name)
        let fm = FileManager.default
        if newItemIsFolder {
            try? fm.createDirectory(atPath: fullPath, withIntermediateDirectories: true)
        } else {
            fm.createFile(atPath: fullPath, contents: nil)
        }
        newItemParent = nil
        newItemName = ""
        refreshTrigger += 1
    }

    private func performRename(oldPath: String, newName inputName: String) {
        let newName = inputName.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != (oldPath as NSString).lastPathComponent else {
            renamingPath = nil
            refreshTrigger += 1
            return
        }
        let parent = (oldPath as NSString).deletingLastPathComponent
        let newPath = (parent as NSString).appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(atPath: oldPath, toPath: newPath)
            if selectedFilePath == oldPath {
                selectedFilePath = newPath
                onOpenFile(newPath)
            }
        } catch {}
        renamingPath = nil
        refreshTrigger += 1
    }

    private func performDelete(path: String) {
        try? FileManager.default.removeItem(atPath: path)
        if let selected = selectedFilePath, selected.hasPrefix(path) {
            selectedFilePath = nil
            onCloseSelectedFile()
        }
        if let clip = clipboardPath, clip.hasPrefix(path) {
            clipboardPath = nil
        }
        refreshTrigger += 1
    }

    private func performPaste(into directory: String) {
        guard let source = clipboardPath else { return }
        let name = (source as NSString).lastPathComponent
        var destination = (directory as NSString).appendingPathComponent(name)
        let fm = FileManager.default

        if !clipboardIsCut && fm.fileExists(atPath: destination) {
            let baseName = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            var counter = 1
            repeat {
                let suffix = counter == 1 ? " copy" : " copy \(counter)"
                let copiedName = ext.isEmpty ? "\(baseName)\(suffix)" : "\(baseName)\(suffix).\(ext)"
                destination = (directory as NSString).appendingPathComponent(copiedName)
                counter += 1
            } while fm.fileExists(atPath: destination)
        }

        do {
            if clipboardIsCut {
                try fm.moveItem(atPath: source, toPath: destination)
                if let selected = selectedFilePath, selected.hasPrefix(source) {
                    let newSelectedPath = selected.replacingOccurrences(of: source, with: destination)
                    selectedFilePath = newSelectedPath
                    onOpenFile(newSelectedPath)
                }
                clipboardPath = nil
            } else {
                try fm.copyItem(atPath: source, toPath: destination)
            }
        } catch {}

        expandedFolders.insert(directory)
        refreshTrigger += 1
    }

    private func expandAncestors(for path: String) {
        var current = path
        while current != rootPath && current != "/" {
            expandedFolders.insert(current)
            current = (current as NSString).deletingLastPathComponent
        }
        expandedFolders.insert(rootPath)
    }

    private func searchFiles(root: String, query: String) -> [FileItem] {
        var results: [FileItem] = []
        searchFilesRecursive(directory: root, query: query, depth: 0, results: &results)
        return sortItems(results)
    }

    private func searchFilesRecursive(directory: String, query: String, depth: Int, results: inout [FileItem]) {
        if let searchDepthLimit, depth >= searchDepthLimit { return }
        for item in listDirectory(directory) {
            if item.name.lowercased().contains(query) {
                results.append(item)
            }
            if item.isDirectory {
                searchFilesRecursive(directory: item.path, query: query, depth: depth + 1, results: &results)
            }
        }
    }

    private func listDirectory(_ path: String) -> [FileItem] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        let items = names.compactMap { name -> FileItem? in
            guard !isHiddenItemName(name) else { return nil }
            let fullPath = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { return nil }
            let item = FileItem(name: name, path: fullPath, isDirectory: isDir.boolValue)
            return shouldShowItem(item) ? item : nil
        }
        return sortItems(items)
    }

    private func sortItems(_ items: [FileItem]) -> [FileItem] {
        items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}

private struct WorkspaceFileTreeRow: View {
    let item: FileItem
    let depth: Int
    let isExpanded: Bool
    let isSelected: Bool
    let isDirty: Bool
    let relativePath: String?

    @ViewBuilder
    var body: some View {
        HStack(spacing: 6) {
            if item.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? .white.opacity(0.75) : .secondary)
                    .frame(width: 16)
            } else {
                Spacer().frame(width: 16)
            }

            WorkspaceFileItemIcon(item: item, isExpanded: isExpanded)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let relativePath {
                    Text(relativePath)
                        .font(.system(size: 10))
                        .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if isDirty {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, relativePath == nil ? CGFloat(depth) * 16 + 12 : 12)
        .padding(.trailing, 12)
        .padding(.vertical, relativePath == nil ? 7 : 5)
        .background(isSelected ? Color.accentColor.opacity(0.85) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
    }
}

private struct WorkspaceFileItemIcon: View {
    let item: FileItem
    let isExpanded: Bool

    var body: some View {
        if item.isDirectory {
            WorkspaceFolderIcon(isExpanded: isExpanded, size: 20)
        } else {
            Image(systemName: workspaceFileIconName(for: item.name))
                .font(.system(size: 17))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
        }
    }
}

private func workspaceFileIconName(for name: String) -> String {
    let ext = (name as NSString).pathExtension.lowercased()
    switch ext {
    case "md": return "doc.richtext"
    case "json": return "curlybraces"
    case "yaml", "yml": return "list.bullet.rectangle"
    case "txt": return "doc.text"
    case "py": return "chevron.left.forwardslash.chevron.right"
    case "swift": return "swift"
    case "js", "ts": return "chevron.left.forwardslash.chevron.right"
    default: return "doc"
    }
}

// MARK: - Commit TextField (reliable Enter + focus-loss on macOS)

private class EnterResignsTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        // Tag the field editor so the global key monitor can skip it
        if let editor = currentEditor() as? NSTextView {
            editor.identifier = NSUserInterfaceItemIdentifier("commitTextField")
        }
        return result
    }

    override func keyDown(with event: NSEvent) {
        // Enter (keyCode 36) or Return (keyCode 76) → resign focus
        if event.keyCode == 36 || event.keyCode == 76 {
            window?.makeFirstResponder(nil)
            return
        }
        super.keyDown(with: event)
    }
}

private struct CommitTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var onCommit: (String) -> Void
    var onCancel: (() -> Void)?

    func makeNSView(context: Context) -> EnterResignsTextField {
        let tf = EnterResignsTextField()
        tf.placeholderString = placeholder
        tf.font = NSFont.systemFont(ofSize: 13)
        tf.isBordered = true
        tf.bezelStyle = .roundedBezel
        tf.focusRingType = .exterior
        tf.delegate = context.coordinator
        tf.stringValue = text
        DispatchQueue.main.async {
            tf.window?.makeFirstResponder(tf)
            tf.currentEditor()?.selectAll(nil)
        }
        return tf
    }

    func updateNSView(_ nsView: EnterResignsTextField, context: Context) {
        context.coordinator.onCommit = onCommit
        context.coordinator.onCancel = onCancel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit, onCancel: onCancel)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onCommit: (String) -> Void
        var onCancel: (() -> Void)?

        init(text: Binding<String>, onCommit: @escaping (String) -> Void, onCancel: (() -> Void)?) {
            self._text = text
            self.onCommit = onCommit
            self.onCancel = onCancel
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            text = tf.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                onCancel?()
                return true
            }
            return false
        }

        // Fires on Enter (resign) and any other focus loss
        func controlTextDidEndEditing(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            onCommit(tf.stringValue)
        }
    }
}

private struct FileItem {
    let name: String
    let path: String
    let isDirectory: Bool
}

// MARK: - File Editor Panel

private enum FileViewMode {
    case preview    // QLPreviewView (read-only, syntax highlight / media playback)
    case editor     // TextEditor (editable)
}

private enum FileCategory {
    case text       // .txt, .yaml, .yml, .csv, .log — open in editor directly
    case code       // .py, .swift, .js, .ts, .json, .go, .rb, .rs, .sh, .md, etc. — preview first, edit button
    case media      // audio/video — preview only
    case image      // .png, .jpg, .gif, .svg, etc. — preview only
    case other      // everything else — preview

    var supportsEditing: Bool {
        switch self {
        case .text, .code: return true
        case .media, .image, .other: return false
        }
    }

    var defaultMode: FileViewMode {
        return .preview
    }

    static func detect(ext: String) -> FileCategory {
        switch ext.lowercased() {
        case "txt", "yaml", "yml", "csv", "log", "ini", "cfg", "conf", "toml":
            return .text
        case "md", "py", "swift", "js", "ts", "jsx", "tsx", "json", "go", "rb", "rs",
             "sh", "bash", "zsh", "c", "cpp", "h", "hpp", "java", "kt", "lua",
             "r", "sql", "html", "css", "scss", "xml", "dockerfile", "makefile":
            return .code
        case "mp3", "wav", "m4a", "aac", "flac", "ogg", "aiff",
             "mp4", "mov", "avi", "mkv", "m4v", "webm":
            return .media
        case "png", "jpg", "jpeg", "gif", "bmp", "tiff", "svg", "webp", "ico", "heic":
            return .image
        default:
            return .other
        }
    }

    static func languageName(ext: String) -> String {
        switch ext.lowercased() {
        case "py": return "Python"
        case "swift": return "Swift"
        case "js": return "JavaScript"
        case "ts": return "TypeScript"
        case "jsx": return "JSX"
        case "tsx": return "TSX"
        case "json": return "JSON"
        case "go": return "Go"
        case "rb": return "Ruby"
        case "rs": return "Rust"
        case "sh", "bash", "zsh": return "Shell"
        case "c": return "C"
        case "cpp", "hpp": return "C++"
        case "h": return "C/C++ Header"
        case "java": return "Java"
        case "kt": return "Kotlin"
        case "lua": return "Lua"
        case "r": return "R"
        case "sql": return "SQL"
        case "html": return "HTML"
        case "css": return "CSS"
        case "scss": return "SCSS"
        case "xml": return "XML"
        case "md": return "Markdown"
        case "txt": return "Plain Text"
        case "yaml", "yml": return "YAML"
        case "toml": return "TOML"
        case "ini", "cfg", "conf": return "Config"
        case "csv": return "CSV"
        case "log": return "Log"
        case "dockerfile": return "Dockerfile"
        case "makefile": return "Makefile"
        default: return ext.uppercased()
        }
    }
}

private struct FileEditorPanel: View {
    let filePath: String
    let onClose: () -> Void
    var onDirtyChanged: ((Bool) -> Void)?

    @State private var content: String = ""
    @State private var originalContent: String = ""
    @State private var isLoading = true
    @State private var saveMessage: String?
    @State private var viewMode: FileViewMode = .editor
    @State private var fontSize: CGFloat = 13
    @State private var cursorLine: Int = 1
    @State private var cursorColumn: Int = 1
    @State private var wordWrap = true

    private var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    private var fileExt: String {
        (filePath as NSString).pathExtension
    }

    private var category: FileCategory {
        FileCategory.detect(ext: fileExt)
    }

    private var isDirty: Bool {
        content != originalContent
    }

    private var fileSizeString: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
              let size = attrs[.size] as? UInt64 else { return "" }
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024) }
        return String(format: "%.1f MB", Double(size) / (1024 * 1024))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar
            Divider()

            // Content
            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if viewMode == .editor {
                CodeEditorView(
                    text: $content,
                    fontSize: fontSize,
                    wordWrap: wordWrap,
                    fileExtension: fileExt,
                    cursorLine: $cursorLine,
                    cursorColumn: $cursorColumn
                )
            } else if category.supportsEditing && !["md", "html", "htm"].contains(fileExt.lowercased()) {
                // Text/code preview: read-only with syntax highlighting
                CodeEditorView(
                    text: .constant(content),
                    fontSize: fontSize,
                    wordWrap: wordWrap,
                    fileExtension: fileExt,
                    cursorLine: $cursorLine,
                    cursorColumn: $cursorColumn,
                    isReadOnly: true
                )
            } else if fileExt.lowercased() == "md" {
                MarkdownPreviewView(markdown: content)
            } else if ["html", "htm"].contains(fileExt.lowercased()) {
                HTMLPreviewView(fileURL: URL(fileURLWithPath: filePath))
            } else {
                QuickLookPreview(url: URL(fileURLWithPath: filePath))
            }

            // Status bar
            if viewMode == .editor {
                Divider()
                statusBar
            }
        }
        .frame(maxWidth: 480)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { loadFile() }
        .onChange(of: filePath) { _ in loadFile() }
        .onChange(of: isDirty) { dirty in
            onDirtyChanged?(dirty)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: headerIcon)
                .foregroundColor(.accentColor)
            Text(fileName)
                .font(.headline)
                .lineLimit(1)
                .onTapGesture(count: 2) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(filePath, forType: .string)
                    let copiedMessage = I18n.t("workspace.files.pathCopied")
                    saveMessage = copiedMessage
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if saveMessage == copiedMessage { saveMessage = nil }
                    }
                }
                .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("workspace.files.copyPathHelp")))

            if viewMode == .editor && isDirty {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
            }

            if let msg = saveMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.green)
            }

            Spacer()

            // Font size controls
            if viewMode == .editor {
                Button(action: { if fontSize > 9 { fontSize -= 1 } }) {
                    Image(systemName: "textformat.size.smaller")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("workspace.files.decreaseFont")))

                Text("\(Int(fontSize))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 18)

                Button(action: { if fontSize < 28 { fontSize += 1 } }) {
                    Image(systemName: "textformat.size.larger")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("workspace.files.increaseFont")))

                // Word wrap toggle
                Button(action: { wordWrap.toggle() }) {
                    Image(systemName: "text.word.spacing")
                        .font(.system(size: 12))
                        .foregroundColor(wordWrap ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .unifiedTooltip(UnifiedTooltipContent(title: wordWrap ? I18n.t("workspace.files.disableWordWrap") : I18n.t("workspace.files.enableWordWrap")))

                Divider().frame(height: 16)
            }

            // Toggle preview/edit for code files
            if category.supportsEditing {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewMode = (viewMode == .preview) ? .editor : .preview
                    }
                }) {
                    Image(systemName: viewMode == .preview ? "square.and.pencil" : "eye")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .unifiedTooltip(UnifiedTooltipContent(title: viewMode == .preview ? I18n.t("common.action.edit") : I18n.t("common.action.preview")))
            }

            // Save via Cmd+S (hidden)
            if viewMode == .editor {
                Button(action: save) { EmptyView() }
                    .keyboardShortcut("s", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .hidden()

                // Font size keyboard shortcuts
                Button(action: { if fontSize < 28 { fontSize += 1 } }) { EmptyView() }
                    .keyboardShortcut("+", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .hidden()

                Button(action: { if fontSize > 9 { fontSize -= 1 } }) { EmptyView() }
                    .keyboardShortcut("-", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .hidden()
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("catalog.action.close")))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            Text(I18n.format("workspace.files.position", Int64(cursorLine), Int64(cursorColumn)))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)

            Text("UTF-8")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Text(FileCategory.languageName(ext: fileExt))
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            Text(fileSizeString)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var headerIcon: String {
        switch category {
        case .media: return "play.circle"
        case .image: return "photo"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .text: return "doc.text"
        case .other: return "doc"
        }
    }

    private func loadFile() {
        isLoading = true
        saveMessage = nil
        viewMode = category.defaultMode
        cursorLine = 1
        cursorColumn = 1

        if category.supportsEditing {
            if let data = FileManager.default.contents(atPath: filePath),
               let text = String(data: data, encoding: .utf8) {
                let formatted = fileExt.lowercased() == "json" ? prettyJSON(text) : text
                content = formatted
                originalContent = formatted
            } else {
                content = ""
                originalContent = ""
            }
        }
        isLoading = false
    }

    private func save() {
        do {
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            originalContent = content
            saveMessage = "Saved"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if saveMessage == "Saved" { saveMessage = nil }
            }
        } catch {
            saveMessage = "Error"
        }
    }

    private func prettyJSON(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return raw
        }
        return result
    }
}

// MARK: - Code Editor View (NSTextView with Line Numbers + Find Bar)

private struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var wordWrap: Bool
    var fileExtension: String
    @Binding var cursorLine: Int
    @Binding var cursorColumn: Int
    var isReadOnly: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        textView.isEditable = !isReadOnly
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.identifier = NSUserInterfaceItemIdentifier("codeEditorTextView")

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        textView.drawsBackground = true
        textView.backgroundColor = isDark
            ? NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.13, alpha: 1.0)
            : NSColor.white
        textView.textColor = isDark ? NSColor.white : NSColor.black
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        if wordWrap {
            textView.isHorizontallyResizable = false
            textView.textContainer?.widthTracksTextView = true
        } else {
            scrollView.hasHorizontalScroller = true
            textView.isHorizontallyResizable = true
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }

        textView.string = text
        SyntaxHighlighter.highlight(textView: textView, fileExtension: fileExtension, fontSize: fontSize)

        // Observe selection changes for cursor position
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textViewDidChangeSelection(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )

        // Observe scroll
        if let clipView = scrollView.contentView as? NSClipView {
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                context.coordinator,
                selector: #selector(Coordinator.boundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
        }

        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Never interrupt IME composition (e.g. Chinese/Japanese input)
        guard !textView.hasMarkedText() else { return }

        if !context.coordinator.isUpdatingFromDelegate && textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            SyntaxHighlighter.highlight(textView: textView, fileExtension: fileExtension, fontSize: fontSize)
            textView.selectedRanges = selectedRanges
        }

        if textView.font?.pointSize != fontSize {
            textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }

        let needsHorizontalScroller = !wordWrap
        if scrollView.hasHorizontalScroller != needsHorizontalScroller {
            scrollView.hasHorizontalScroller = needsHorizontalScroller
            if wordWrap {
                textView.isHorizontallyResizable = false
                textView.textContainer?.widthTracksTextView = true
            } else {
                textView.isHorizontallyResizable = true
                textView.textContainer?.widthTracksTextView = false
                textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            }
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        weak var textView: NSTextView?
        var isUpdatingFromDelegate = false

        init(_ parent: CodeEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            isUpdatingFromDelegate = true
            parent.text = tv.string
            // Defer flag reset so it covers SwiftUI's batched updateNSView call
            DispatchQueue.main.async {
                self.isUpdatingFromDelegate = false
            }
            SyntaxHighlighter.highlight(textView: tv, fileExtension: parent.fileExtension, fontSize: parent.fontSize)
        }

        @objc func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let selectedRange = tv.selectedRange()
            let text = tv.string
            let nsText = text as NSString

            let lineRange = nsText.lineRange(for: NSRange(location: selectedRange.location, length: 0))
            let lineStart = lineRange.location

            var line = 1
            var idx = 0
            while idx < selectedRange.location && idx < nsText.length {
                if nsText.character(at: idx) == 0x0A { line += 1 }
                idx += 1
            }

            let col = selectedRange.location - lineStart + 1

            DispatchQueue.main.async {
                self.parent.cursorLine = line
                self.parent.cursorColumn = col
            }
        }

        @objc func boundsDidChange(_ notification: Notification) {
        }
    }
}

// MARK: - Line Number Gutter (replaces NSRulerView to avoid tile() corruption)

private class LineNumberGutterView: NSView {
    weak var textView: NSTextView?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Background
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()

        // Separator line on the right edge
        NSColor.separatorColor.setStroke()
        let sep = NSBezierPath()
        sep.move(to: NSPoint(x: bounds.maxX - 0.5, y: dirtyRect.minY))
        sep.line(to: NSPoint(x: bounds.maxX - 0.5, y: dirtyRect.maxY))
        sep.lineWidth = 0.5
        sep.stroke()

        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView = textView.enclosingScrollView else { return }

        let visibleRect = scrollView.contentView.bounds
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let font = NSFont.monospacedSystemFont(ofSize: (textView.font?.pointSize ?? 13) - 2, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let nsString = textView.string as NSString
        guard nsString.length > 0 else { return }

        // Find line number for the first visible character
        var lineNumber = 1
        var idx = 0
        while idx < charRange.location && idx < nsString.length {
            if nsString.character(at: idx) == 0x0A { lineNumber += 1 }
            idx += 1
        }

        // Draw line numbers for visible lines
        var charIndex = charRange.location
        while charIndex < NSMaxRange(charRange) && charIndex < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))

            let glyphIdx = layoutManager.glyphIndexForCharacter(at: lineRange.location)
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
            lineRect.origin.y += textView.textContainerInset.height

            let yPos = lineRect.origin.y - visibleRect.origin.y
            let lineStr = "\(lineNumber)" as NSString
            let strSize = lineStr.size(withAttributes: attrs)
            let drawPoint = NSPoint(
                x: bounds.width - strSize.width - 8,
                y: yPos + (lineRect.height - strSize.height) / 2
            )
            lineStr.draw(at: drawPoint, withAttributes: attrs)

            lineNumber += 1
            charIndex = NSMaxRange(lineRange)
            if charIndex == lineRange.location { charIndex += 1 } // prevent infinite loop
        }
    }
}

// MARK: - Syntax Highlighter

private struct SyntaxHighlighter {

    struct Rule {
        let pattern: String
        let color: NSColor
        let options: NSRegularExpression.Options

        init(_ pattern: String, _ color: NSColor, options: NSRegularExpression.Options = []) {
            self.pattern = pattern
            self.color = color
            self.options = options
        }
    }

    static func highlight(textView: NSTextView, fileExtension: String, fontSize: CGFloat) {
        guard let layoutManager = textView.layoutManager else { return }
        let source = textView.string
        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        guard fullRange.length > 0 else { return }

        // Clear previous temporary highlighting
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)

        // Apply rules via temporary attributes (display-only, does not modify textStorage)
        let rules = Self.rules(for: fileExtension)
        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else { continue }
            regex.enumerateMatches(in: source, options: [], range: fullRange) { match, _, _ in
                guard let matchRange = match?.range, matchRange.location != NSNotFound else { return }
                layoutManager.addTemporaryAttribute(.foregroundColor, value: rule.color, forCharacterRange: matchRange)
            }
        }
    }

    // MARK: - Language Rules

    private static func rules(for ext: String) -> [Rule] {
        switch ext.lowercased() {
        case "py":          return pythonRules
        case "swift":       return swiftRules
        case "js", "jsx":   return jsRules
        case "ts", "tsx":   return tsRules
        case "json":        return jsonRules
        case "go":          return goRules
        case "rb":          return rubyRules
        case "rs":          return rustRules
        case "sh", "bash", "zsh": return shellRules
        case "c", "cpp", "h", "hpp": return cRules
        case "java", "kt":  return javaRules
        case "html", "xml": return htmlRules
        case "css", "scss": return cssRules
        case "sql":         return sqlRules
        case "yaml", "yml": return yamlRules
        case "toml", "ini", "cfg", "conf": return configRules
        case "md":          return markdownRules
        case "lua":         return luaRules
        case "dockerfile":  return dockerRules
        case "makefile":    return makefileRules
        default:            return genericRules
        }
    }

    // Colors
    private static let kKeyword   = NSColor.systemPink
    private static let kString    = NSColor.systemGreen
    private static let kComment   = NSColor.systemGray
    private static let kNumber    = NSColor.systemOrange
    private static let kType      = NSColor.systemTeal
    private static let kFunction  = NSColor.systemBlue
    private static let kConstant  = NSColor.systemPurple
    private static let kTag       = NSColor.systemRed
    private static let kAttr      = NSColor.systemOrange
    private static let kHeading   = NSColor.systemBlue

    // Shared patterns
    private static let pDoubleStr = "\"(?:[^\"\\\\]|\\\\.)*\""
    private static let pSingleStr = "'(?:[^'\\\\]|\\\\.)*'"
    private static let pNumber    = "\\b(?:0[xXoObB])?[0-9][0-9_]*\\.?[0-9_]*(?:[eE][+-]?[0-9]+)?\\b"
    private static let pLineComment = "//.*"
    private static let pHashComment = "#.*"
    private static let pBlockComment = "/\\*[\\s\\S]*?\\*/"

    // MARK: Python
    private static var pythonRules: [Rule] { [
        Rule(pHashComment, kComment),
        Rule("\"\"\"[\\s\\S]*?\"\"\"", kString, options: []),
        Rule("'''[\\s\\S]*?'''", kString, options: []),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:def|class|if|elif|else|for|while|return|import|from|as|try|except|finally|with|raise|yield|lambda|pass|break|continue|and|or|not|in|is|async|await|global|nonlocal|del|assert)\\b", kKeyword),
        Rule("\\b(?:True|False|None|self|cls)\\b", kConstant),
        Rule("\\b(?:int|float|str|bool|list|dict|tuple|set|bytes|object|type|Exception)\\b", kType),
        Rule("@\\w+", kFunction),
        Rule("\\b\\w+(?=\\()", kFunction),
    ] }

    // MARK: Swift
    private static var swiftRules: [Rule] { [
        Rule(pBlockComment, kComment, options: [.dotMatchesLineSeparators]),
        Rule(pLineComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:func|var|let|if|else|guard|switch|case|default|for|while|repeat|return|import|class|struct|enum|protocol|extension|init|deinit|self|super|throw|throws|try|catch|do|break|continue|where|in|as|is|typealias|associatedtype|async|await|actor|some|any|macro)\\b", kKeyword),
        Rule("\\b(?:true|false|nil|Self)\\b", kConstant),
        Rule("\\b(?:String|Int|Double|Float|Bool|Array|Dictionary|Optional|Set|Result|Void|Any|AnyObject|Error|Codable|Hashable|Equatable|Identifiable|View|State|Binding|Published|ObservableObject|EnvironmentObject)\\b", kType),
        Rule("@\\w+", kFunction),
        Rule("#\\w+", kKeyword),
        Rule("\\b\\w+(?=\\()", kFunction),
    ] }

    // MARK: JavaScript
    private static var jsRules: [Rule] { [
        Rule(pBlockComment, kComment, options: [.dotMatchesLineSeparators]),
        Rule(pLineComment, kComment),
        Rule("`(?:[^`\\\\]|\\\\.)*`", kString),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:function|var|let|const|if|else|for|while|do|switch|case|default|return|break|continue|throw|try|catch|finally|new|delete|typeof|instanceof|in|of|class|extends|super|import|export|from|as|default|async|await|yield|this|void)\\b", kKeyword),
        Rule("\\b(?:true|false|null|undefined|NaN|Infinity)\\b", kConstant),
        Rule("\\b(?:Array|Object|String|Number|Boolean|Function|Promise|Map|Set|RegExp|Error|Date|Math|JSON|console)\\b", kType),
        Rule("\\b\\w+(?=\\()", kFunction),
    ] }

    // MARK: TypeScript
    private static var tsRules: [Rule] { [
        Rule(pBlockComment, kComment, options: [.dotMatchesLineSeparators]),
        Rule(pLineComment, kComment),
        Rule("`(?:[^`\\\\]|\\\\.)*`", kString),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:function|var|let|const|if|else|for|while|do|switch|case|default|return|break|continue|throw|try|catch|finally|new|delete|typeof|instanceof|in|of|class|extends|super|import|export|from|as|default|async|await|yield|this|void|type|interface|enum|namespace|declare|abstract|implements|readonly|keyof|infer)\\b", kKeyword),
        Rule("\\b(?:true|false|null|undefined|NaN|Infinity)\\b", kConstant),
        Rule("\\b(?:string|number|boolean|any|unknown|never|void|object|symbol|bigint|Array|Object|Promise|Map|Set|Record|Partial|Required|Omit|Pick)\\b", kType),
        Rule("\\b\\w+(?=\\()", kFunction),
    ] }

    // MARK: JSON
    private static var jsonRules: [Rule] { [
        Rule(pDoubleStr + "(?=\\s*:)", kFunction),
        Rule(pDoubleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:true|false|null)\\b", kConstant),
    ] }

    // MARK: Go
    private static var goRules: [Rule] { [
        Rule(pBlockComment, kComment, options: [.dotMatchesLineSeparators]),
        Rule(pLineComment, kComment),
        Rule("`[^`]*`", kString),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:func|var|const|if|else|for|range|switch|case|default|return|break|continue|go|defer|select|chan|map|struct|interface|type|package|import|fallthrough|goto)\\b", kKeyword),
        Rule("\\b(?:true|false|nil|iota)\\b", kConstant),
        Rule("\\b(?:int|int8|int16|int32|int64|uint|uint8|uint16|uint32|uint64|float32|float64|complex64|complex128|string|bool|byte|rune|error|any)\\b", kType),
        Rule("\\b\\w+(?=\\()", kFunction),
    ] }

    // MARK: Ruby
    private static var rubyRules: [Rule] { [
        Rule(pHashComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:def|class|module|if|elsif|else|unless|while|until|for|do|end|return|break|next|yield|begin|rescue|ensure|raise|require|include|extend|attr_accessor|attr_reader|attr_writer|puts|print|lambda|proc)\\b", kKeyword),
        Rule("\\b(?:true|false|nil|self)\\b", kConstant),
        Rule(":[a-zA-Z_]\\w*", kConstant),
        Rule("@{1,2}\\w+", kType),
        Rule("\\b\\w+(?=[?!]?\\()", kFunction),
    ] }

    // MARK: Rust
    private static var rustRules: [Rule] { [
        Rule(pBlockComment, kComment, options: [.dotMatchesLineSeparators]),
        Rule(pLineComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:fn|let|mut|if|else|match|for|while|loop|return|break|continue|struct|enum|impl|trait|type|use|mod|pub|crate|self|super|where|async|await|move|unsafe|extern|const|static|ref|as|in|dyn|macro_rules)\\b", kKeyword),
        Rule("\\b(?:true|false|None|Some|Ok|Err|Self)\\b", kConstant),
        Rule("\\b(?:i8|i16|i32|i64|i128|isize|u8|u16|u32|u64|u128|usize|f32|f64|bool|char|str|String|Vec|Option|Result|Box|Rc|Arc|HashMap|HashSet)\\b", kType),
        Rule("\\b\\w+(?=\\()", kFunction),
        Rule("#\\[.*?\\]", kFunction),
    ] }

    // MARK: Shell
    private static var shellRules: [Rule] { [
        Rule(pHashComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:if|then|else|elif|fi|for|while|do|done|case|esac|in|function|return|exit|local|export|source|alias|unalias|set|unset|readonly|shift|eval|exec|trap)\\b", kKeyword),
        Rule("\\$\\{?[a-zA-Z_]\\w*\\}?", kType),
        Rule("\\$[0-9#?@*!$-]", kType),
        Rule("\\b\\w+(?=\\()", kFunction),
    ] }

    // MARK: C / C++
    private static var cRules: [Rule] { [
        Rule(pBlockComment, kComment, options: [.dotMatchesLineSeparators]),
        Rule(pLineComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("#\\s*(?:include|define|ifdef|ifndef|endif|pragma|if|else|elif|undef|error|warning)\\b.*", kFunction),
        Rule("\\b(?:if|else|for|while|do|switch|case|default|return|break|continue|struct|union|enum|typedef|sizeof|static|extern|inline|const|volatile|register|auto|void|goto|class|public|private|protected|virtual|override|template|typename|namespace|using|new|delete|try|catch|throw|noexcept|constexpr|nullptr|this|operator)\\b", kKeyword),
        Rule("\\b(?:int|char|short|long|float|double|unsigned|signed|bool|size_t|string|vector|map|set|auto|wchar_t|int8_t|int16_t|int32_t|int64_t|uint8_t|uint16_t|uint32_t|uint64_t)\\b", kType),
        Rule("\\b(?:true|false|NULL|nullptr|TRUE|FALSE)\\b", kConstant),
        Rule("\\b\\w+(?=\\()", kFunction),
    ] }

    // MARK: Java / Kotlin
    private static var javaRules: [Rule] { [
        Rule(pBlockComment, kComment, options: [.dotMatchesLineSeparators]),
        Rule(pLineComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:if|else|for|while|do|switch|case|default|return|break|continue|class|interface|extends|implements|new|this|super|import|package|public|private|protected|static|final|abstract|synchronized|volatile|transient|native|try|catch|finally|throw|throws|void|enum|instanceof|assert|when|fun|val|var|data|object|companion|override|open|sealed|suspend|inline|reified|lateinit|by|constructor|init)\\b", kKeyword),
        Rule("\\b(?:true|false|null|it)\\b", kConstant),
        Rule("\\b(?:int|long|short|byte|float|double|char|boolean|String|Integer|Long|Float|Double|Boolean|Object|List|Map|Set|Array|ArrayList|HashMap|void|Void|Any|Unit|Nothing|Int)\\b", kType),
        Rule("@\\w+", kFunction),
        Rule("\\b\\w+(?=\\()", kFunction),
    ] }

    // MARK: HTML / XML
    private static var htmlRules: [Rule] { [
        Rule("<!--[\\s\\S]*?-->", kComment, options: [.dotMatchesLineSeparators]),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule("</?\\w+", kTag),
        Rule("/?>", kTag),
        Rule("\\b[a-zA-Z-]+(?=\\s*=)", kAttr),
    ] }

    // MARK: CSS / SCSS
    private static var cssRules: [Rule] { [
        Rule(pBlockComment, kComment, options: [.dotMatchesLineSeparators]),
        Rule(pLineComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("[.#][a-zA-Z_][\\w-]*", kTag),
        Rule("@[a-zA-Z][\\w-]*", kKeyword),
        Rule("\\b[a-zA-Z-]+(?=\\s*:)", kFunction),
        Rule("#[0-9a-fA-F]{3,8}\\b", kConstant),
        Rule("\\$[a-zA-Z_][\\w-]*", kType),
    ] }

    // MARK: SQL
    private static var sqlRules: [Rule] { [
        Rule("--.*", kComment),
        Rule(pBlockComment, kComment, options: [.dotMatchesLineSeparators]),
        Rule(pSingleStr, kString),
        Rule(pDoubleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|DROP|ALTER|ADD|INDEX|JOIN|LEFT|RIGHT|INNER|OUTER|ON|AND|OR|NOT|IN|IS|NULL|AS|ORDER|BY|GROUP|HAVING|LIMIT|OFFSET|UNION|DISTINCT|EXISTS|BETWEEN|LIKE|CASE|WHEN|THEN|ELSE|END|BEGIN|COMMIT|ROLLBACK|PRIMARY|KEY|FOREIGN|REFERENCES|UNIQUE|DEFAULT|CHECK|CONSTRAINT|VIEW|TRIGGER|FUNCTION|PROCEDURE|GRANT|REVOKE|WITH|RECURSIVE)\\b", kKeyword, options: [.caseInsensitive]),
        Rule("\\b(?:INT|INTEGER|VARCHAR|TEXT|BOOLEAN|BOOL|DATE|TIMESTAMP|FLOAT|DOUBLE|DECIMAL|NUMERIC|CHAR|BLOB|SERIAL|BIGINT|SMALLINT|REAL)\\b", kType, options: [.caseInsensitive]),
        Rule("\\b(?:COUNT|SUM|AVG|MIN|MAX|COALESCE|IFNULL|NULLIF|CAST|CONVERT|CONCAT|LENGTH|SUBSTR|TRIM|UPPER|LOWER|NOW|CURRENT_TIMESTAMP)\\b", kFunction, options: [.caseInsensitive]),
    ] }

    // MARK: YAML
    private static var yamlRules: [Rule] { [
        Rule(pHashComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("^\\s*[\\w.-]+(?=\\s*:)", kFunction, options: [.anchorsMatchLines]),
        Rule("\\b(?:true|false|yes|no|null|~)\\b", kConstant, options: [.caseInsensitive]),
    ] }

    // MARK: Config (TOML / INI)
    private static var configRules: [Rule] { [
        Rule(pHashComment, kComment),
        Rule(";.*", kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("^\\s*\\[.*?\\]", kTag, options: [.anchorsMatchLines]),
        Rule("^\\s*[\\w.-]+(?=\\s*=)", kFunction, options: [.anchorsMatchLines]),
        Rule("\\b(?:true|false)\\b", kConstant, options: [.caseInsensitive]),
    ] }

    // MARK: Markdown
    private static var markdownRules: [Rule] { [
        Rule("^#{1,6}\\s+.*$", kHeading, options: [.anchorsMatchLines]),
        Rule("\\*\\*(?:[^*]|\\*(?!\\*))+\\*\\*", kKeyword),
        Rule("\\*(?:[^*])+\\*", kConstant),
        Rule("`[^`\n]+`", kString),
        Rule("```[\\s\\S]*?```", kString, options: [.dotMatchesLineSeparators]),
        Rule("^\\s*[-*+]\\s", kTag, options: [.anchorsMatchLines]),
        Rule("^\\s*\\d+\\.\\s", kTag, options: [.anchorsMatchLines]),
        Rule("\\[([^\\]]*)\\]\\([^)]*\\)", kFunction),
    ] }

    // MARK: Lua
    private static var luaRules: [Rule] { [
        Rule("--\\[\\[[\\s\\S]*?\\]\\]", kComment, options: [.dotMatchesLineSeparators]),
        Rule("--.*", kComment),
        Rule("\\[\\[[\\s\\S]*?\\]\\]", kString, options: [.dotMatchesLineSeparators]),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:and|break|do|else|elseif|end|for|function|if|in|local|not|or|repeat|return|then|until|while|goto)\\b", kKeyword),
        Rule("\\b(?:true|false|nil)\\b", kConstant),
        Rule("\\b\\w+(?=\\()", kFunction),
    ] }

    // MARK: Dockerfile
    private static var dockerRules: [Rule] { [
        Rule(pHashComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule("^\\s*(?:FROM|RUN|CMD|LABEL|MAINTAINER|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|ARG|ONBUILD|STOPSIGNAL|HEALTHCHECK|SHELL|AS)\\b", kKeyword, options: [.anchorsMatchLines, .caseInsensitive]),
        Rule("\\$\\{?[a-zA-Z_]\\w*\\}?", kType),
    ] }

    // MARK: Makefile
    private static var makefileRules: [Rule] { [
        Rule(pHashComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule("^[a-zA-Z_][\\w.-]*(?=\\s*:)", kTag, options: [.anchorsMatchLines]),
        Rule("\\$[({][^)}]+[)}]", kType),
        Rule("\\b(?:ifeq|ifneq|ifdef|ifndef|else|endif|include|define|endef|override|export|unexport|vpath|PHONY)\\b", kKeyword),
    ] }

    // MARK: Generic fallback
    private static var genericRules: [Rule] { [
        Rule(pBlockComment, kComment, options: [.dotMatchesLineSeparators]),
        Rule(pLineComment, kComment),
        Rule(pHashComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
    ] }
}

// MARK: - Line Number Ruler View

private class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView!, orientation: .verticalRuler)
        self.ruleThickness = 40
        self.clientView = textView
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = self.textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        // Background
        NSColor.controlBackgroundColor.setFill()
        rect.fill()

        // Separator line
        NSColor.separatorColor.setStroke()
        let separatorPath = NSBezierPath()
        separatorPath.move(to: NSPoint(x: bounds.maxX - 0.5, y: rect.minY))
        separatorPath.line(to: NSPoint(x: bounds.maxX - 0.5, y: rect.maxY))
        separatorPath.lineWidth = 0.5
        separatorPath.stroke()

        let font = NSFont.monospacedSystemFont(ofSize: (textView.font?.pointSize ?? 13) - 2, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let nsString = textView.string as NSString
        let visibleRect = scrollView!.contentView.bounds
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Find the line number for the first visible character
        var lineNumber = 1
        var idx = 0
        while idx < charRange.location && idx < nsString.length {
            if nsString.character(at: idx) == 0x0A {
                lineNumber += 1
            }
            idx += 1
        }

        // Draw line numbers for visible lines
        var charIndex = charRange.location
        while charIndex < NSMaxRange(charRange) {
            let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))

            let glyphIdx = layoutManager.glyphIndexForCharacter(at: lineRange.location)
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
            lineRect.origin.y += textView.textContainerInset.height

            // Convert to ruler coordinates
            let yPos = lineRect.origin.y - visibleRect.origin.y

            let lineStr = "\(lineNumber)" as NSString
            let strSize = lineStr.size(withAttributes: attrs)
            let drawPoint = NSPoint(
                x: ruleThickness - strSize.width - 8,
                y: yPos + (lineRect.height - strSize.height) / 2
            )
            lineStr.draw(at: drawPoint, withAttributes: attrs)

            lineNumber += 1
            charIndex = NSMaxRange(lineRange)
        }
    }
}

// MARK: - QuickLook Preview (NSViewRepresentable)

// MARK: - Markdown Preview (WKWebView)

private struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        loadMarkdown(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        loadMarkdown(webView)
    }

    private func loadMarkdown(_ webView: WKWebView) {
        let escaped = markdown
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let bgColor = isDark ? "#1e1e1e" : "#ffffff"
        let textColor = isDark ? "#d4d4d4" : "#1e1e1e"
        let codeBg = isDark ? "#2d2d2d" : "#f5f5f5"
        let borderColor = isDark ? "#444" : "#ddd"
        let linkColor = isDark ? "#569cd6" : "#0366d6"
        let headingColor = isDark ? "#e0e0e0" : "#111111"

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                font-size: 14px;
                line-height: 1.6;
                color: \(textColor);
                background: \(bgColor);
                padding: 16px 20px;
                margin: 0;
                word-wrap: break-word;
            }
            h1, h2, h3, h4, h5, h6 { color: \(headingColor); margin-top: 1.2em; margin-bottom: 0.4em; }
            h1 { font-size: 1.8em; border-bottom: 1px solid \(borderColor); padding-bottom: 0.3em; }
            h2 { font-size: 1.4em; border-bottom: 1px solid \(borderColor); padding-bottom: 0.2em; }
            h3 { font-size: 1.2em; }
            a { color: \(linkColor); text-decoration: none; }
            a:hover { text-decoration: underline; }
            code {
                background: \(codeBg);
                padding: 2px 6px;
                border-radius: 3px;
                font-family: "SF Mono", Menlo, monospace;
                font-size: 0.9em;
            }
            pre {
                background: \(codeBg);
                padding: 12px;
                border-radius: 6px;
                overflow-x: auto;
            }
            pre code { background: none; padding: 0; }
            blockquote {
                border-left: 4px solid \(borderColor);
                margin: 0.5em 0;
                padding: 0.2em 1em;
                color: \(isDark ? "#999" : "#666");
            }
            table { border-collapse: collapse; width: 100%; margin: 0.8em 0; }
            th, td { border: 1px solid \(borderColor); padding: 6px 12px; text-align: left; }
            th { background: \(codeBg); font-weight: 600; }
            img { max-width: 100%; }
            hr { border: none; border-top: 1px solid \(borderColor); margin: 1.5em 0; }
            ul, ol { padding-left: 1.5em; }
            li { margin: 0.2em 0; }
        </style>
        </head>
        <body>
        <div id="content"></div>
        <script>
            document.getElementById('content').innerHTML = marked.parse(`\(escaped)`);
        </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - HTML Preview (WKWebView)

private struct HTMLPreviewView: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
    }
}

private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        view.previewItem = url as QLPreviewItem
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = url as QLPreviewItem
    }
}
