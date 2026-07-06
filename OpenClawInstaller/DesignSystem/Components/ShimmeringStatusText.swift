import SwiftUI

struct ShimmeringStatusText: View {
    let text: String
    var font: Font = .system(size: 13, weight: .medium)
    var foregroundStyle: Color = .secondary
    var highlightOpacity: Double = 0.70
    var duration: Double = 1.8

    @State private var highlightIsTrailing = false

    private var label: some View {
        Text(text)
            .font(font)
    }

    var body: some View {
        label
            .foregroundColor(foregroundStyle)
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .primary.opacity(0.10), location: 0.35),
                            .init(color: .primary.opacity(highlightOpacity), location: 0.50),
                            .init(color: .primary.opacity(0.10), location: 0.65),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: max(proxy.size.width * 0.72, 36), height: proxy.size.height)
                    .offset(x: highlightIsTrailing ? proxy.size.width : -max(proxy.size.width * 0.72, 36))
                }
                .mask(label)
                .allowsHitTesting(false)
            }
            .onAppear {
                highlightIsTrailing = false
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    highlightIsTrailing = true
                }
            }
    }
}
