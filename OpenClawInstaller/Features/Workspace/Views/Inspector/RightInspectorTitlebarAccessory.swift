import SwiftUI
import AppKit

private let rightInspectorTitlebarAccessoryID = NSUserInterfaceItemIdentifier("GetClowHub.RightInspectorTitlebarAccessory")

struct RightInspectorTitlebarAccessoryInstaller<Accessory: View>: NSViewRepresentable {
    let isVisible: Bool
    let width: CGFloat
    let height: CGFloat
    let accessory: Accessory

    init(
        isVisible: Bool,
        width: CGFloat,
        height: CGFloat = 44,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.isVisible = isVisible
        self.width = width
        self.height = height
        self.accessory = accessory()
    }

    func makeCoordinator() -> RightInspectorTitlebarAccessoryCoordinator {
        RightInspectorTitlebarAccessoryCoordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.update(
                window: view.window,
                isVisible: isVisible,
                width: width,
                height: height,
                rootView: AnyView(accessory)
            )
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.update(
                window: nsView.window,
                isVisible: isVisible,
                width: width,
                height: height,
                rootView: AnyView(accessory)
            )
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: RightInspectorTitlebarAccessoryCoordinator) {
        coordinator.remove()
    }
}

final class RightInspectorTitlebarAccessoryCoordinator {
    private weak var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    private var accessoryController: NSTitlebarAccessoryViewController?
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?

    func update(
        window targetWindow: NSWindow?,
        isVisible: Bool,
        width: CGFloat,
        height: CGFloat,
        rootView: AnyView
    ) {
        guard let targetWindow else { return }

        if window !== targetWindow {
            remove()
            window = targetWindow
        }

        removeStaleAccessories(from: targetWindow)

        let hostingController = hostingController ?? NSHostingController(rootView: rootView)
        hostingController.rootView = rootView
        hostingController.view.identifier = rightInspectorTitlebarAccessoryID
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        self.hostingController = hostingController

        let accessoryController = accessoryController ?? NSTitlebarAccessoryViewController()
        if self.accessoryController == nil {
            accessoryController.layoutAttribute = .right
            accessoryController.view = hostingController.view
            targetWindow.addTitlebarAccessoryViewController(accessoryController)
            self.accessoryController = accessoryController
            widthConstraint = hostingController.view.widthAnchor.constraint(equalToConstant: 0)
            heightConstraint = hostingController.view.heightAnchor.constraint(equalToConstant: height)
            NSLayoutConstraint.activate([widthConstraint, heightConstraint].compactMap { $0 })
        }

        applyVisibility(
            isVisible,
            width: width,
            height: height,
            hostingController: hostingController
        )
    }

    private func applyVisibility(
        _ isVisible: Bool,
        width: CGFloat,
        height: CGFloat,
        hostingController: NSHostingController<AnyView>
    ) {
        let targetWidth = isVisible ? max(width, 44) : 0
        hostingController.view.isHidden = !isVisible
        hostingController.view.alphaValue = isVisible ? 1 : 0
        if let widthConstraint, abs(widthConstraint.constant - targetWidth) > 0.5 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = RightInspectorSplitMetrics.animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                self.widthConstraint?.animator().constant = targetWidth
                hostingController.view.superview?.layoutSubtreeIfNeeded()
            }
        } else {
            widthConstraint?.constant = targetWidth
        }
        heightConstraint?.constant = height
    }

    func remove() {
        guard let accessoryController else {
            hostingController = nil
            widthConstraint = nil
            heightConstraint = nil
            window = nil
            return
        }

        if let window,
           let index = window.titlebarAccessoryViewControllers.firstIndex(where: { $0 === accessoryController }) {
            window.removeTitlebarAccessoryViewController(at: index)
        }

        self.accessoryController = nil
        hostingController = nil
        widthConstraint = nil
        heightConstraint = nil
        window = nil
    }

    private func removeStaleAccessories(from window: NSWindow) {
        let indexedControllers = window.titlebarAccessoryViewControllers.enumerated()
        for (index, controller) in indexedControllers.reversed() {
            guard controller !== accessoryController,
                  controller.view.identifier == rightInspectorTitlebarAccessoryID else {
                continue
            }
            window.removeTitlebarAccessoryViewController(at: index)
        }
    }
}

struct RightInspectorTitlebarAccessory: View {
    let isTerminalOpen: Bool
    let isExpanded: Bool
    let toggleTerminal: () -> Void
    let toggle: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggleTerminal) {
                Image(systemName: "terminal")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isTerminalOpen ? .accentColor : .secondary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .unifiedTitlebarTooltip(title: isTerminalOpen ? I18n.t("dashboard.tooltip.hideTerminal") : I18n.t("dashboard.tooltip.showTerminal"))

            Button(action: isExpanded ? close : toggle) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .unifiedTitlebarTooltip(title: isExpanded ? I18n.t("dashboard.tooltip.hideOutputs") : I18n.t("dashboard.tooltip.showOutputs"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}
