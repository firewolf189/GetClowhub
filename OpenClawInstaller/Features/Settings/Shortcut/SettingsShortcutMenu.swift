import SwiftUI

struct SettingsShortcutMenu: View {
    let shortcutState: SettingsShortcutState
    let loadShortcutData: () async -> Void
    let onSizeChange: (CGSize) -> Void
    let onDismiss: () -> Void
    let onOpenSettingsSection: (SettingsPageSection) -> Void

    #if REQUIRE_LOGIN
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var membershipManager: MembershipManager
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            accountHeader

            #if REQUIRE_LOGIN
            BillingShortcutSummary(
                snapshot: shortcutState.billingSnapshot
            )
            #endif

            BudgetShortcutSummary(
                snapshots: shortcutState.budgetSnapshots
            )

            Divider()

            SettingsShortcutActionRow(
                title: I18n.t("All settings"),
                systemImage: "gearshape",
                showsTrailingChevron: false
            ) {
                onOpenSettingsSection(.profile)
            }

            #if REQUIRE_LOGIN
            Button {
                if authManager.isLoggedIn {
                    authManager.logout()
                } else {
                    authManager.login()
                }
                onDismiss()
            } label: {
                SettingsShortcutRowContent(
                    title: authManager.isLoggedIn ? I18n.t("Log out") : I18n.t("Log in"),
                    systemImage: authManager.isLoggedIn ? "rectangle.portrait.and.arrow.right" : "person.crop.circle.badge.plus",
                    showsTrailingChevron: false,
                    role: authManager.isLoggedIn ? .destructive : .normal
                )
            }
            .buttonStyle(.plain)
            #endif
        }
        .padding(12)
        .frame(width: SettingsShortcutPanelMetrics.width, alignment: .leading)
        .background(SettingsShortcutLiquidDropBackground(cornerRadius: SettingsShortcutPanelMetrics.cornerRadius))
        .clipShape(SettingsShortcutPanelMetrics.panelShape)
        .compositingGroup()
        .foregroundStyle(SettingsShortcutColors.primaryText)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SettingsShortcutSizeKey.self, value: proxy.size)
            }
            .allowsHitTesting(false)
        )
        .onPreferenceChange(SettingsShortcutSizeKey.self) { size in
            onSizeChange(size)
        }
        .task {
            await loadShortcutData()
        }
    }

    @ViewBuilder
    private var accountHeader: some View {
        #if REQUIRE_LOGIN
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(SettingsShortcutColors.secondaryText)

            VStack(alignment: .leading, spacing: 1) {
                Text(accountDisplayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SettingsShortcutColors.primaryText)
                    .lineLimit(1)
                Text(authManager.isLoggedIn ? I18n.t("Signed in") : I18n.t("Not signed in"))
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsShortcutColors.secondaryText)
            }

            Spacer()

            if let membership = membershipManager.membership {
                Text(membership.level.displayName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(membershipBadgeColor(membership.level))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(membershipBadgeColor(membership.level).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        #else
        HStack(spacing: 9) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(SettingsShortcutColors.secondaryText)
            Text(I18n.t("Local user"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SettingsShortcutColors.primaryText)
            Spacer()
        }
        #endif
    }
}

private extension SettingsShortcutMenu {
    #if REQUIRE_LOGIN
    var accountDisplayName: String {
        if let email = authManager.userEmail, !email.isEmpty {
            return email
        }
        if case .loggedIn(let nickname) = authManager.state, !nickname.isEmpty {
            return nickname
        }
        if let userId = authManager.userId, !userId.isEmpty {
            return userId
        }
        return I18n.t("User")
    }

    func membershipBadgeColor(_ level: MembershipLevel) -> SwiftUI.Color {
        switch level {
        case .free: return .gray
        case .pro: return .blue
        case .max: return .purple
        }
    }
    #endif
}

private struct BudgetShortcutSummary: View {
    let snapshots: [BudgetSnapshot]

    private var globalSnapshot: BudgetSnapshot? {
        snapshots.first(where: { $0.scope == .global })
    }

    private var budgetSummary: String {
        guard let snapshot = globalSnapshot else {
            return I18n.t("No local budget rule")
        }
        guard snapshot.tokenLimit > 0 else {
            return formatTokenCount(snapshot.tokensUsed)
        }
        return "\(formatTokenCount(snapshot.tokensUsed)) / \(formatTokenCount(snapshot.tokenLimit))"
    }

    private var budgetMeter: SettingsShortcutInlineMeter? {
        guard let snapshot = globalSnapshot, snapshot.tokenLimit > 0 else { return nil }
        return SettingsShortcutInlineMeter(value: min(snapshot.tokenPercent, 1))
    }

    var body: some View {
        SettingsShortcutSummaryRow(
            title: I18n.t("Budget"),
            systemImage: "dollarsign.gauge.chart.lefthalf.righthalf",
            trailingSummary: budgetSummary,
            meter: budgetMeter,
            showsTrailingChevron: false
        )
    }

    private func formatTokenCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

struct SettingsShortcutSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
