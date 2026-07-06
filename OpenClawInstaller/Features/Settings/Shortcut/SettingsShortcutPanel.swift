import SwiftUI
import AppKit

struct SettingsShortcutPanelButton: View {
    let shortcutState: SettingsShortcutState
    let loadShortcutData: () async -> Void
    let isActive: Bool
    let highlightColor: (Bool) -> SwiftUI.Color
    let onBeforeToggle: () -> Void
    let onOpenSettingsSection: (SettingsPageSection) -> Void
    @State private var isPanelPresented = false

    var body: some View {
        Button {
            onBeforeToggle()
            isPanelPresented.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .frame(width: 18, height: 18)
                Text(I18n.t("Settings"))
                    .lineLimit(1)
                Spacer()
            }
            .font(.system(size: 14, weight: .regular))
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(highlightColor(isPanelPresented || isActive))
            )
        }
        .buttonStyle(.plain)
        .background {
            SettingsShortcutPanelHost(
                isPresented: $isPanelPresented,
                shortcutState: shortcutState,
                loadShortcutData: loadShortcutData,
                onOpenSettingsSection: onOpenSettingsSection
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .allowsHitTesting(false)
        }
    }
}

private struct SettingsShortcutPanelHost: NSViewRepresentable {
    @Binding var isPresented: Bool
    let shortcutState: SettingsShortcutState
    let loadShortcutData: () async -> Void
    let onOpenSettingsSection: (SettingsPageSection) -> Void
    #if REQUIRE_LOGIN
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var membershipManager: MembershipManager
    #endif

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let presentation = $isPresented
        let menu = SettingsShortcutMenu(
            shortcutState: shortcutState,
            loadShortcutData: loadShortcutData,
            onSizeChange: { size in
                context.coordinator.updateContentSize(size)
            },
            onDismiss: {
                presentation.wrappedValue = false
            },
            onOpenSettingsSection: { section in
                presentation.wrappedValue = false
                onOpenSettingsSection(section)
            }
        )
        .frame(width: SettingsShortcutPanelMetrics.width)

        #if REQUIRE_LOGIN
        let rootView = AnyView(
            menu
                .environmentObject(authManager)
                .environmentObject(membershipManager)
        )
        #else
        let rootView = AnyView(menu)
        #endif

        context.coordinator.update(
            rootView: rootView,
            isPresented: isPresented,
            onClose: {
                presentation.wrappedValue = false
            },
            relativeTo: nsView
        )
    }

    func makeCoordinator() -> SettingsShortcutPanelCoordinator {
        SettingsShortcutPanelCoordinator()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: SettingsShortcutPanelCoordinator) {
        coordinator.closeImmediately(updateBinding: false)
    }
}

private final class SettingsShortcutPanelCoordinator {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var pendingPresentWork: DispatchWorkItem?
    private var eventMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var onClose: () -> Void = {}
    private weak var sourceView: NSView?
    private var lastContentSize: CGSize = .zero

    func update(
        rootView: AnyView,
        isPresented: Bool,
        onClose: @escaping () -> Void,
        relativeTo sourceView: NSView
    ) {
        self.onClose = onClose
        self.sourceView = sourceView

        if isPresented {
            let panel = ensurePanel(rootView: rootView)
            hostingController?.rootView = rootView
            resizePanel(panel)
            schedulePresent(relativeTo: sourceView)
        } else {
            if let hostingController {
                hostingController.rootView = rootView
            }
            closeImmediately(updateBinding: false)
        }
    }

    func updateContentSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        guard abs(size.width - lastContentSize.width) > 0.5 ||
                abs(size.height - lastContentSize.height) > 0.5 else { return }
        lastContentSize = size

        guard let panel else { return }
        let height = constrainedPanelHeight(for: size.height)
        guard abs(panel.frame.height - height) > 0.5 else { return }

