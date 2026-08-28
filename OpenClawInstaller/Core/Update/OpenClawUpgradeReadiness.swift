import Foundation

/// Built-in, reversible upgrade optimization that runs before any gateway stop.
///
/// Field failures (2026-07-22 through 2026-08-24) share one chain: GetClawHub
/// stopped the running gateway, swapped in 2026.7.1-2, then startup migrations
/// refused ready because of leftover 2026.6.10 state. This type migrates that
/// leftover state and gates the swap so a typical machine can reach the bundled
/// core without a destructive outage.
struct OpenClawUpgradeMigrationReport: Equatable {
    var actions: [String] = []
    var quarantineDir: URL?
}

enum OpenClawUpgradeGate: Equatable {
    case allowed
    case blocked(String)
}

enum OpenClawUpgradeReadiness {
    /// Fatal staged-core output only. Doctor warnings such as leftover
    /// update-check text are handled by `remainingBlockersOnDisk`.
    static let blockingPhrases = [
        "refusing to report the gateway ready",
        "startup migrations did not complete",
        "failed post-core payload smoke check",
        "config is invalid",
        "must not have additional properties"
    ]

    static func quarantineRoot(homeDir: String) -> URL {
        URL(fileURLWithPath: homeDir).appendingPathComponent(".openclaw/upgrade-quarantine")
    }

    static func configURL(homeDir: String) -> URL {
        URL(fileURLWithPath: homeDir).appendingPathComponent(".openclaw/openclaw.json")
    }

    static func updateCheckURL(homeDir: String) -> URL {
        URL(fileURLWithPath: homeDir).appendingPathComponent(".openclaw/update-check.json")
    }

    static func sqliteURL(homeDir: String) -> URL {
        URL(fileURLWithPath: homeDir).appendingPathComponent(".openclaw/state/openclaw.sqlite")
    }

    static func npmGlobalOpenclawMjs(homeDir: String) -> URL {
        URL(fileURLWithPath: homeDir)
            .appendingPathComponent(".npm-global/lib/node_modules/openclaw/openclaw.mjs")
    }

    /// Reversible cleanup that must run before stop/swap.
    static func migrateLegacyState(
        homeDir: String,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> OpenClawUpgradeMigrationReport {
        var report = OpenClawUpgradeMigrationReport()
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let quarantine = quarantineRoot(homeDir: homeDir).appendingPathComponent(stamp)

        backupIfPresent(configURL(homeDir: homeDir), to: quarantine, as: "openclaw.json", fileManager: fileManager, report: &report)
        backupIfPresent(updateCheckURL(homeDir: homeDir), to: quarantine, as: "update-check.json", fileManager: fileManager, report: &report)

        if fileManager.fileExists(atPath: updateCheckURL(homeDir: homeDir).path),
           fileManager.fileExists(atPath: sqliteURL(homeDir: homeDir).path) {
            moveToQuarantine(
                updateCheckURL(homeDir: homeDir),
                quarantine: quarantine,
                name: "update-check.json",
                fileManager: fileManager,
                report: &report
            )
            report.actions.append("Quarantined update-check.json because shared SQLite state is present")
        }

        if migrateOpenClawJSON(homeDir: homeDir, fileManager: fileManager, quarantine: quarantine, report: &report) {
            report.actions.append("Wrote migrated openclaw.json")
        }

        isolateMismatchedLegacyBin(homeDir: homeDir, fileManager: fileManager, report: &report)
        if !report.actions.isEmpty {
            report.quarantineDir = quarantine
        }
        return report
    }

    static func evaluateGate(
        output: String?,
        checkRan: Bool,
        bundleExists: Bool,
        nodeSatisfied: Bool
    ) -> OpenClawUpgradeGate {
        if !bundleExists {
            return .blocked("bundled openclaw-bundle.tar.gz is missing")
        }
        if !nodeSatisfied {
            return .blocked("bundled Node does not satisfy the new core runtime range")
        }
        if !checkRan {
            return .blocked("staged-core pre-check could not run")
        }
        let text = output ?? ""
        let lower = text.lowercased()
        for phrase in blockingPhrases where lower.contains(phrase) {
            return .blocked(lineMatching(phrase, in: text) ?? phrase)
        }
        return .allowed
    }

    /// After `migrateLegacyState`, these leftovers still make 2026.7.x refuse ready.
    /// Block the swap on disk facts, not doctor warning wording.
    static func remainingBlockersOnDisk(
        homeDir: String,
        fileManager: FileManager = .default
    ) -> [String] {
        var blockers: [String] = []
        let updateCheck = updateCheckURL(homeDir: homeDir)
        let sqlite = sqliteURL(homeDir: homeDir)
        if fileManager.fileExists(atPath: updateCheck.path),
           fileManager.fileExists(atPath: sqlite.path) {
            blockers.append("update-check.json still present alongside shared SQLite state")
        }

        var seen = Set<String>()
        if let root = readJSON(at: configURL(homeDir: homeDir)),
           let plugins = root["plugins"] as? [String: Any],
           let entries = plugins["entries"] as? [String: Any] {
            for id in entries.keys where pluginNeedsDisable(id: id, homeDir: homeDir, fileManager: fileManager) {
                let key = "plugin:\(id)"
                if seen.insert(key).inserted {
                    blockers.append("incomplete TypeScript-only plugin still on disk: \(id)")
                }
            }
        }

        let extensions = URL(fileURLWithPath: homeDir).appendingPathComponent(".openclaw/extensions")
        if let kids = try? fileManager.contentsOfDirectory(at: extensions, includingPropertiesForKeys: [.isDirectoryKey]) {
            for dir in kids where pluginNeedsDisable(at: dir, fileManager: fileManager) {
                let key = dir.path
                if seen.insert(key).inserted {
                    blockers.append("incomplete TypeScript-only plugin still on disk: \(dir.lastPathComponent)")
                }
            }
        }
        return blockers
    }

    static func pluginNeedsDisable(id: String, homeDir: String, fileManager: FileManager = .default) -> Bool {
        let dirs = resolvePluginDirs(id: id, homeDir: homeDir, fileManager: fileManager)
        guard !dirs.isEmpty else { return false }
        if dirs.contains(where: { hasCompiledRuntime(at: $0, fileManager: fileManager) }) {
            return false
        }
        return dirs.contains(where: { hasTypeScriptOnlyEntry(at: $0, fileManager: fileManager) })
    }

    static func pluginNeedsDisable(at pluginDir: URL, fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: pluginDir.path) else { return false }
        if hasCompiledRuntime(at: pluginDir, fileManager: fileManager) { return false }
        return hasTypeScriptOnlyEntry(at: pluginDir, fileManager: fileManager)
    }

