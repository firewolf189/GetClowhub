import Foundation

/// Post-swap launch contract: `gateway install --force` rewrites the LaunchAgent.
/// It does not mean a process is running. Kickstart only when launchd has no PID;
/// a live PID is left alone so first-boot migrations are not raced (2026-08-26).
enum OpenClawPostInstallLaunch: Equatable {
    case kickstart
    case alreadyServing
    case waitForExistingProcess(pid: Int)
}

enum OpenClawPostInstallLaunchPolicy {
    static func decide(serving: Bool, launchdPid: Int?) -> OpenClawPostInstallLaunch {
        if serving { return .alreadyServing }
        if let pid = launchdPid, pid > 0 { return .waitForExistingProcess(pid: pid) }
        return .kickstart
    }

    static func launchdPid(fromListOutput output: String?) -> Int? {
        guard let output else { return nil }
        let lower = output.lowercased()
        if lower.contains("could not find service") || lower.contains("no such") {
            return nil
        }
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("\"PID\"") {
                if let pid = firstPositiveInt(in: trimmed) { return pid }
                continue
            }
            let compact = trimmed.lowercased().replacingOccurrences(of: " ", with: "")
            if compact.hasPrefix("pid=") {
                if let pid = firstPositiveInt(in: trimmed) { return pid }
                continue
            }
            let cols = trimmed.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            if cols.count >= 3, cols.contains(where: { $0.contains("ai.openclaw.gateway") }) {
                if let pid = Int(cols[0]), pid > 0 { return pid }
            }
        }
        return nil
    }

    private static func firstPositiveInt(in text: String) -> Int? {
        guard let range = text.range(of: #"\d+"#, options: .regularExpression),
              let pid = Int(text[range]), pid > 0 else {
            return nil
        }
        return pid
    }
}
