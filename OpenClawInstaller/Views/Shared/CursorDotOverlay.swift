import SwiftUI
import AppKit
import Combine

struct CursorDotConfiguration {
    var dotSize: CGFloat = 5
    var ringSize: CGFloat = 20
    var smoothing: CGFloat = 0.18
    var dotColor: Color = .white
    var ringColor: Color = .white.opacity(0.74)
}

struct CursorDotOverlay: View {
    static let coordinateSpaceName = "CursorDotOverlayCoordinateSpace"

    let isEnabled: Bool
    let configuration: CursorDotConfiguration
    let disabledFrames: [CGRect]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var state = CursorDotState()

    private var effectiveEnabled: Bool {
        isEnabled && !reduceMotion
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            CursorDotTrackingView(
                isEnabled: effectiveEnabled,
                state: state,
                disabledFrames: disabledFrames
            )

            TimelineView(.animation) { context in
                cursorVisuals
                    .onChange(of: context.date) { _, _ in
                        state.advanceRing(smoothing: configuration.smoothing)
                    }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var cursorVisuals: some View {
        if effectiveEnabled, state.isVisible, let pointer = state.pointerLocation {
            let ring = state.ringLocation ?? pointer

            Circle()
                .stroke(configuration.ringColor, lineWidth: 1)
                .blendMode(.difference)
                .frame(width: configuration.ringSize, height: configuration.ringSize)
                .position(ring)

            Circle()
                .fill(configuration.dotColor)
                .blendMode(.difference)
                .frame(width: configuration.dotSize, height: configuration.dotSize)
                .position(pointer)
        }
    }
}

struct CursorDotOverlayModifier: ViewModifier {
    let isEnabled: Bool
    let configuration: CursorDotConfiguration

    @State private var disabledFrames: [CGRect] = []

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: CursorDotOverlay.coordinateSpaceName)
            .onPreferenceChange(CursorDotDisabledPreferenceKey.self) { frames in
                disabledFrames = frames
            }
            .overlay {
                CursorDotOverlay(
                    isEnabled: isEnabled,
                    configuration: configuration,
                    disabledFrames: disabledFrames
                )
            }
    }
}

extension View {
    func cursorDotOverlay(
        isEnabled: Bool = true,
        configuration: CursorDotConfiguration = CursorDotConfiguration()
    ) -> some View {
        modifier(CursorDotOverlayModifier(isEnabled: isEnabled, configuration: configuration))
    }

    func cursorDotDisabledRegion() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CursorDotDisabledPreferenceKey.self,
                    value: [proxy.frame(in: .named(CursorDotOverlay.coordinateSpaceName))]
                )
            }
        )
    }
}

private struct CursorDotDisabledPreferenceKey: PreferenceKey {
    static var defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

private final class CursorDotState: ObservableObject {
    @Published var pointerLocation: CGPoint?
    @Published var ringLocation: CGPoint?
    @Published var isVisible = false

    func updatePointer(_ point: CGPoint, visible: Bool) {
        pointerLocation = point
        if ringLocation == nil {
            ringLocation = point
        }
        isVisible = visible
    }

    func hide() {
        isVisible = false
    }

    func advanceRing(smoothing: CGFloat) {
        guard let pointerLocation else { return }
        guard let currentRing = ringLocation else {
            ringLocation = pointerLocation
            return
        }

        ringLocation = CGPoint(
            x: currentRing.x + (pointerLocation.x - currentRing.x) * smoothing,
            y: currentRing.y + (pointerLocation.y - currentRing.y) * smoothing
        )
    }
}

private struct CursorDotTrackingView: NSViewRepresentable {
    let isEnabled: Bool
    @ObservedObject var state: CursorDotState
    let disabledFrames: [CGRect]

    func makeNSView(context: Context) -> CursorDotTrackingNSView {
        let view = CursorDotTrackingNSView()
        view.state = state
        view.isEffectEnabled = isEnabled
        view.disabledFrames = disabledFrames
        return view
    }

    func updateNSView(_ nsView: CursorDotTrackingNSView, context: Context) {
        nsView.state = state
        nsView.disabledFrames = disabledFrames
        nsView.isEffectEnabled = isEnabled
    }
}

private final class CursorDotTrackingNSView: NSView {
    weak var state: CursorDotState?
    var disabledFrames: [CGRect] = []
    var isEffectEnabled = true {
        didSet {
            if !isEffectEnabled {
                state?.hide()
                setSystemCursorHidden(false)
            }
        }
    }

    private var trackingArea: NSTrackingArea?
    private var isSystemCursorHidden = false
    private var windowObservers: [NSObjectProtocol] = []

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [
            .activeInKeyWindow,
            .inVisibleRect,
            .mouseEnteredAndExited,
            .mouseMoved
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func mouseEntered(with event: NSEvent) {
        updatePointer(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updatePointer(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        state?.hide()
        setSystemCursorHidden(false)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeWindowObservers()
            setSystemCursorHidden(false)
            state?.hide()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installWindowObservers()
    }

    deinit {
        removeWindowObservers()
        setSystemCursorHidden(false)
    }

    private func updatePointer(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let inside = bounds.contains(point)

        guard isEffectEnabled, inside else {
            state?.hide()
            setSystemCursorHidden(false)
            return
        }

        if isDisabledRegion(at: point) {
            state?.hide()
            setSystemCursorHidden(false)
            return
        }

        state?.updatePointer(point, visible: true)
        setSystemCursorHidden(true)
    }

    private func isDisabledRegion(at point: CGPoint) -> Bool {
        disabledFrames.contains { $0.insetBy(dx: -2, dy: -2).contains(point) }
    }

    private func setSystemCursorHidden(_ hidden: Bool) {
        guard hidden != isSystemCursorHidden else { return }

        if hidden {
            NSCursor.hide()
        } else {
            NSCursor.unhide()
        }
        isSystemCursorHidden = hidden
    }

    private func installWindowObservers() {
        removeWindowObservers()
        guard let window else { return }

        let center = NotificationCenter.default
        windowObservers.append(
            center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.state?.hide()
                self?.setSystemCursorHidden(false)
            }
        )
        windowObservers.append(
            center.addObserver(
                forName: NSWindow.didMiniaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.state?.hide()
                self?.setSystemCursorHidden(false)
            }
        )
    }

    private func removeWindowObservers() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
    }
}
