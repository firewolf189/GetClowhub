import SwiftUI

struct SmoothScrollView<Content: View>: View {
    private let axes: Axis.Set
    private let content: () -> Content
    private let coordinateSpaceName = "smoothScrollSpace-\(UUID().uuidString)"

    @Environment(\.colorScheme) private var colorScheme
    @State private var metrics = SmoothScrollContentMetrics()
    @State private var viewportHeight: CGFloat = 1
    @State private var showIndicator = false
    @State private var indicatorHideTask: DispatchWorkItem?

    init(
        _ axes: Axis.Set = .vertical,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.axes = axes
        self.content = content
    }

    var body: some View {
        ScrollView(axes, showsIndicators: false) {
            content()
                .background(
                    GeometryReader { contentProxy in
                        let rawOffset = -contentProxy.frame(in: .named(coordinateSpaceName)).minY
                        Color.clear.preference(
                            key: SmoothScrollContentMetricsKey.self,
                            value: SmoothScrollContentMetrics(
                                offsetY: max(0, rawOffset),
                                contentHeight: max(1, contentProxy.size.height)
                            )
                        )
                    }
                )
        }
        .coordinateSpace(name: coordinateSpaceName)
        .background(
            GeometryReader { viewportProxy in
                Color.clear.preference(
                    key: SmoothScrollViewportHeightKey.self,
                    value: max(1, viewportProxy.size.height)
                )
            }
        )
        .onPreferenceChange(SmoothScrollContentMetricsKey.self) { newMetrics in
            metrics = newMetrics
            showTransientIndicator()
        }
        .onPreferenceChange(SmoothScrollViewportHeightKey.self) { height in
            viewportHeight = height
        }
        .overlay(alignment: .trailing) {
            scrollIndicator
        }
        .onDisappear {
            indicatorHideTask?.cancel()
            indicatorHideTask = nil
        }
    }

    private var scrollIndicator: some View {
        GeometryReader { proxy in
            let indicatorHeight: CGFloat = 38
            let verticalInset: CGFloat = 12
            let maxScrollableOffset = max(1, metrics.contentHeight - viewportHeight)
            let progress = min(max(metrics.offsetY / maxScrollableOffset, 0), 1)
            let availableTravel = max(0, proxy.size.height - indicatorHeight - verticalInset * 2)
            let y = verticalInset + indicatorHeight / 2 + availableTravel * progress

            Capsule(style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.30 : 0.22))
                .frame(width: 3, height: indicatorHeight)
                .position(x: proxy.size.width - 8, y: y)
                .opacity(showIndicator && metrics.contentHeight > viewportHeight + 8 ? 1 : 0)
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.16), value: showIndicator)
        .animation(.easeOut(duration: 0.08), value: metrics.offsetY)
    }

    private func showTransientIndicator() {
        guard metrics.contentHeight > viewportHeight + 8 else { return }

        indicatorHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.12)) {
            showIndicator = true
        }

        let task = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.22)) {
                showIndicator = false
            }
        }
        indicatorHideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: task)
    }
}

private struct SmoothScrollContentMetrics: Equatable {
    var offsetY: CGFloat = 0
    var contentHeight: CGFloat = 1
}

private struct SmoothScrollContentMetricsKey: PreferenceKey {
    static var defaultValue = SmoothScrollContentMetrics()

    static func reduce(value: inout SmoothScrollContentMetrics, nextValue: () -> SmoothScrollContentMetrics) {
        value = nextValue()
    }
}

private struct SmoothScrollViewportHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 1

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
