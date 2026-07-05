import SwiftUI
import AppKit

enum RightInspectorSplitMetrics {
    static let animationDuration: TimeInterval = 0.30
}

struct RightInspectorSidebarWidthCoordinator {
    var animateSidebarWidth: (CGFloat) -> Void
}

private struct RightInspectorSidebarWidthCoordinatorKey: EnvironmentKey {
    static let defaultValue = RightInspectorSidebarWidthCoordinator(animateSidebarWidth: { _ in })
}

extension EnvironmentValues {
    var rightInspectorSidebarWidthCoordinator: RightInspectorSidebarWidthCoordinator {
        get { self[RightInspectorSidebarWidthCoordinatorKey.self] }
        set { self[RightInspectorSidebarWidthCoordinatorKey.self] = newValue }
    }
}

struct RightInspectorSplitView<Content: View, Sidebar: View>: NSViewControllerRepresentable {
    let isSidebarExpanded: Bool
    let sidebarWidth: CGFloat
    let minSidebarWidth: CGFloat
    let maxSidebarWidth: CGFloat
    let contentUpdateID: AnyHashable
    let expandRequestID: Int
    let collapseRequestID: Int
    let onSidebarExpandFinished: () -> Void
    let onSidebarCollapseFinished: () -> Void
    let content: Content
    let sidebar: Sidebar

    init(
        isSidebarExpanded: Bool,
        sidebarWidth: CGFloat,
        minSidebarWidth: CGFloat,
        maxSidebarWidth: CGFloat,
        contentUpdateID: AnyHashable,
        expandRequestID: Int,
        collapseRequestID: Int,
        onSidebarExpandFinished: @escaping () -> Void,
        onSidebarCollapseFinished: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder sidebar: () -> Sidebar
    ) {
        self.isSidebarExpanded = isSidebarExpanded
        self.sidebarWidth = sidebarWidth
        self.minSidebarWidth = minSidebarWidth
        self.maxSidebarWidth = maxSidebarWidth
        self.contentUpdateID = contentUpdateID
        self.expandRequestID = expandRequestID
        self.collapseRequestID = collapseRequestID
        self.onSidebarExpandFinished = onSidebarExpandFinished
        self.onSidebarCollapseFinished = onSidebarCollapseFinished
        self.content = content()
        self.sidebar = sidebar()
    }

    func makeNSViewController(context: Context) -> NSViewController {
        let controller = RightInspectorSplitController()
        controller.loadViewIfNeeded()
        return controller
    }

    func updateNSViewController(_ controller: NSViewController, context: Context) {
        guard let inspectorController = controller as? RightInspectorSplitController else { return }

        inspectorController.update(
            content: AnyView(content),
            sidebar: AnyView(sidebar),
            isSidebarExpanded: isSidebarExpanded,
            sidebarWidth: sidebarWidth,
            minSidebarWidth: minSidebarWidth,
            maxSidebarWidth: maxSidebarWidth,
            contentUpdateID: contentUpdateID,
            expandRequestID: expandRequestID,
            collapseRequestID: collapseRequestID,
            onSidebarExpandFinished: onSidebarExpandFinished,
            onSidebarCollapseFinished: onSidebarCollapseFinished
        )
    }
}

