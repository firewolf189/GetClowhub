import SwiftUI
import AppKit

struct UnifiedTooltipContent {
    let title: String
    var detail: String?
    var shortcut: String?

    init(title: String, detail: String? = nil, shortcut: String? = nil) {
        self.title = title
        self.detail = detail
        self.shortcut = shortcut
    }
}

extension UnifiedTooltipContent: Equatable {}

struct UnifiedTooltipModifier: ViewModifier {
    let content: UnifiedTooltipContent
    @State private var isHovering = false

    func body(content base: Content) -> some View {
        base
            .accessibilityLabel(self.content.title)
            .onHover { hovering in
                isHovering = hovering
            }
            .background(
                UnifiedTooltipHost(content: self.content, isHovering: isHovering)
            )
    }
}

private struct UnifiedTooltipHost: NSViewRepresentable {
    let content: UnifiedTooltipContent
    let isHovering: Bool

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(content: content)
        context.coordinator.setHovering(isHovering, sourceView: nsView)
    }

    func makeCoordinator() -> UnifiedTooltipCoordinator {
        UnifiedTooltipCoordinator(content: content)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: UnifiedTooltipCoordinator) {
        coordinator.close()
    }
}

private final class UnifiedTooltipCoordinator {
    private var content: UnifiedTooltipContent
    private var panel: NSPanel?
    private var hostingController: NSHostingController<UnifiedTooltipBubble>?
    private var isHovering = false
    private var pendingPresentWork: DispatchWorkItem?
    private var visibleFrame: NSRect?
    private var visibleContent: UnifiedTooltipContent?

    init(content: UnifiedTooltipContent) {
        self.content = content
    }

    func update(content: UnifiedTooltipContent) {
        self.content = content
        hostingController?.rootView = UnifiedTooltipBubble(content: content)
    }

    func setHovering(_ hovering: Bool, sourceView: NSView) {
        isHovering = hovering
        pendingPresentWork?.cancel()
        if hovering {
            present(relativeTo: sourceView)
        } else {
            close()
        }
    }

    func close() {
        isHovering = false
        pendingPresentWork?.cancel()
        pendingPresentWork = nil
        visibleFrame = nil
        visibleContent = nil
        panel?.orderOut(nil)
    }

    private func present(relativeTo sourceView: NSView) {
        let work = DispatchWorkItem { [weak self, weak sourceView] in
            guard let self, let sourceView else { return }
            guard self.isHovering else { return }
            guard sourceView.window != nil else { return }

            let panel = self.ensurePanel()
            let frame = self.panelFrame(relativeTo: sourceView)
            guard !panel.isVisible || self.visibleFrame != frame || self.visibleContent != self.content else { return }
            panel.setContentSize(frame.size)
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            self.visibleFrame = frame
            self.visibleContent = self.content
        }
        pendingPresentWork = work
        // Present in a floating panel so parent window clipping cannot hide the tooltip.
        DispatchQueue.main.async(execute: work)
    }

    private var fittingSize: NSSize {
        let view = hostingController?.view ?? NSHostingView(rootView: UnifiedTooltipBubble(content: content))
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        return NSSize(width: max(42, size.width), height: max(28, size.height))
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let controller = NSHostingController(rootView: UnifiedTooltipBubble(content: content))
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostingController = controller

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: controller.view.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = true
        panel.ignoresMouseEvents = true
        panel.contentView = controller.view
        self.panel = panel
        return panel
    }

    private func panelFrame(relativeTo sourceView: NSView) -> NSRect {
        let size = fittingSize
        guard let window = sourceView.window else {
            return NSRect(origin: .zero, size: size)
        }

        let sourceBounds = sourceView.convert(sourceView.bounds, to: nil)
        let sourceFrame = window.convertToScreen(sourceBounds)
        let x = sourceFrame.midX - (size.width / 2)
        let y = sourceFrame.maxY + 6
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

private struct UnifiedTooltipBubble: View {
    let content: UnifiedTooltipContent

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if let detail = content.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            if let shortcut = content.shortcut, !shortcut.isEmpty {
                KeyboardShortcutBadge(shortcut: shortcut)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, content.detail == nil ? 5 : 7)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
        )
    }
}

private struct KeyboardShortcutBadge: View {
    let shortcut: String

    var body: some View {
        Text(shortcut)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.primary.opacity(0.72))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.08))
            )
    }
}

extension View {
    func unifiedTooltip(_ content: UnifiedTooltipContent) -> some View {
        modifier(UnifiedTooltipModifier(content: content))
    }

    func unifiedIconTooltip(
        title: String,
        detail: String? = nil,
        shortcut: String? = nil
    ) -> some View {
        unifiedTooltip(UnifiedTooltipContent(title: title, detail: detail, shortcut: shortcut))
    }
}
