import Foundation

struct SettingsShortcutState: Equatable {
    let budgetSnapshots: [BudgetSnapshot]
    let billingSnapshot: SettingsShortcutBillingSnapshot
}

struct SettingsShortcutBillingSnapshot: Equatable, Codable {
    let spend: Double?
    let maxBudget: Double?
    let hasLoadedRemoteValue: Bool
    let updatedAt: Date?

    static let unavailable = SettingsShortcutBillingSnapshot(
        spend: nil,
        maxBudget: nil,
        hasLoadedRemoteValue: false,
        updatedAt: nil
    )

    var hasDisplayValue: Bool {
        spend != nil
    }

    var meterValue: Double? {
        guard let spend, let maxBudget, maxBudget > 0 else { return nil }
        return min(max(spend / maxBudget, 0), 1)
    }
}

#if REQUIRE_LOGIN
extension SettingsShortcutBillingSnapshot {
    @MainActor
    static func current(
        from membershipManager: MembershipManager?,
        cacheIdentity: String?
    ) -> SettingsShortcutBillingSnapshot {
        guard let membershipManager else {
            return SettingsShortcutBillingSnapshotCache.load(identity: cacheIdentity) ?? .unavailable
        }

        if membershipManager.hasLoadedKeysBilling || !membershipManager.keysBilling.isEmpty {
            return SettingsShortcutBillingSnapshot.remote(from: membershipManager.keysBilling)
        }

        return SettingsShortcutBillingSnapshotCache.load(identity: cacheIdentity) ?? .unavailable
    }

    @MainActor
    static func persistCurrentRemoteValue(
        from membershipManager: MembershipManager?,
        cacheIdentity: String?
    ) {
        guard let membershipManager,
              membershipManager.hasLoadedKeysBilling || !membershipManager.keysBilling.isEmpty else {
            return
        }
        let snapshot = SettingsShortcutBillingSnapshot.remote(from: membershipManager.keysBilling)
        SettingsShortcutBillingSnapshotCache.saveOrClear(snapshot, identity: cacheIdentity)
    }

    private static func remote(from keysBilling: [KeyBillingInfo]) -> SettingsShortcutBillingSnapshot {
        guard !keysBilling.isEmpty else {
            return SettingsShortcutBillingSnapshot(
                spend: nil,
                maxBudget: nil,
                hasLoadedRemoteValue: true,
                updatedAt: Date()
            )
        }

        let spend = keysBilling.reduce(0) { $0 + $1.spend }
        let budgets = keysBilling.compactMap(\.maxBudget)
        return SettingsShortcutBillingSnapshot(
            spend: spend,
            maxBudget: budgets.isEmpty ? nil : budgets.reduce(0, +),
            hasLoadedRemoteValue: true,
            updatedAt: Date()
        )
    }
}
#endif

private enum SettingsShortcutBillingSnapshotCache {
    private static let keyPrefix = "settingsShortcut.billingSnapshot.v1."

    static func load(identity: String?) -> SettingsShortcutBillingSnapshot? {
        guard let key = cacheKey(identity: identity),
              let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(SettingsShortcutBillingSnapshot.self, from: data)
    }

    static func saveOrClear(_ snapshot: SettingsShortcutBillingSnapshot, identity: String?) {
        guard let key = cacheKey(identity: identity) else { return }

        guard snapshot.hasDisplayValue else {
            if snapshot.hasLoadedRemoteValue {
                UserDefaults.standard.removeObject(forKey: key)
            }
            return
        }

        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func cacheKey(identity: String?) -> String? {
        guard let identity = identity?.trimmingCharacters(in: .whitespacesAndNewlines),
              !identity.isEmpty else {
            return nil
        }

        let allowedCharacters = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_@."))
        let encodedIdentity = identity.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? identity
        return keyPrefix + encodedIdentity
    }
}
