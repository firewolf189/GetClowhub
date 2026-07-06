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

enum UnifiedTooltipPlacement {
    case standard
    case titlebar
}

struct UnifiedTooltipModifier: ViewModifier {
    let content: UnifiedTooltipContent
    var placement: UnifiedTooltipPlacement = .standard

    func body(content base: Content) -> some View {
        base
            .accessibilityLabel(self.content.title)
            .background(
                UnifiedTooltipAnchor(content: self.content, placement: placement)
            )
    }
}

private struct UnifiedTooltipAnchor: NSViewRepresentable {
    let content: UnifiedTooltipContent
    let placement: UnifiedTooltipPlacement

    func makeNSView(context: Context) -> UnifiedTooltipAnchorView {
        let view = UnifiedTooltipAnchorView(frame: .zero)
        view.configure(content: content, placement: placement)
        return view
    }

    func updateNSView(_ nsView: UnifiedTooltipAnchorView, context: Context) {
        nsView.configure(content: content, placement: placement)
    }

    static func dismantleNSView(_ nsView: UnifiedTooltipAnchorView, coordinator: ()) {
        nsView.detach()
    }
}

private final class UnifiedTooltipAnchorView: NSView {
    private let id = UUID()
    private var currentContent: UnifiedTooltipContent?
    private var currentPlacement: UnifiedTooltipPlacement = .standard
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        guard let currentContent else { return }
        UnifiedTooltipPresenter.shared.show(content: currentContent, placement: currentPlacement, id: id, sourceView: self)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        UnifiedTooltipPresenter.shared.hide(id: id)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            detach()
        } else {
            refreshIfHovering()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshIfHovering()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        refreshIfHovering()
    }

    func configure(content: UnifiedTooltipContent, placement: UnifiedTooltipPlacement) {
        guard currentContent != content || currentPlacement != placement else { return }
        currentContent = content
        currentPlacement = placement
        refreshIfHovering()
    }

    func detach() {
        isHovering = false
        UnifiedTooltipPresenter.shared.hide(id: id)
    }

    deinit {
        detach()
    }

    private func refreshIfHovering() {
        guard isHovering, let currentContent, window != nil else { return }
        UnifiedTooltipPresenter.shared.show(content: currentContent, placement: currentPlacement, id: id, sourceView: self)
    }
}

private final class UnifiedTooltipPresenter {
    static let shared = UnifiedTooltipPresenter()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<UnifiedTooltipBubble>?
    private var activeID: UUID?
    private weak var activeSourceView: NSView?
    private var activeContent: UnifiedTooltipContent?
    private var activePlacement: UnifiedTooltipPlacement?
    private var renderedContent: UnifiedTooltipContent?
    private var cachedContent: UnifiedTooltipContent?
    private var cachedSize: NSSize?
    private var pendingPresentWork: DispatchWorkItem?
    private var visibleFrame: NSRect?
    private var visibleContent: UnifiedTooltipContent?

    private init() {}

