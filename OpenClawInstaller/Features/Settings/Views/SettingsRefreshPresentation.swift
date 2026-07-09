import SwiftUI

struct SettingsInlineRefreshStatus: View {
    let isRefreshing: Bool
    var text: String = I18n.t("settings.refreshing", fallback: "Refreshing...")

    var body: some View {
        if isRefreshing {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                Text(text)
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
    }
}

struct SettingsStaticLoadingPlaceholder: View {
    let title: String
    let systemImage: String
    var detail: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .medium))
                .foregroundColor(.secondary)
            Text(title)
                .font(.callout)
                .foregroundColor(.secondary)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}
