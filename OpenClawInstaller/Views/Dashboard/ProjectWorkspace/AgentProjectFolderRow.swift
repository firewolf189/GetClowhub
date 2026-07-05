import SwiftUI

struct AgentProjectFolderRow<Sessions: View>: View {
    let group: ProjectSessionGroup
    let backgroundColor: (Bool) -> SwiftUI.Color
    let onToggle: () -> Void
    let onNewSession: () -> Void
    let onRevealInFinder: () -> Void
    let onRemoveFromAgent: () -> Void
    @ViewBuilder let sessions: () -> Sessions

    var body: some View {
        SidebarCollapsibleRow(
            title: group.project.displayName,
            titleFont: .system(size: 13.5, weight: .regular),
            isExpanded: !group.binding.isCollapsed,
            rowHeight: 24,
            verticalPadding: 5,
            backgroundColor: backgroundColor,
            onToggle: onToggle,
            icon: {
                SidebarProjectBookIcon(isExpanded: !group.binding.isCollapsed, size: 18)
            },
            actions: {
                Button(action: onNewSession) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(I18n.t("workspace.project.newChat"))
            },
            children: sessions
        )
        .contextMenu {
            Button(action: onNewSession) {
                Label(I18n.t("workspace.project.newChat"), systemImage: "plus")
            }
            Button(action: onRevealInFinder) {
                Label(I18n.t("workspace.project.revealInFinder"), systemImage: "folder")
            }
            Divider()
            Button(role: .destructive, action: onRemoveFromAgent) {
                Label(I18n.t("workspace.project.removeFromAgent"), systemImage: "minus.circle")
            }
        }
    }
}

private struct SidebarProjectBookIcon: View {
    let isExpanded: Bool
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: isExpanded ? "book" : "book.closed")
            .font(.system(size: size, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
