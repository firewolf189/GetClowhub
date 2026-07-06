//
//  BudgetManagement.swift
//  Budget management & monitoring extracted from DashboardViewModel.
//  P1 refactor: file split only, no behavior change.
//

import Foundation
import os.log

extension DashboardViewModel {

    // MARK: - Budget Management

    /// Sync the budgetRules @Published mirror from the nested budgetService.
    /// Call this after any mutation to budgetService.config.rules so SwiftUI re-renders.
    func syncBudgetRules() {
        budgetRules = budgetService.config.rules
    }

    /// Load budget status by combining session data with budget rules and model costs.
    func loadBudgets() async {
        os_log("[DashboardViewModel] Auto-refreshing budgets at %@", log: OSLog.default, type: .info, Date().description)
        isLoadingBudgets = true

        // Try to load session data (may remain nil if service is not running)
        await loadSessionsSummary()
        os_log("[DashboardViewModel] Loaded sessions: %d tokens", log: OSLog.default, type: .info, sessionsSummary?.totalTokens ?? 0)

        budgetService.loadConfig()
        syncBudgetRules()
        budgetSnapshots = budgetService.evaluate(
            sessions: sessionsSummary,
            modelCosts: settings.settings.configuredModels
        )
        os_log("[DashboardViewModel] Updated %d budget snapshots", log: OSLog.default, type: .info, budgetSnapshots.count)

        isLoadingBudgets = false

        #if REQUIRE_LOGIN
        // Also load official service billing in parallel
        await loadKeysBilling()
        #endif
    }

    #if REQUIRE_LOGIN
    /// Load official service key billing from GetClawHub backend.
    func loadKeysBilling() async {
        await membershipManager?.fetchKeysBilling()
    }
    #endif

    // MARK: - Budget Monitoring

    func startBudgetMonitor() {
        print("[DashboardViewModel] Starting budget monitor with 30-second interval")
        budgetMonitorTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.loadBudgets()
            }
        }
        // Also load immediately
        Task {
            await loadBudgets()
        }
    }

    func stopBudgetMonitor() {
        print("[DashboardViewModel] Stopping budget monitor")
        budgetMonitorTimer?.invalidate()
        budgetMonitorTimer = nil
    }

}
