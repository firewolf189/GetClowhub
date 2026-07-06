import SwiftUI

struct BillingShortcutSummary: View {
    let snapshot: SettingsShortcutBillingSnapshot

    private var billingSummary: String {
        guard let spend = snapshot.spend else {
            return snapshot.hasLoadedRemoteValue
                ? I18n.t("No billing data yet")
                : "--"
        }

        guard let maxBudget = snapshot.maxBudget else {
            return formatCurrency(spend)
        }
        return "\(formatCurrency(spend)) / \(formatCurrency(maxBudget))"
    }

    private var billingMeter: SettingsShortcutInlineMeter? {
        guard let meterValue = snapshot.meterValue else { return nil }
        return SettingsShortcutInlineMeter(value: meterValue)
    }

    var body: some View {
        SettingsShortcutSummaryRow(
            title: I18n.t("Billing"),
            systemImage: "creditcard",
            trailingSummary: billingSummary,
            meter: billingMeter,
            showsTrailingChevron: false
        )
    }

    private func formatCurrency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}
