import SwiftUI
import AppKit

/// One-click "open document" chips under an assistant reply. Each chip is a
/// resolved, existing local file the reply referenced (see
/// `MessageFileReferences`); click opens it with the system default app,
/// the context menu reveals it in Finder.
struct MessageFileChipsRow: View {
    let paths: [String]
    /// When set, clicks preview in-app (right inspector); otherwise fall back
    /// to opening with the system default application.
    var onOpen: ((String) -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            ForEach(paths, id: \.self) { path in
                chip(for: path)
            }
        }
    }

    private func chip(for path: String) -> some View {
        let url = URL(fileURLWithPath: path)
        return Button {
            if let onOpen {
                onOpen(path)
            } else {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: iconName(for: url.pathExtension.lowercased()))
                    .font(.system(size: 11, weight: .medium))
                Text(url.lastPathComponent)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: 260, alignment: .leading)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(path)
        .contextMenu {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label(I18n.t("chat.fileChip.openExternal"), systemImage: "arrow.up.forward.app")
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Label(I18n.t("chat.fileChip.revealInFinder"), systemImage: "folder")
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            } label: {
                Label(I18n.t("chat.fileChip.copyPath"), systemImage: "doc.on.doc")
            }
        }
    }

    private func iconName(for ext: String) -> String {
        switch ext {
        case "pdf": return "doc.richtext"
        case "xlsx", "xls", "csv", "numbers": return "tablecells"
        case "doc", "docx", "pages", "md", "txt", "rtf": return "doc.text"
        case "png", "jpg", "jpeg", "gif", "webp", "heic": return "photo"
        case "pptx", "ppt", "key": return "rectangle.on.rectangle"
        case "zip", "tar", "gz": return "archivebox"
        case "mp4", "mov": return "film"
        case "mp3", "wav", "m4a": return "waveform"
        default: return "doc"
        }
    }
}
