import SwiftUI
import AppKit
import SwiftTerm

// MARK: - Terminal Panel

struct TerminalPanelView: View {
    let workspacePath: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(I18n.t("dashboard.terminal.title"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            SwiftTermView(workspacePath: workspacePath)
        }
        .background(Color(NSColor.textBackgroundColor))
    }
}

private struct SwiftTermView: NSViewRepresentable {
    let workspacePath: String

    func makeNSView(context: Context) -> SwiftTerm.LocalProcessTerminalView {
        let tv = SwiftTerm.LocalProcessTerminalView(frame: .zero)
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let cwd: String
        if !workspacePath.isEmpty, FileManager.default.fileExists(atPath: workspacePath) {
            cwd = workspacePath
        } else {
            cwd = FileManager.default.homeDirectoryForCurrentUser.path
        }
        tv.startProcess(executable: shell, args: [], environment: nil, execName: nil, currentDirectory: cwd)
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        return tv
    }

    func updateNSView(_ nsView: SwiftTerm.LocalProcessTerminalView, context: Context) {}
}

struct TerminalDragHandle: View {
    @Binding var height: CGFloat
    @State private var dragStart: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 4)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStart == nil { dragStart = height }
                        let newHeight = (dragStart ?? height) - value.translation.height
                        height = min(max(newHeight, 80), 500)
                    }
                    .onEnded { _ in dragStart = nil }
            )
    }
}
