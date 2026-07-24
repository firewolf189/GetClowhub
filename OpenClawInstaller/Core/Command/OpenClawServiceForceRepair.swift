import Foundation

/// macOS counterpart of the Windows client's 强行修复网关 (`repair_gateway`).
///
/// The regular restart path shells out to `openclaw gateway restart`, which
/// only works while the CLI and the gateway are healthy. Force repair is the
/// bottom-line recovery for when they are NOT:
///   1. config triage  — strip a UTF-8 BOM from openclaw.json (Rust/Swift JSON
///      readers choke on it; observed on Windows as `token_missing` refusals),
///      and back up an unparseable config instead of letting the gateway spin
///      on it.
///   2. log hygiene    — truncate runaway gateway logs (a 16 GB gateway.err.log
///      was observed in the field filling the disk).
///   3. process purge  — kill whatever holds the gateway port plus any orphan
///      gateway processes `gateway stop` can no longer reach.
///   4. cold start     — bring the gateway back with the normal start path.
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

    func forceRepairGateway() async -> ForceRepairReport {
        var report = ForceRepairReport()
        addLog("Force repair: starting")

        repairConfigFile(report: &report)
        truncateOversizedLogs(report: &report)
        await forceKillGatewayProcesses(report: &report)

        do {
            try await start()
            report.note(I18n.t("repair.step.restarted"))
        } catch {
            report.fail(I18n.format("repair.step.restartFailed", error.localizedDescription))
        }

        addLog("Force repair: finished (success=\(report.succeeded))")
        return report
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
