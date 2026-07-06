import SwiftUI

enum SettingsShortcutPanelMetrics {
    static let width: CGFloat = 280
    static let minHeight: CGFloat = 96
    static let maxHeight: CGFloat = 240
    static let cornerRadius: CGFloat = 18
    static let horizontalWindowInset: CGFloat = 12
    static let verticalWindowInset: CGFloat = 10
    static let verticalSourceGap: CGFloat = 8

    static var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

enum SettingsShortcutColors {
    static let primaryText = SwiftUI.Color(red: 0.10, green: 0.12, blue: 0.16)
    static let secondaryText = SwiftUI.Color(red: 0.36, green: 0.40, blue: 0.48)
    static let tertiaryText = SwiftUI.Color(red: 0.55, green: 0.59, blue: 0.66)
    static let glassBase = SwiftUI.Color.white.opacity(0.74)
    static let glassHighlight = SwiftUI.Color.white.opacity(0.48)
    static let glassEdge = SwiftUI.Color.white.opacity(0.66)
    static let glassShadow = SwiftUI.Color(red: 0.18, green: 0.22, blue: 0.30).opacity(0.18)
}

struct SettingsShortcutLiquidDropBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(SettingsShortcutColors.glassBase)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                SettingsShortcutColors.glassHighlight,
                                Color.white.opacity(0.24),
                                Color.white.opacity(0.08),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.60),
                                Color.white.opacity(0.20),
                                Color.clear
                            ],
                            center: UnitPoint(x: 0.18, y: 0.12),
                            startRadius: 4,
                            endRadius: 190
                        )
                    )
                    .blendMode(.plusLighter)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.30),
                                Color.white.opacity(0.10),
                                Color.clear
                            ],
                            center: UnitPoint(x: 0.82, y: 0.18),
                            startRadius: 0,
                            endRadius: 150
                        )
                    )
                    .blendMode(.screen)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                SettingsShortcutColors.glassEdge,
                                Color.white.opacity(0.28),
                                Color(red: 0.30, green: 0.34, blue: 0.42).opacity(0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: SettingsShortcutColors.glassShadow, radius: 22, x: 0, y: 12)
            .shadow(color: Color.white.opacity(0.34), radius: 1, x: 0, y: 1)
    }
}