    func show(content: UnifiedTooltipContent, placement: UnifiedTooltipPlacement, id: UUID, sourceView: NSView) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak sourceView] in
                guard let sourceView else { return }
                self.show(content: content, placement: placement, id: id, sourceView: sourceView)
            }
            return
        }

        let sourceChanged = activeSourceView !== sourceView
        guard activeID != id || activeContent != content || activePlacement != placement || sourceChanged || panel?.isVisible != true else {
            presentIfNeeded(content: content, placement: placement, id: id, sourceView: sourceView)
            return
        }

        activeID = id
        activeContent = content
        activePlacement = placement
        activeSourceView = sourceView
        pendingPresentWork?.cancel()

        let work = DispatchWorkItem { [weak self, weak sourceView] in
            guard let self, let sourceView else { return }
            guard self.activeID == id, self.activeContent == content, self.activePlacement == placement, self.activeSourceView === sourceView else { return }
            self.presentIfNeeded(content: content, placement: placement, id: id, sourceView: sourceView)
        }
        pendingPresentWork = work
        // Present in a floating panel so parent window clipping cannot hide the tooltip.
        DispatchQueue.main.async(execute: work)
    }

    func hide(id: UUID) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.hide(id: id)
            }
            return
        }

        guard activeID == id else { return }
        activeID = nil
        activeSourceView = nil
        activeContent = nil
        activePlacement = nil
        pendingPresentWork?.cancel()
        pendingPresentWork = nil
        visibleFrame = nil
        visibleContent = nil
        panel?.orderOut(nil)
    }

    private func presentIfNeeded(content: UnifiedTooltipContent, placement: UnifiedTooltipPlacement, id: UUID, sourceView: NSView) {
        guard activeID == id, sourceView.window != nil else {
            hide(id: id)
            return
        }

        let panel = ensurePanel(content: content)
        let frame = panelFrame(for: content, placement: placement, relativeTo: sourceView)
        guard !panel.isVisible || visibleFrame != frame || visibleContent != content else { return }
        panel.setContentSize(frame.size)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        visibleFrame = frame
        visibleContent = content
    }

    private func updateRenderedContentIfNeeded(_ content: UnifiedTooltipContent) {
        guard renderedContent != content else { return }
        hostingController?.rootView = UnifiedTooltipBubble(content: content)
        renderedContent = content
        cachedContent = nil
        cachedSize = nil
    }

    private func fittingSize(for content: UnifiedTooltipContent) -> NSSize {
        if cachedContent == content, let cachedSize {
            return cachedSize
        }
        let panel = ensurePanel(content: content)
        guard let view = panel.contentView else {
            return NSSize(width: 42, height: 28)
        }
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        let resolvedSize = NSSize(width: max(42, size.width), height: max(28, size.height))
        cachedContent = content
        cachedSize = resolvedSize
        return resolvedSize
    }

    private func ensurePanel(content: UnifiedTooltipContent) -> NSPanel {
        if let panel {
            updateRenderedContentIfNeeded(content)
            return panel
        }

        let controller = NSHostingController(rootView: UnifiedTooltipBubble(content: content))
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostingController = controller
        renderedContent = content

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
        panel.isReleasedWhenClosed = false
        panel.contentView = controller.view
        self.panel = panel
        return panel
    }

    private func panelFrame(for content: UnifiedTooltipContent, placement: UnifiedTooltipPlacement, relativeTo sourceView: NSView) -> NSRect {
        let size = fittingSize(for: content)
        guard sourceView.window != nil,
              let sourceFrame = sourceRectOnScreen(for: sourceView) else {
            return NSRect(origin: .zero, size: size)
        }

        let screenFrame = containerFrame(for: sourceView)
        let preferredX = sourceFrame.midX - (size.width / 2)
        let minX = screenFrame.minX + 8
        let maxX = screenFrame.maxX - size.width - 8
        let clampedX = min(max(preferredX, minX), maxX)

        let regularGap: CGFloat = 6
        let topEdgeBelowGap: CGFloat = 18
        let isNearTopEdge = sourceFrame.maxY > screenFrame.maxY - 56
        let belowGap = isNearTopEdge ? topEdgeBelowGap : regularGap
        let aboveY = sourceFrame.maxY + regularGap
        let belowY = sourceFrame.minY - size.height - belowGap
        let fitsAbove = aboveY + size.height <= screenFrame.maxY - 8
        let fitsBelow = belowY >= screenFrame.minY + 8
        let preferBelow = isNearTopEdge && fitsBelow
        let y = if placement == .titlebar {
            titlebarSafeY(for: sourceView, sourceFrame: sourceFrame, tooltipSize: size, containerFrame: screenFrame)
        } else if preferBelow || !fitsAbove {
            max(screenFrame.minY + 8, belowY)
        } else {
            aboveY
        }

        return NSRect(x: clampedX, y: y, width: size.width, height: size.height)
    }

    private func titlebarSafeY(for sourceView: NSView, sourceFrame: NSRect, tooltipSize size: NSSize, containerFrame: NSRect) -> CGFloat {
        let margin: CGFloat = 8
        let titlebarReservedHeight: CGFloat = 64
        let topReservedY = containerFrame.maxY - titlebarReservedHeight - size.height
        let belowSourceY = sourceFrame.minY - size.height - margin
        let fallbackY = containerFrame.maxY - size.height - 52
        let safeYWithoutContentLayout = min(topReservedY, belowSourceY)
        guard let window = sourceView.window else {
            return clampTooltipY(min(safeYWithoutContentLayout, fallbackY), tooltipSize: size, containerFrame: containerFrame)
        }

        let contentLayoutFrame = window.convertToScreen(window.contentLayoutRect)
        guard !contentLayoutFrame.isNull, !contentLayoutFrame.isEmpty else {
            return clampTooltipY(min(safeYWithoutContentLayout, fallbackY), tooltipSize: size, containerFrame: containerFrame)
        }

        let preferredY = contentLayoutFrame.maxY - size.height - margin
        return clampTooltipY(min(safeYWithoutContentLayout, preferredY), tooltipSize: size, containerFrame: containerFrame)
    }

    private func clampTooltipY(_ y: CGFloat, tooltipSize size: NSSize, containerFrame: NSRect) -> CGFloat {
        let margin: CGFloat = 8
        let minY = containerFrame.minY + margin
        let maxY = containerFrame.maxY - size.height - margin
        guard maxY >= minY else { return minY }
        return min(max(y, minY), maxY)
    }

    private func sourceRectOnScreen(for sourceView: NSView) -> NSRect? {
        guard let window = sourceView.window else { return nil }
        let anchorView = sourceView.superview ?? sourceView
        let sourceBounds = anchorView.convert(anchorView.bounds, to: nil)
        return window.convertToScreen(sourceBounds)
    }

    private func containerFrame(for sourceView: NSView) -> NSRect {
        guard let window = sourceView.window else {
            return sourceView.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        }
        let windowFrame = window.frame
        guard let screenFrame = window.screen?.visibleFrame else {
            return windowFrame
        }
        let clippedFrame = window.frame.intersection(screenFrame)
        if clippedFrame.isNull || clippedFrame.isEmpty {
            return screenFrame
        }
        return clippedFrame
    }

}

private struct UnifiedTooltipBubble: View {
    let content: UnifiedTooltipContent

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.86))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if let detail = content.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.58))
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
            .foregroundStyle(Color.black.opacity(0.72))
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

    func unifiedTitlebarTooltip(title: String) -> some View {
        modifier(UnifiedTooltipModifier(content: UnifiedTooltipContent(title: title), placement: .titlebar))
    }

    func unifiedIconTooltip(
        title: String,
        detail: String? = nil,
        shortcut: String? = nil
    ) -> some View {
        unifiedTooltip(UnifiedTooltipContent(title: title, detail: detail, shortcut: shortcut))
    }
}
