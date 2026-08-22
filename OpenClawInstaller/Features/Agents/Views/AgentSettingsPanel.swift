import SwiftUI
import AppKit

// MARK: - Agent Settings Panel

struct AgentSettingsPanel: View {
    @ObservedObject var viewModel: DashboardViewModel
    let agent: SubAgentInfo
    let onClose: () -> Void

    @State private var selectedModel: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                AgentAvatarImage(size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.headline)
                    Text(agent.id)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color(NSColor.windowBackgroundColor))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Info section
                        VStack(alignment: .leading, spacing: 6) {
                            // Model picker
                            HStack(spacing: 6) {
                                Image(systemName: "cpu")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(I18n.t("dashboard.model.label")):")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
	                                Picker("", selection: $selectedModel) {
	                                    Text(I18n.t("dashboard.model.defaultInherit")).tag("")
	                                    ForEach(viewModel.availableModelsForSettings) { model in
	                                        Text(model.name).tag(model.runtimeId)
	                                    }
	                                }
                                .labelsHidden()
                                .controlSize(.small)
                                .frame(maxWidth: 260)
                                .onChange(of: selectedModel) { newValue in
                                    if newValue != agent.model {
                                        viewModel.updateAgentModel(model: newValue)
                                    }
                                }
                            }

                            // Workspace path (clickable → open in Finder)
                            if !agent.workspace.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(agent.workspace.replacingOccurrences(
                                        of: FileManager.default.homeDirectoryForCurrentUser.path,
                                        with: "~"
                                    ))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    NSWorkspace.shared.open(URL(fileURLWithPath: agent.workspace))
                                }
                                .onHover { inside in
                                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                }
                            }

                            // Binding details
                            if !agent.bindingDetails.isEmpty {
                                ForEach(agent.bindingDetails, id: \.self) { binding in
                                    HStack(spacing: 6) {
                                        Image(systemName: "link")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(binding)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        Divider()

                        // Persona editors (collapsed by default)
                        VStack(alignment: .leading, spacing: 12) {
                            MarkdownFileEditor(
                                title: "IDENTITY.md",
                                icon: "person.crop.circle",
                                content: viewModel.settingsBinding(for: .identity),
                                isDirty: viewModel.selectedAgentDetail?.identityDirty ?? false,
                                onSave: {
                                    viewModel.saveAgentPersonaFile(file: .identity)
                                },
                                initiallyExpanded: false
                            )

                            MarkdownFileEditor(
                                title: "SOUL.md",
                                icon: "heart.fill",
                                content: viewModel.settingsBinding(for: .soul),
                                isDirty: viewModel.selectedAgentDetail?.soulDirty ?? false,
                                onSave: {
                                    viewModel.saveAgentPersonaFile(file: .soul)
                                },
                                initiallyExpanded: false
                            )

                            MarkdownFileEditor(
                                title: "MEMORY.md",
                                icon: "brain.head.profile",
                                content: viewModel.settingsBinding(for: .memory),
                                isDirty: viewModel.selectedAgentDetail?.memoryDirty ?? false,
                                onSave: {
                                    viewModel.saveAgentPersonaFile(file: .memory)
                                },
                                initiallyExpanded: false
                            )

                            // Additional .md files — only shown when present in workspace
                            if viewModel.hasPersonaFile("USER.md") {
                                MarkdownFileEditor(
                                    title: "USER.md",
                                    icon: "person.fill",
                                    content: viewModel.settingsBindingByName("USER.md"),
                                    isDirty: viewModel.isFileDirtyByName("USER.md"),
                                    onSave: { viewModel.savePersonaFileByName("USER.md") },
                                    initiallyExpanded: false
                                )
                            }

                            if viewModel.hasPersonaFile("AGENTS.md") {
                                MarkdownFileEditor(
                                    title: "AGENTS.md",
                                    icon: "person.3.fill",
                                    content: viewModel.settingsBindingByName("AGENTS.md"),
                                    isDirty: viewModel.isFileDirtyByName("AGENTS.md"),
                                    onSave: { viewModel.savePersonaFileByName("AGENTS.md") },
                                    initiallyExpanded: false
                                )
                            }

                            if viewModel.hasPersonaFile("BOOTSTRAP.md") {
                                MarkdownFileEditor(
                                    title: "BOOTSTRAP.md",
                                    icon: "power",
                                    content: viewModel.settingsBindingByName("BOOTSTRAP.md"),
                                    isDirty: viewModel.isFileDirtyByName("BOOTSTRAP.md"),
                                    onSave: { viewModel.savePersonaFileByName("BOOTSTRAP.md") },
                                    initiallyExpanded: false
                                )
                            }

                            if viewModel.hasPersonaFile("HEARTBEAT.md") {
                                MarkdownFileEditor(
                                    title: "HEARTBEAT.md",
                                    icon: "heart.text.clipboard",
                                    content: viewModel.settingsBindingByName("HEARTBEAT.md"),
                                    isDirty: viewModel.isFileDirtyByName("HEARTBEAT.md"),
                                    onSave: { viewModel.savePersonaFileByName("HEARTBEAT.md") },
                                    initiallyExpanded: false
                                )
                            }

                            if viewModel.hasPersonaFile("TOOLS.md") {
                                MarkdownFileEditor(
                                    title: "TOOLS.md",
                                    icon: "wrench.and.screwdriver",
                                    content: viewModel.settingsBindingByName("TOOLS.md"),
                                    isDirty: viewModel.isFileDirtyByName("TOOLS.md"),
                                    onSave: { viewModel.savePersonaFileByName("TOOLS.md") },
                                    initiallyExpanded: false
                                )
                            }
                        }
                        .padding(16)
                    }
                }
        }
        .frame(width: 380)
        // Contrast against the chat area's windowBackgroundColor so the
        // drawer reads as a clearly separate panel — without this, the
        // drawer and chat were the same surface and felt borderless.
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .leading) {
            // Crisp 1px divider on the leading edge so the boundary is
            // unambiguous even when shadow is muted in light mode.
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 6, x: -2, y: 0)
        .onAppear {
            selectedModel = agent.model
        }
    }
}

