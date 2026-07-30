import Foundation

/// macOS counterpart of the Windows client's emergency repair (`repair_gateway`).
///
/// Healthy gateways use `safeRepairGateway()` below, which delegates active-work
/// protection to OpenClaw's official `gateway restart --safe` implementation.
/// Force repair is the separately confirmed bottom-line recovery for when the
/// CLI or gateway is NOT healthy:
///   1. config triage  — strip a UTF-8 BOM from openclaw.json (Rust/Swift JSON
///      readers choke on it; observed on Windows as `token_missing` refusals),
///      and back up an unparseable config instead of letting the gateway spin
///      on it.
///   2. log hygiene    — truncate runaway gateway logs (a 16 GB gateway.err.log
///      was observed in the field filling the disk).
///   3. process purge  — kill whatever holds the gateway port plus any orphan
///      gateway processes `gateway stop` can no longer reach.
///   4. runtime triage — report whether the installed Node is one the core will
///      actually run on. The core's launcher exits(1) on an unsupported Node
///      before binding a port, so this is a silent cause of a gateway that
///      "starts" and vanishes; `start()` below repairs it.
///   5. cold start     — bring the gateway back with the normal start path.
struct ForceRepairReport {
    var steps: [String] = []
    var succeeded = true

    mutating func note(_ line: String) { steps.append(line) }
    mutating func fail(_ line: String) {
        steps.append(line)
        succeeded = false
    }
}

extension OpenClawService {
    private static let oversizedLogThreshold: UInt64 = 512 * 1024 * 1024 // 512 MB

    /// Repair the two safety settings and ask OpenClaw itself to restart only
    /// after all channel work drains. This path never kills a process.
    func safeRepairGateway() async -> SafeGatewayRepairOutcome {
        addLog("Safe repair: checking core capability and required settings")
        let previousPID = await gatewayListenerPID()
        let coordinator = SafeGatewayRepairCoordinator(
            runCommand: { [weak self] command, timeout in
                guard let self else { return nil }
                return await self.runCommand(command, timeout: timeout)
            },
            waitForRecovery: { [weak self] in
                guard let self else { return false }
                return await self.waitForSafeRestartRecovery(previousPID: previousPID)
            }
        )
        let outcome = await coordinator.repair()
        addLog("Safe repair: finished with \(String(describing: outcome))")
        return outcome
    }

    func forceRepairGateway() async -> ForceRepairReport {
        var report = ForceRepairReport()
        addLog("Emergency force repair: starting")

        repairConfigFile(report: &report)
        await repairRequiredGatewaySettings(report: &report)
        truncateOversizedLogs(report: &report)
        await forceKillGatewayProcesses(report: &report)
        await reportNodeRuntimeSupport(report: &report)

        do {
            // start() reinstalls the bundled Node first when the installed one is
            // outside the core's supported ranges, so the runtime is repaired here.
            try await start()
            report.note(I18n.t("repair.step.restarted"))
        } catch {
            report.fail(I18n.format("repair.step.restartFailed", error.localizedDescription))
        }

        addLog("Emergency force repair: finished (success=\(report.succeeded))")
        return report
    }

    // MARK: - Safe repair support

    private func gatewayListenerPID() async -> String? {
        let pid = await runShellQuietly(
            "lsof -ti tcp:\(port) -sTCP:LISTEN 2>/dev/null | head -n 1",
            timeout: 5
        )?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        return pid?.isEmpty == false ? pid : nil
    }

