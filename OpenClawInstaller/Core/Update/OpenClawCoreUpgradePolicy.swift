import Foundation

/// Layer 0: only 2026.6.10 may move to the bundled 2026.7.1-2 core.
/// Newer running cores (7.1-2, 8.2, …) are left alone. 8.x is out of scope.
enum OpenClawCoreUpgradeEligibility: Equatable {
    case proceed(runningVersion: String)
    case skip(String)
}

enum OpenClawCoreUpgradePolicy {
    static let eligibleSourceVersion = "2026.6.10"

    static func eligibility(
        runningVersion: String?,
        bundledVersion: String,
        gatewayServing: Bool,
        force: Bool
    ) -> OpenClawCoreUpgradeEligibility {
        guard let runningVersion, !runningVersion.isEmpty else {
            return .skip("Cannot determine the running OpenClaw version; skipping rather than swapping blind")
        }
        if OpenClawVersionComparator.compare(runningVersion, bundledVersion) != .orderedAscending {
            return .skip("OpenClaw core \(runningVersion) is already current for bundled \(bundledVersion)")
        }
        if !isEligibleSourceVersion(runningVersion) {
            return .skip("Skipping core upgrade: running \(runningVersion) is not \(eligibleSourceVersion); only that source is in scope for bundled \(bundledVersion)")
        }
        if !force, !gatewayServing {
            return .skip("Skipping core upgrade: gateway is not serving; wait until idle and healthy")
        }
        return .proceed(runningVersion: runningVersion)
    }

    static func isEligibleSourceVersion(_ raw: String) -> Bool {
        OpenClawVersionComparator.compare(raw, eligibleSourceVersion) == .orderedSame
    }
}

enum OpenClawRunningCoreLocator {
    static func packageDirectoryFromLaunchAgent(
        homeDir: String,
        fileManager: FileManager = .default
    ) -> URL? {
        let plist = URL(fileURLWithPath: homeDir)
            .appendingPathComponent("Library/LaunchAgents/ai.openclaw.gateway.plist")
        guard let data = try? Data(contentsOf: plist),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let args = root["ProgramArguments"] as? [String] else {
            return nil
        }
        return packageDirectory(containingOpenClawPathIn: args, fileManager: fileManager)
    }

    static func packageDirectory(containingOpenClawPathIn arguments: [String], fileManager: FileManager = .default) -> URL? {
        for argument in arguments {
            if let dir = packageDirectory(walkingFrom: URL(fileURLWithPath: argument), fileManager: fileManager) {
                return dir
            }
        }
        return nil
    }

    static func version(atPackageDirectory dir: URL, fileManager: FileManager = .default) -> String? {
        let packageJSON = dir.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: packageJSON),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = root["version"] as? String,
              !version.isEmpty else {
            return nil
        }
        return version
    }

    private static func packageDirectory(walkingFrom start: URL, fileManager: FileManager) -> URL? {
        var dir = start.isFileURL && start.pathExtension.isEmpty ? start : start.deletingLastPathComponent()
        for _ in 0..<8 {
            let packageJSON = dir.appendingPathComponent("package.json")
            if fileManager.fileExists(atPath: packageJSON.path),
               let data = try? Data(contentsOf: packageJSON),
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let name = root["name"] as? String
                if name == "openclaw" || dir.lastPathComponent == "openclaw" {
                    return dir
                }
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }
}
