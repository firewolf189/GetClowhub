import SwiftUI

enum SettingsShortcutRowRole {
    case normal
    case destructive
}

struct SettingsShortcutSummaryRow: View {
    let title: String
    let systemImage: String
    let trailingSummary: String
    var meter: SettingsShortcutInlineMeter?
    var showsTrailingChevron = true
    var role: SettingsShortcutRowRole = .normal
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) {
                rowContent
            }
            .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        SettingsShortcutRowContent(
            title: title,
            systemImage: systemImage,
            trailingSummary: trailingSummary,
            meter: meter,
            showsTrailingChevron: showsTrailingChevron,
            role: role
        )
    }
}

struct SettingsShortcutActionRow: View {
    let title: String
    let systemImage: String
    var showsTrailingChevron = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsShortcutRowContent(
                title: title,
                systemImage: systemImage,
                showsTrailingChevron: showsTrailingChevron
            )
        }
        .buttonStyle(.plain)
    }
}

struct SettingsShortcutRowContent: View {
    let title: String
    let systemImage: String
    var trailingSummary: String?
    var meter: SettingsShortcutInlineMeter?
    var showsTrailingChevron = true
    var role: SettingsShortcutRowRole = .normal

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 15)
                .foregroundStyle(rowForegroundStyle)

            Text(title)
                .foregroundStyle(rowForegroundStyle)

            Spacer(minLength: 10)

            if let meter {
                SettingsShortcutInlineMeterView(meter: meter)
            }

            if let trailingSummary {
                Text(trailingSummary)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(SettingsShortcutColors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .monospacedDigit()
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SettingsShortcutColors.tertiaryText)
                .opacity(showsTrailingChevron ? 1 : 0)
                .frame(width: 10)
        }
        .font(.system(size: 12.5, weight: .medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var rowForegroundStyle: SwiftUI.Color {
        switch role {
        case .normal: return SettingsShortcutColors.primaryText
        case .destructive: return .red
        }
    }
}

struct SettingsShortcutInlineMeterView: View {
    let meter: SettingsShortcutInlineMeter

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(SettingsShortcutColors.tertiaryText.opacity(0.18))
                Capsule()
                    .fill(Color.accentColor.opacity(0.72))
                    .frame(width: max(4, proxy.size.width * min(max(meter.value, 0), 1)))
            }
        }
        .frame(width: 44, height: 5)
        .clipShape(Capsule())
    }
}

struct SettingsShortcutInlineMeter {
    let value: Double
}
