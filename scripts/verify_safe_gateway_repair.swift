import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appSources = [
    "OpenClawInstaller/Core/Command/SafeGatewayRepair.swift",
]
let testSource = "Tests/SafeGatewayRepairTests.swift"

let fm = FileManager.default

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

func read(_ path: String) -> String {
    let url = repoRoot.appendingPathComponent(path)
    guard let value = try? String(contentsOf: url, encoding: .utf8) else {
        fail("could not read \(path)")
    }
    return value
}

func readStringJSON(_ path: String) -> [String: String] {
    guard let object = try? JSONSerialization.jsonObject(with: Data(read(path).utf8))
        as? [String: String] else {
        fail("could not parse \(path)")
    }
    return object
}

// Keep the non-technical UI boundary pinned: safe first, destructive only
// after a second confirmation.
let statusView = read("OpenClawInstaller/Features/Status/Views/StatusTabView.swift")
let viewModel = read("OpenClawInstaller/Features/Dashboard/DashboardViewModel.swift")
guard viewModel.contains("func ensureMainAgentContinuity"),
      viewModel.contains("migrateStrandedMemoryIfNeeded") else {
    fail("launch must pin main's workspace and copy stranded MEMORY.md from workspace-<id>")
}
let installationViewModel = read(
    "OpenClawInstaller/Features/Installation/InstallationViewModel.swift"
)
guard statusView.contains("showSafeRepairConfirm"),
      statusView.contains("showEmergencyRepairConfirm"),
      statusView.contains("await viewModel.safeRepairService()"),
      statusView.contains("await viewModel.forceRepairService()"),
      viewModel.contains("func safeRepairService() async -> Bool") else {
    fail("repair UI must keep safe repair and emergency force repair as two distinct confirmations")
}
guard installationViewModel.contains(#"session["dmScope"] = "per-channel-peer""#),
      installationViewModel.contains(#"reload["deferralTimeoutMs"] = 0"#),
      installationViewModel.contains(#"reset["mode"] = "idle""#),
      installationViewModel.contains(#"reset["idleMinutes"] = 5_256_000"#) else {
    fail("new installations must start with isolated DMs, indefinite safe-restart deferral, and no inactivity session wipe")
}
let appServices = read("OpenClawInstaller/App/OpenClawInstallerApp.swift")
let forceRepair = read("OpenClawInstaller/Core/Command/OpenClawServiceForceRepair.swift")
let safeRepair = read("OpenClawInstaller/Core/Command/SafeGatewayRepair.swift")
let chatHelpers = read("OpenClawInstaller/Features/Chat/ChatHelpers.swift")
let persistence = read("OpenClawInstaller/Features/Sessions/SessionPersistence.swift")
let chatSession = read("OpenClawInstaller/Features/Sessions/Models/ChatSession.swift")
guard appServices.contains("applySessionIsolationIfNeeded()"),
      forceRepair.contains("func applySessionIsolationIfNeeded()"),
      safeRepair.contains("enum SessionIsolationBootstrap"),
      safeRepair.contains("dingtalk-connector"),
      safeRepair.contains("globalResetIsIdle"),
      safeRepair.contains("sessionIdleMinutes"),
      chatHelpers.contains("GatewayTranscriptRehydrate.ensurePriorTurnsPresent"),
      chatHelpers.contains("recordGatewaySessionId"),
      persistence.contains("func reconcileGatewayTranscriptIfNeeded"),
      viewModel.contains("reconcileGatewayTranscriptIfNeeded(forAgent:"),
      chatSession.contains("var gatewaySessionId: String?") else {
    fail("launch path must silently write session isolation, no inactivity session wipe, rehydrate before send and on session open, persist the gateway sessionId, and treat both DingTalk ids as one channel")
}

// Every locale must have the repair keys; English is the fallback for locales
// that do not yet have a dedicated translation.
let englishCommon = readStringJSON("OpenClawInstaller/Resources/I18n/en/common.json")
let repairKeys = Set(englishCommon.keys.filter { key in
    key == "repair.action.safeRepair"
        || key.hasPrefix("repair.emergency.")
        || key.hasPrefix("repair.safe.")
        || [
            "repair.step.deferralFailed",
            "repair.step.deferralRepaired",
            "repair.step.dmScopeFailed",
            "repair.step.dmScopeRepaired",
        ].contains(key)
})
let i18nRoot = repoRoot.appendingPathComponent("OpenClawInstaller/Resources/I18n")
let localeDirs = (try? fm.contentsOfDirectory(
    at: i18nRoot,
    includingPropertiesForKeys: [.isDirectoryKey],
    options: [.skipsHiddenFiles]
)) ?? []
for localeDir in localeDirs {
    let commonPath = localeDir.appendingPathComponent("common.json")
    guard fm.fileExists(atPath: commonPath.path) else { continue }
    let relative = commonPath.path.replacingOccurrences(
        of: repoRoot.path + "/",
        with: ""
    )
    let localized = readStringJSON(relative)
    let missing = repairKeys.subtracting(localized.keys)
    guard missing.isEmpty else {
        fail("\(relative) is missing repair keys: \(missing.sorted().joined(separator: ", "))")
    }
}

let generator = read("scripts/generate_unified_i18n_resources.py")
for key in repairKeys {
    guard generator.contains("\"\(key)\"") else {
        fail("i18n generator would drop repair key \(key)")
    }
}

let workDir = fm.temporaryDirectory
    .appendingPathComponent("verify_safe_gateway_repair-\(UUID().uuidString)")
try! fm.createDirectory(at: workDir, withIntermediateDirectories: true)
let binaryURL = workDir.appendingPathComponent("verify")

@discardableResult
func run(_ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    do { try process.run() } catch {
        fputs("FAIL: could not launch \(arguments[0]): \(error)\n", stderr)
        exit(1)
    }
    process.waitUntilExit()
    return process.terminationStatus
}

var compileArgs = ["swiftc"]
compileArgs += appSources.map { repoRoot.appendingPathComponent($0).path }
compileArgs += [repoRoot.appendingPathComponent(testSource).path, "-o", binaryURL.path]
if run(compileArgs) != 0 {
    fputs("FAIL: SafeGatewayRepair + its tests no longer compile\n", stderr)
    try? fm.removeItem(at: workDir)
    exit(1)
}
let status = run([binaryURL.path])
try? fm.removeItem(at: workDir)
exit(status)