    /// Copy of `openclaw.json` with DingTalk keys the new schema rejects removed.
    /// Used only as `OPENCLAW_CONFIG_PATH` for the staged-core gate so the
    /// still-running old core keeps `robotCode` / `requireMention` / `enableAICard`.
    @discardableResult
    static func writeConfigForStagedGate(
        homeDir: String,
        to dest: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard var root = readJSON(at: configURL(homeDir: homeDir)) else { return false }
        _ = DingTalkChannelConfig.stripRejectedKeys(from: &root)
        try? fileManager.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fileManager.removeItem(at: dest)
        return writeJSON(root, to: dest, fileManager: fileManager)
    }

    /// Strip those DingTalk keys from the live file. Call only after the
    /// pre-upgrade `openclaw.json` has been copied into the swap backup so
    /// rollback restores the old channel payload.
    @discardableResult
    static func stripDingTalkRejectedKeysFromLiveConfig(
        homeDir: String,
        fileManager: FileManager = .default
    ) -> Bool {
        let url = configURL(homeDir: homeDir)
        guard var root = readJSON(at: url) else { return false }
        guard DingTalkChannelConfig.stripRejectedKeys(from: &root) else { return false }
        return writeJSON(root, to: url, fileManager: fileManager)
    }

    static func preferredOpenclawInvocationPath(homeDir: String, fileManager: FileManager = .default) -> String? {
        let mjs = npmGlobalOpenclawMjs(homeDir: homeDir)
        if fileManager.fileExists(atPath: mjs.path) {
            return mjs.path
        }
        let bin = "\(homeDir)/.npm-global/bin/openclaw"
        if fileManager.isExecutableFile(atPath: bin) {
            return bin
        }
        return nil
    }

    // MARK: - Private

    private static func migrateOpenClawJSON(
        homeDir: String,
        fileManager: FileManager,
        quarantine: URL,
        report: inout OpenClawUpgradeMigrationReport
    ) -> Bool {
        let url = configURL(homeDir: homeDir)
        guard var root = readJSON(at: url) else { return false }
        var changed = false

        // DingTalk extra keys stay in the live file until the core swap
        // backup exists. Stripping them here would change a still-running
        // 2026.6.x gateway's channel payload.

        if var plugins = root["plugins"] as? [String: Any] {
            if var entries = plugins["entries"] as? [String: Any] {
                for key in Array(entries.keys) {
                    let dirs = resolvePluginDirs(id: key, homeDir: homeDir, fileManager: fileManager)
                    if pluginNeedsDisable(id: key, homeDir: homeDir, fileManager: fileManager) {
                        var entry = entries[key] as? [String: Any] ?? [:]
                        if (entry["enabled"] as? Bool) != false {
                            entry["enabled"] = false
                            entries[key] = entry
                            report.actions.append("Disabled plugin \(key): package has TypeScript entry but no compiled runtime output")
                            changed = true
                        }
                        // 2026.7.1-2 still runs `update repair` on the on-disk
                        // package even when the entry is disabled, then refuses
                        // ready. Move the broken tree aside so discovery skips it.
                        for dir in dirs where hasTypeScriptOnlyEntry(at: dir, fileManager: fileManager) && !hasCompiledRuntime(at: dir, fileManager: fileManager) {
                            let dest = quarantine.appendingPathComponent("plugin-\(key)-\(dir.lastPathComponent)")
                            try? fileManager.createDirectory(at: quarantine, withIntermediateDirectories: true)
                            if fileManager.fileExists(atPath: dir.path) {
                                try? fileManager.removeItem(at: dest)
                                try? fileManager.moveItem(at: dir, to: dest)
                                if !fileManager.fileExists(atPath: dir.path) {
                                    report.actions.append("Quarantined incomplete plugin package \(dir.path)")
                                    changed = true
                                }
                            }
                        }
                    }
                }
                plugins["entries"] = entries
            }
            root["plugins"] = plugins
        }

        guard changed else { return false }
        return writeJSON(root, to: url, fileManager: fileManager)
    }