        panel.setContentSize(NSSize(width: SettingsShortcutPanelMetrics.width, height: height))
        if let sourceView, panel.isVisible {
            panel.setFrame(panelFrame(relativeTo: sourceView), display: true)
        }
    }

    func closeImmediately(updateBinding: Bool = true) {
        pendingPresentWork?.cancel()
        pendingPresentWork = nil
        removeEventMonitors()
        panel?.orderOut(nil)
        if updateBinding {
            onClose()
        }
    }

    private func ensurePanel(rootView: AnyView) -> NSPanel {
        if let panel {
            return panel
        }

        let controller = NSHostingController(rootView: rootView)
        hostingController = controller

        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SettingsShortcutPanelMetrics.width,
                height: SettingsShortcutPanelMetrics.maxHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .aqua)
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = controller
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.masksToBounds = false
        self.panel = panel
        return panel
    }

    private func resizePanel(_ panel: NSPanel) {
        guard let hostingController else { return }
        let fittingSize = hostingController.sizeThatFits(
            in: NSSize(
                width: SettingsShortcutPanelMetrics.width,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        let height = constrainedPanelHeight(for: fittingSize.height)
        panel.setContentSize(NSSize(width: SettingsShortcutPanelMetrics.width, height: height))
    }

    private func schedulePresent(relativeTo sourceView: NSView) {
        pendingPresentWork?.cancel()
        let work = DispatchWorkItem { [weak self, weak sourceView] in
            guard let self, let sourceView, let panel = self.panel else { return }
            guard sourceView.window != nil, !sourceView.bounds.isEmpty else { return }
            self.resizePanel(panel)
            panel.setFrame(self.panelFrame(relativeTo: sourceView), display: true)
            panel.orderFrontRegardless()
            self.installEventMonitors()
        }
        pendingPresentWork = work
        DispatchQueue.main.async(execute: work)
    }

    private func panelFrame(relativeTo sourceView: NSView) -> NSRect {
        guard let window = sourceView.window, let panel else {
            return NSRect(
                x: 0,
                y: 0,
                width: SettingsShortcutPanelMetrics.width,
                height: SettingsShortcutPanelMetrics.maxHeight
            )
        }

        let sourceFrameInWindow = sourceView.convert(sourceView.bounds, to: nil)
        let sourceFrameOnScreen = window.convertToScreen(sourceFrameInWindow)
        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let windowFrameOnScreen = window.frame.intersection(screenFrame)
        let constraintFrame = windowFrameOnScreen.isEmpty ? screenFrame : windowFrameOnScreen
        let availableHeight = max(
            SettingsShortcutPanelMetrics.minHeight,
            constraintFrame.height - (SettingsShortcutPanelMetrics.verticalWindowInset * 2)
        )
        let panelHeight = min(panel.frame.height, availableHeight)
        if abs(panel.frame.height - panelHeight) > 0.5 {
            panel.setContentSize(NSSize(width: SettingsShortcutPanelMetrics.width, height: panelHeight))
        }

        return anchorAboveSource(
            sourceFrameOnScreen: sourceFrameOnScreen,
            panelHeight: panelHeight,
            constraintFrame: constraintFrame
        )
    }

    private func anchorAboveSource(
        sourceFrameOnScreen: NSRect,
        panelHeight: CGFloat,
        constraintFrame: NSRect
    ) -> NSRect {
        let desiredX = sourceFrameOnScreen.minX
        let x = max(
            constraintFrame.minX + SettingsShortcutPanelMetrics.horizontalWindowInset,
            min(
                desiredX,
                constraintFrame.maxX - SettingsShortcutPanelMetrics.width - SettingsShortcutPanelMetrics.horizontalWindowInset
            )
        )
        let desiredY = sourceFrameOnScreen.maxY + SettingsShortcutPanelMetrics.verticalSourceGap
        let y = max(
            constraintFrame.minY + SettingsShortcutPanelMetrics.verticalWindowInset,
            min(
                desiredY,
                constraintFrame.maxY - panelHeight - SettingsShortcutPanelMetrics.verticalWindowInset
            )
        )

        return NSRect(x: x, y: y, width: SettingsShortcutPanelMetrics.width, height: panelHeight)
    }

    private func constrainedPanelHeight(for contentHeight: CGFloat) -> CGFloat {
        let availableHeight: CGFloat
        if let sourceView, let window = sourceView.window {
            let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let windowFrameOnScreen = window.frame.intersection(screenFrame)
            let constraintFrame = windowFrameOnScreen.isEmpty ? screenFrame : windowFrameOnScreen
            availableHeight = constraintFrame.height - (SettingsShortcutPanelMetrics.verticalWindowInset * 2)
        } else {
            availableHeight = SettingsShortcutPanelMetrics.maxHeight
        }
        return min(
            max(contentHeight, SettingsShortcutPanelMetrics.minHeight),
            min(SettingsShortcutPanelMetrics.maxHeight, max(SettingsShortcutPanelMetrics.minHeight, availableHeight))
        )
    }

    private func installEventMonitors() {
        removeEventMonitors()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else { return event }
            let mouseLocation = NSEvent.mouseLocation
            if !panel.frame.contains(mouseLocation) && !self.sourceFrameOnScreen.contains(mouseLocation) {
                self.closeImmediately()
            }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.closeImmediately()
        }
    }

    private func removeEventMonitors() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
    }

    private var sourceFrameOnScreen: NSRect {
        guard let sourceView, let window = sourceView.window else { return .zero }
        return window.convertToScreen(sourceView.convert(sourceView.bounds, to: nil))
    }
}
