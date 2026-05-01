import Foundation

// MARK: - Budget Scope

enum BudgetScope: String, Codable, CaseIterable {
    case global   // 全局预算
    case agent    // 按 agent 独立预算
}

// MARK: - Budget Status

enum BudgetStatus: String, Codable {
    case ok       // 正常
    case warn     // 接近阈值
    case over     // 超标

    /// Returns the raw English key for this status.
    /// Use `Text(LocalizedStringKey(status.label))` in SwiftUI views for proper i18n.
    var label: String {
        switch self {
        case .ok: return "Status OK"
        case .warn: return "Warning"
        case .over: return "Over Budget"
        }
    }
}

// MARK: - Budget Rule (单条预算规则)

struct BudgetRule: Codable, Identifiable, Equatable {
    var id: String                  // "global" 或 agentId
    var scope: BudgetScope
    var label: String               // 显示名称
    var tokenLimit: Int             // token 上限（0 = 不限）
    var costLimit: Double           // 费用上限 USD（0 = 不限）
    var warnRatio: Double           // 警告比例，默认 0.8
    var enabled: Bool

    static let defaultWarnRatio: Double = 0.8

    static func globalDefault() -> BudgetRule {
        BudgetRule(
            id: "global",
            scope: .global,
            label: "Global",
            tokenLimit: 10_000_000,
            costLimit: 0,
            warnRatio: defaultWarnRatio,
            enabled: true
        )
    }
}

// MARK: - Budget Snapshot (运行时状态快照)

struct BudgetSnapshot: Identifiable {
    let id: String
    let label: String
    let scope: BudgetScope

    // 实际用量
    let tokensUsed: Int
    let inputTokens: Int
    let outputTokens: Int
    let estimatedCost: Double

    // 预算规则
    let tokenLimit: Int
    let costLimit: Double
    let warnRatio: Double

    // 计算状态
    let tokenStatus: BudgetStatus
    let costStatus: BudgetStatus
    let overallStatus: BudgetStatus

    // 百分比 (0.0 ~ 1.0+)
    let tokenPercent: Double
    let costPercent: Double
}

// MARK: - Budget Config (持久化配置)

struct BudgetConfig: Codable {
    var rules: [BudgetRule]
    var notifyOnWarn: Bool
    var notifyOnOver: Bool

    static func defaultConfig() -> BudgetConfig {
        BudgetConfig(
            rules: [BudgetRule.globalDefault()],
            notifyOnWarn: true,
            notifyOnOver: true
        )
    }
}
