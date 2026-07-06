import Foundation

struct CronJobInfo: Identifiable {
    let id = UUID()
    let cronId: String
    let name: String
    let schedule: String
    let timezone: String
    let agentId: String
    let sessionTarget: String
    let message: String
    let enabled: Bool
    let nextRun: String
    let lastRun: String
    let status: String
    let model: String
}