    private static func isolateMismatchedLegacyBin(
        homeDir: String,
        fileManager: FileManager,
        report: inout OpenClawUpgradeMigrationReport
    ) {
        let bin = URL(fileURLWithPath: "\(homeDir)/.npm-global/bin/openclaw")
        let mjs = npmGlobalOpenclawMjs(homeDir: homeDir)
        guard fileManager.fileExists(atPath: bin.path) else { return }
        let destination = (try? fileManager.destinationOfSymbolicLink(atPath: bin.path)) ?? ""
        if destination.contains("lib/node_modules/openclaw/openclaw.mjs") || fileManager.fileExists(atPath: mjs.path) {
            return
        }
        let disabled = URL(fileURLWithPath: "\(bin.path).disabled-\(Int(Date().timeIntervalSince1970))")
        try? fileManager.moveItem(at: bin, to: disabled)
        if !fileManager.fileExists(atPath: bin.path) {
            report.actions.append("Renamed mismatched ~/.npm-global/bin/openclaw to \(disabled.lastPathComponent)")
        }
    }

    private static func resolvePluginDirs(id: String, homeDir: String, fileManager: FileManager) -> [URL] {
        let home = URL(fileURLWithPath: homeDir)
        var candidates = [
            home.appendingPathComponent(".openclaw/extensions/\(id)"),
            home.appendingPathComponent(".npm-global/lib/node_modules/\(id)"),
            home.appendingPathComponent(".openclaw/npm/node_modules/\(id)")
        ]
        let searchRoots = [
            home.appendingPathComponent(".openclaw/extensions"),
            home.appendingPathComponent(".openclaw/npm/projects")
        ]
        for root in searchRoots {
            if let kids = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                candidates.append(contentsOf: kids.filter { $0.lastPathComponent.contains(id) })
            }
        }
        return candidates.filter { fileManager.fileExists(atPath: $0.path) }
    }

    private static func hasCompiledRuntime(at pluginDir: URL, fileManager: FileManager) -> Bool {
        let compiled = [
            "dist/index.js", "dist/index.mjs", "dist/index.cjs",
            "index.js", "index.mjs", "index.cjs"
        ]
        if compiled.contains(where: { fileManager.fileExists(atPath: pluginDir.appendingPathComponent($0).path) }) {
            return true
        }
        // Installed npm project trees nest the package one or two levels down.
        if let enumerator = fileManager.enumerator(at: pluginDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            var seen = 0
            while let url = enumerator.nextObject() as? URL {
                seen += 1
                if seen > 400 { break }
                if compiled.contains(url.lastPathComponent) { return true }
            }
        }
        return false
    }

    private static func hasTypeScriptOnlyEntry(at pluginDir: URL, fileManager: FileManager) -> Bool {
        ["index.ts", "src/index.ts"].contains {
            fileManager.fileExists(atPath: pluginDir.appendingPathComponent($0).path)
        }
    }

    private static func backupIfPresent(
        _ source: URL,
        to quarantine: URL,
        as name: String,
        fileManager: FileManager,
        report: inout OpenClawUpgradeMigrationReport
    ) {
        guard fileManager.fileExists(atPath: source.path) else { return }
        try? fileManager.createDirectory(at: quarantine, withIntermediateDirectories: true)
        let dest = quarantine.appendingPathComponent(name)
        if !fileManager.fileExists(atPath: dest.path) {
            try? fileManager.copyItem(at: source, to: dest)
        }
    }

    private static func moveToQuarantine(
        _ source: URL,
        quarantine: URL,
        name: String,
        fileManager: FileManager,
        report: inout OpenClawUpgradeMigrationReport
    ) {
        guard fileManager.fileExists(atPath: source.path) else { return }
        try? fileManager.createDirectory(at: quarantine, withIntermediateDirectories: true)
        let dest = quarantine.appendingPathComponent(name)
        try? fileManager.removeItem(at: dest)
        try? fileManager.moveItem(at: source, to: dest)
    }

    private static func readJSON(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return root
    }

    @discardableResult
    private static func writeJSON(_ root: [String: Any], to url: URL, fileManager: FileManager) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    private static func lineMatching(_ phrase: String, in text: String) -> String? {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.lowercased().contains(phrase) }
    }
}