private final class RightInspectorSplitController: NSViewController {
    private let contentHost = NSHostingController(rootView: AnyView(EmptyView()))
    private let sidebarRail = NSView()
    private let sidebarSeparator = NSBox()
    private let sidebarClipView = NSView()
    private let sidebarHost = NSHostingController(rootView: AnyView(EmptyView()))

    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var sidebarContentWidthConstraint: NSLayoutConstraint?
    private var contentMinWidthConstraint: NSLayoutConstraint?
    private var currentSidebarWidth: CGFloat = 0
    private var currentMinSidebarWidth: CGFloat = 240
    private var currentMaxSidebarWidth: CGFloat = 420
    private var currentIsSidebarExpanded = false
    private var hasInstalledLayout = false
    private var hasAppliedInitialLayout = false
    private var isAnimatingSidebar = false
    private var sidebarAnimationGeneration = 0
    private var currentContentUpdateID: AnyHashable?
    private var onSidebarExpandFinished: (() -> Void)?
    private var onSidebarCollapseFinished: (() -> Void)?
    private var lastExpandRequestID = 0
    private var lastCollapseRequestID = 0
    private var locallyManagedSidebarWidth: CGFloat?
    private var dragStartSidebarWidth: CGFloat = 0
    private lazy var sidebarWidthCoordinator = RightInspectorSidebarWidthCoordinator { [weak self] width in
        self?.animateExpandedSidebarWidth(to: width)
    }
    private let layoutEpsilon: CGFloat = 0.5

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installLayoutIfNeeded()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applySidebarWidth()
    }

    func update(
        content: AnyView,
        sidebar: AnyView,
        isSidebarExpanded: Bool,
        sidebarWidth: CGFloat,
        minSidebarWidth: CGFloat,
        maxSidebarWidth: CGFloat,
        contentUpdateID: AnyHashable,
        expandRequestID: Int,
        collapseRequestID: Int,
        onSidebarExpandFinished: @escaping () -> Void,
        onSidebarCollapseFinished: @escaping () -> Void
    ) {
        loadViewIfNeeded()
        installLayoutIfNeeded()

        if currentContentUpdateID != contentUpdateID {
            contentHost.rootView = content
            currentContentUpdateID = contentUpdateID
        }
        let previousTargetWidth = resolvedSidebarWidth()
        let shouldAnimate = currentIsSidebarExpanded != isSidebarExpanded
        let shouldExpandFromRequest = expandRequestID != lastExpandRequestID
        if shouldExpandFromRequest {
            lastExpandRequestID = expandRequestID
        }
        let shouldCollapseFromRequest = collapseRequestID != lastCollapseRequestID
        if shouldCollapseFromRequest {
            lastCollapseRequestID = collapseRequestID
        }
        let isCollapsingSidebar = (shouldAnimate && currentIsSidebarExpanded && !isSidebarExpanded && hasAppliedInitialLayout) || (shouldCollapseFromRequest && hasAppliedInitialLayout)
        let shouldDeferSidebarRootUpdate = isCollapsingSidebar || (isAnimatingSidebar && !currentIsSidebarExpanded)
        if !shouldDeferSidebarRootUpdate {
            sidebarHost.rootView = AnyView(sidebar.environment(\.rightInspectorSidebarWidthCoordinator, sidebarWidthCoordinator))
        }
        self.onSidebarExpandFinished = onSidebarExpandFinished
        self.onSidebarCollapseFinished = onSidebarCollapseFinished
        if let locallyManagedSidebarWidth, abs(sidebarWidth - locallyManagedSidebarWidth) <= layoutEpsilon {
            self.locallyManagedSidebarWidth = nil
        }
        let effectiveSidebarWidth = locallyManagedSidebarWidth ?? sidebarWidth
        currentSidebarWidth = effectiveSidebarWidth
        currentMinSidebarWidth = minSidebarWidth
        currentMaxSidebarWidth = maxSidebarWidth

        if shouldExpandFromRequest {
            currentIsSidebarExpanded = true
            setSidebarExpanded(
                true,
                animated: true,
                completion: {
                    self.sidebarHost.rootView = AnyView(sidebar.environment(\.rightInspectorSidebarWidthCoordinator, self.sidebarWidthCoordinator))
                    self.onSidebarExpandFinished?()
                }
            )
            return
        }

        if isAnimatingSidebar && !currentIsSidebarExpanded && isSidebarExpanded {
            return
        }

        if isAnimatingSidebar && currentIsSidebarExpanded && !isSidebarExpanded {
            return
        }

        if shouldCollapseFromRequest {
            currentIsSidebarExpanded = false
            setSidebarExpanded(
                false,
                animated: true,
                completion: {
                    self.sidebarHost.rootView = AnyView(sidebar.environment(\.rightInspectorSidebarWidthCoordinator, self.sidebarWidthCoordinator))
                    self.onSidebarCollapseFinished?()
                }
            )
            return
        }

        currentIsSidebarExpanded = isSidebarExpanded
        setSidebarExpanded(
            isSidebarExpanded,
            animated: shouldAnimate,
            completion: isCollapsingSidebar ? {
                self.sidebarHost.rootView = AnyView(sidebar.environment(\.rightInspectorSidebarWidthCoordinator, self.sidebarWidthCoordinator))
                self.onSidebarCollapseFinished?()
            } : nil
        )
        if isSidebarExpanded, !shouldAnimate {
            let targetWidth = resolvedSidebarWidth()
            if hasAppliedInitialLayout, abs(previousTargetWidth - targetWidth) > 0.5 {
                animateSidebarWidth(to: targetWidth)
            } else {
                applySidebarWidth()
            }
        }
    }

    private func installLayoutIfNeeded() {
        guard !hasInstalledLayout else { return }

        addChild(contentHost)
        addChild(sidebarHost)

        contentHost.view.translatesAutoresizingMaskIntoConstraints = false
        sidebarRail.translatesAutoresizingMaskIntoConstraints = false
        sidebarRail.clipsToBounds = true
        sidebarSeparator.translatesAutoresizingMaskIntoConstraints = false
        sidebarSeparator.boxType = .custom
        sidebarSeparator.wantsLayer = true
        sidebarSeparator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        sidebarClipView.translatesAutoresizingMaskIntoConstraints = false
        sidebarClipView.clipsToBounds = true
        sidebarHost.view.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(contentHost.view)
        view.addSubview(sidebarRail)
        sidebarRail.addSubview(sidebarSeparator)
        sidebarRail.addSubview(sidebarClipView)
        sidebarClipView.addSubview(sidebarHost.view)

        let sidebarWidthConstraint = sidebarRail.widthAnchor.constraint(equalToConstant: 0)
        let sidebarContentWidthConstraint = sidebarHost.view.widthAnchor.constraint(equalToConstant: 0)
        let contentMinWidthConstraint = contentHost.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 360)
        contentMinWidthConstraint.priority = .defaultHigh
        let separatorWidthConstraint = sidebarSeparator.widthAnchor.constraint(equalToConstant: 1)
        separatorWidthConstraint.priority = .fittingSizeCompression
        let resizePan = NSPanGestureRecognizer(target: self, action: #selector(handleSidebarResizePan(_:)))
        sidebarSeparator.addGestureRecognizer(resizePan)

        NSLayoutConstraint.activate([
            contentHost.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentHost.view.topAnchor.constraint(equalTo: view.topAnchor),
            contentHost.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentHost.view.trailingAnchor.constraint(equalTo: sidebarRail.leadingAnchor),
            sidebarRail.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarRail.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarRail.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sidebarSeparator.leadingAnchor.constraint(equalTo: sidebarRail.leadingAnchor),
            sidebarSeparator.topAnchor.constraint(equalTo: sidebarRail.topAnchor),
            sidebarSeparator.bottomAnchor.constraint(equalTo: sidebarRail.bottomAnchor),
            separatorWidthConstraint,
            sidebarClipView.leadingAnchor.constraint(equalTo: sidebarSeparator.trailingAnchor),
            sidebarClipView.topAnchor.constraint(equalTo: sidebarRail.topAnchor),
            sidebarClipView.bottomAnchor.constraint(equalTo: sidebarRail.bottomAnchor),
            sidebarClipView.trailingAnchor.constraint(equalTo: sidebarRail.trailingAnchor),
            sidebarHost.view.leadingAnchor.constraint(equalTo: sidebarClipView.leadingAnchor),
            sidebarHost.view.topAnchor.constraint(equalTo: sidebarClipView.topAnchor),
            sidebarHost.view.bottomAnchor.constraint(equalTo: sidebarClipView.bottomAnchor),
            sidebarContentWidthConstraint,
            sidebarWidthConstraint,
            contentMinWidthConstraint
        ])

        self.sidebarWidthConstraint = sidebarWidthConstraint
        self.sidebarContentWidthConstraint = sidebarContentWidthConstraint
        self.contentMinWidthConstraint = contentMinWidthConstraint
        hasInstalledLayout = true
    }

    @objc private func handleSidebarResizePan(_ recognizer: NSPanGestureRecognizer) {
        guard currentIsSidebarExpanded else { return }

        switch recognizer.state {
        case .began:
            invalidateSidebarAnimation()
            dragStartSidebarWidth = sidebarWidthConstraint?.constant ?? resolvedSidebarWidth()
        case .changed:
            let translation = recognizer.translation(in: view)
            let proposedWidth = dragStartSidebarWidth - translation.x
            let clampedWidth = clampedSidebarWidth(proposedWidth)
            locallyManagedSidebarWidth = clampedWidth
            currentSidebarWidth = clampedWidth
            setSidebarWidth(clampedWidth)
        case .ended, .cancelled, .failed:
            let currentWidth = sidebarWidthConstraint?.constant ?? resolvedSidebarWidth()
            let clampedWidth = clampedSidebarWidth(currentWidth)
            locallyManagedSidebarWidth = clampedWidth
            currentSidebarWidth = clampedWidth
            setSidebarWidth(clampedWidth)
            dragStartSidebarWidth = 0
        default:
            break
        }
    }

    private func setSidebarExpanded(_ isSidebarExpanded: Bool, animated: Bool, completion: (() -> Void)? = nil) {
        guard hasInstalledLayout else { return }

        if !hasAppliedInitialLayout {
            if isSidebarExpanded {
                setSidebarWidth(resolvedSidebarWidth())
            } else {
                setSidebarWidth(0)
            }
            hasAppliedInitialLayout = true
            completion?()
            return
        }

        let targetWidth = isSidebarExpanded ? resolvedSidebarWidth() : 0
        guard animated else {
            invalidateSidebarAnimation()
            if !isSidebarWidthApplied(targetWidth) {
                setSidebarWidth(targetWidth)
            }
            completion?()
            return
        }

        animateSidebarWidth(to: targetWidth, completion: completion)
    }

    private func resolvedSidebarWidth() -> CGFloat {
        let totalWidth = view.bounds.width
        guard totalWidth > 0 else { return currentSidebarWidth }

        let contentMinimumWidth = contentMinWidthConstraint?.constant ?? 360
        let availableSidebarWidth = max(0, totalWidth - contentMinimumWidth)
        let upperBound = min(currentMaxSidebarWidth, availableSidebarWidth)
        guard upperBound >= currentMinSidebarWidth else { return 0 }

        return min(max(currentSidebarWidth, currentMinSidebarWidth), upperBound)
    }

    private func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        let totalWidth = view.bounds.width
        let contentMinimumWidth = contentMinWidthConstraint?.constant ?? 360
        let availableSidebarWidth = totalWidth > 0 ? max(0, totalWidth - contentMinimumWidth) : currentMaxSidebarWidth
        let upperBound = min(currentMaxSidebarWidth, availableSidebarWidth)
        guard upperBound >= currentMinSidebarWidth else { return 0 }

        return min(max(width, currentMinSidebarWidth), upperBound)
    }

    private func setSidebarWidth(_ width: CGFloat) {
        let clampedWidth = max(0, width)
        guard !isSidebarWidthApplied(clampedWidth) else { return }
        sidebarWidthConstraint?.constant = clampedWidth
        if clampedWidth > 0 {
            sidebarContentWidthConstraint?.constant = clampedWidth
        }
        view.layoutSubtreeIfNeeded()
    }

    private func isSidebarWidthApplied(_ width: CGFloat) -> Bool {
        let targetWidth = max(0, width)
        let railWidth = sidebarWidthConstraint?.constant ?? 0
        guard abs(railWidth - targetWidth) <= layoutEpsilon else { return false }

        if targetWidth > 0 {
            let contentWidth = sidebarContentWidthConstraint?.constant ?? 0
            return abs(contentWidth - targetWidth) <= layoutEpsilon
        }

        return true
    }

    private func invalidateSidebarAnimation() {
        sidebarAnimationGeneration += 1
        isAnimatingSidebar = false
    }

    private func animateSidebarWidth(to width: CGFloat, completion: (() -> Void)? = nil) {
        let targetWidth = max(0, width)
        let sourceWidth = sidebarWidthConstraint?.constant ?? 0
        sidebarAnimationGeneration += 1
        let animationID = sidebarAnimationGeneration

        guard view.bounds.width > 0 else {
            setSidebarWidth(targetWidth)
            isAnimatingSidebar = false
            completion?()
            return
        }

        isAnimatingSidebar = true
        if targetWidth >= sourceWidth {
            sidebarContentWidthConstraint?.constant = targetWidth
        } else if (sidebarContentWidthConstraint?.constant ?? 0) <= 0 {
            sidebarContentWidthConstraint?.constant = max(currentSidebarWidth, currentMinSidebarWidth)
        }
        view.layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = RightInspectorSplitMetrics.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            self.sidebarWidthConstraint?.animator().constant = targetWidth
            self.view.layoutSubtreeIfNeeded()
        } completionHandler: {
            guard self.sidebarAnimationGeneration == animationID else { return }
            self.sidebarWidthConstraint?.constant = targetWidth
            self.sidebarContentWidthConstraint?.constant = targetWidth
            self.isAnimatingSidebar = false
            completion?()
        }
    }

    private func animateExpandedSidebarWidth(to width: CGFloat) {
        locallyManagedSidebarWidth = width
        currentSidebarWidth = width
        guard currentIsSidebarExpanded, hasAppliedInitialLayout else {
            setSidebarWidth(resolvedSidebarWidth())
            return
        }

        animateSidebarWidth(to: resolvedSidebarWidth())
    }

    private func applySidebarWidth() {
        guard hasInstalledLayout, hasAppliedInitialLayout, !isAnimatingSidebar else { return }
        if currentIsSidebarExpanded {
            setSidebarWidth(resolvedSidebarWidth())
        } else {
            setSidebarWidth(0)
        }
    }
}