    private func waitForSafeRestartRecovery(previousPID: String?) async -> Bool {
        // Let the RPC response flush before looking for the replacement process.
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        for _ in 0..<45 {
            let currentPID = await gatewayListenerPID()
            if let currentPID, previousPID == nil || currentPID != previousPID {
                await checkStatus()
                return status == .running
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }

    private func repairRequiredGatewaySettings(report: inout ForceRepairReport) async {
        let dmScopeOK = await ensureEmergencyConfigValue(
            getCommand: SafeGatewayRepairCommands.getDMScope,
            setCommand: SafeGatewayRepairCommands.setDMScope,
            predicate: SafeGatewayConfigVerification.isExpectedDMScope
        )
        if dmScopeOK {
            report.note(I18n.t("repair.step.dmScopeRepaired"))
        } else {
            report.fail(I18n.t("repair.step.dmScopeFailed"))
        }

        let deferralOK = await ensureEmergencyConfigValue(
            getCommand: SafeGatewayRepairCommands.getDeferralTimeout,
            setCommand: SafeGatewayRepairCommands.setDeferralTimeout,
            predicate: SafeGatewayConfigVerification.isExpectedDeferralTimeout
        )
        if deferralOK {
            report.note(I18n.t("repair.step.deferralRepaired"))
        } else {
            report.fail(I18n.t("repair.step.deferralFailed"))
        }
    }

    private func ensureEmergencyConfigValue(
        getCommand: String,
        setCommand: String,
        predicate: (String) -> Bool
    ) async -> Bool {
        if let current = await runSafeRepairShellCommand(getCommand),
           current.succeeded,
           predicate(current.output) {
            return true
        }
        guard let write = await runSafeRepairShellCommand(setCommand), write.succeeded,
              let verified = await runSafeRepairShellCommand(getCommand), verified.succeeded else {
            return false
        }
        return predicate(verified.output)
    }

    private func runSafeRepairShellCommand(_ command: String) async -> SafeGatewayShellResult? {
        let raw = await runCommand(
            SafeGatewayRepairCommands.reportingExitStatus(command),
            timeout: 30
        )
        return SafeGatewayShellResult.decode(raw)
    }

    // MARK: - Step 4: runtime triage

    /// Note whether the installed Node is one the bundled core will run on.
    ///
    /// Purely diagnostic — `start()` does the repair. It is reported separately
    /// because an unsupported Node is invisible otherwise: the core's launcher
    /// exits before writing any log the gateway owns, and `launchctl` reports the
    /// respawning job as loaded.
    private func reportNodeRuntimeSupport(report: inout ForceRepairReport) async {
        guard let manifest = try? OpenClawCoreManifest.loadBundled(),
              let requirement = manifest.nodeRuntimeRequirement else {
            return
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let nodePath = "\(home)/.openclaw/node/bin/node"
        var installed: String?
        if FileManager.default.isExecutableFile(atPath: nodePath) {
            installed = await runShellQuietly("'\(nodePath)' --version", timeout: 10)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if requirement.isSatisfied(by: installed) {
            report.note(I18n.format("repair.step.nodeOK", installed ?? "unknown"))
        } else {
            report.note(I18n.format(
                "repair.step.nodeUnsupported",
                installed ?? "missing",
                requirement.displayText
            ))
        }
    }

    // MARK: - Step 1: config triage

    private func repairConfigFile(report: inout ForceRepairReport) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(home)/.openclaw/openclaw.json"
        guard var data = FileManager.default.contents(atPath: configPath) else {
            report.note(I18n.t("repair.step.configMissing"))
            return
        }

        // UTF-8 BOM: the Node gateway tolerates it, but native JSON readers
        // (this app, and historically the Windows client) do not.
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        if data.count >= 3, data.prefix(3).elementsEqual(bom) {
            data.removeFirst(3)
            if (try? data.write(to: URL(fileURLWithPath: configPath), options: .atomic)) != nil {
                report.note(I18n.t("repair.step.configBOMStripped"))
            } else {
                report.fail(I18n.t("repair.step.configWriteFailed"))
                return
            }
        }

        if (try? JSONSerialization.jsonObject(with: data)) == nil {
            // Never destroy user data: park the broken file for inspection and
            // let the gateway regenerate a fresh default on next start.
            let stamp = Int(Date().timeIntervalSince1970)
            let backupPath = "\(configPath).broken-\(stamp)"
            do {
                try FileManager.default.moveItem(atPath: configPath, toPath: backupPath)
                report.note(I18n.format("repair.step.configQuarantined", (backupPath as NSString).lastPathComponent))
            } catch {
                report.fail(I18n.format("repair.step.configUnreadable", error.localizedDescription))
            }
        } else {
            report.note(I18n.t("repair.step.configOK"))
        }
    }

    // MARK: - Step 2: log hygiene

    private func truncateOversizedLogs(report: inout ForceRepairReport) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.openclaw/logs/gateway.log",
            "\(home)/.openclaw/logs/gateway.err.log",
            "\(home)/Library/Logs/openclaw/gateway.log",
        ]
        var reclaimed: UInt64 = 0
        for path in candidates {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = attrs[.size] as? UInt64,
                  size > Self.oversizedLogThreshold else { continue }
            if let handle = FileHandle(forWritingAtPath: path) {
                try? handle.truncate(atOffset: 0)
                try? handle.close()
                reclaimed += size
            }
        }
        if reclaimed > 0 {
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(reclaimed), countStyle: .file)
            report.note(I18n.format("repair.step.logsTruncated", formatted))
        }
    }

    // MARK: - Step 3: process purge

    private func forceKillGatewayProcesses(report: inout ForceRepairReport) async {
        // Two nets: whatever LISTENs on the gateway port (covers a zombie that
        // lost its cmdline pattern), then any process whose command line still
        // says it is an openclaw gateway (covers a zombie that lost the port).
        let killByPort = "lsof -ti tcp:\(port) -sTCP:LISTEN 2>/dev/null | xargs kill -9 2>/dev/null"
        let killByPattern = "pkill -9 -f 'openclaw.*gateway' 2>/dev/null"
        _ = await runShellQuietly("\(killByPort); \(killByPattern); true")
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        let stillListening = await runShellQuietly("lsof -ti tcp:\(port) -sTCP:LISTEN 2>/dev/null")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if stillListening.isEmpty {
            report.note(I18n.t("repair.step.processesKilled"))
        } else {
            report.fail(I18n.format("repair.step.portStillBusy", String(port)))
        }
    }
}