// MARK: - Workspace File Panel

private struct OutputsTabView: View {
    let agentId: String
    @State private var refreshId = UUID()

    private var workspacePath: String {
        let base = NSString("~/.openclaw").expandingTildeInPath
        if agentId == "main" {
            return (base as NSString).appendingPathComponent("workspace")
        }
        return (base as NSString).appendingPathComponent("workspace-\(agentId)")
    }

    private var outputItems: [URL] {
        let root = URL(fileURLWithPath: workspacePath, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let excludedNames: Set<String> = [
            "IDENTITY.md", "SOUL.md", "MEMORY.md", "USER.md",
            "AGENTS.md", "BOOTSTRAP.md", "HEARTBEAT.md", "TOOLS.md"
        ]

        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            let name = url.lastPathComponent
            if excludedNames.contains(name) { return nil }
            if name.hasPrefix(".") { return nil }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true { return nil }
            return url
        }
        .sorted { lhs, rhs in
            let lDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lDate > rDate
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(I18n.t("dashboard.outputs.title"))
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
                Button {
                    refreshId = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("common.action.refresh", fallback: "Refresh")))
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: workspacePath))
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .buttonStyle(.plain)
                .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("dashboard.tooltip.openOutputsFolder")))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Divider()

            if outputItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(I18n.t("dashboard.outputs.empty"))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(outputItems, id: \.path) { url in
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: iconName(for: url))
                                .foregroundColor(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                    .foregroundColor(.primary)
                                Text(relativePath(for: url))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .id(refreshId)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func relativePath(for url: URL) -> String {
        url.path.replacingOccurrences(of: workspacePath + "/", with: "")
    }

    private func iconName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic": return "photo"
        case "mp4", "mov", "webm": return "film"
        case "md", "txt", "json", "csv", "xml", "yaml", "yml": return "doc.text"
        default: return "doc"
        }
    }
}
