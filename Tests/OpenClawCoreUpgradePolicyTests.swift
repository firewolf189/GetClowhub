import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case assertion(String)
    var description: String {
        switch self {
        case .assertion(let message): message
        }
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure.assertion(message) }
}

@main
private enum OpenClawCoreUpgradePolicyTests {
    static func main() throws {
        try sixTenToBundledProceedsWhenHealthy()
        try newerRunningCoreIsNeverDowngraded()
        try nonSixTenIsSkipped()
        try missingVersionSkips()
        try automaticUpgradeRequiresServingGateway()
        try forceMayProceedWhenGatewayIsDown()
        try locatesPackageDirFromPlistArguments()
        try locatesPackageDirFromServiceEnvWrapper()
        print("PASS: 6.10 -> 7.1-2 upgrade eligibility")
    }

    private static func sixTenToBundledProceedsWhenHealthy() throws {
        let result = OpenClawCoreUpgradePolicy.eligibility(
            runningVersion: "2026.6.10",
            bundledVersion: "2026.7.1-2",
            gatewayServing: true,
            force: false
        )
        try expect(
            result == .proceed(runningVersion: "2026.6.10"),
            "healthy 6.10 must be allowed to move to bundled 7.1-2, got \(result)"
        )
    }

    private static func newerRunningCoreIsNeverDowngraded() throws {
        let eight = OpenClawCoreUpgradePolicy.eligibility(
            runningVersion: "2026.8.2",
            bundledVersion: "2026.7.1-2",
            gatewayServing: true,
            force: false
        )
        try expect(
            {
                if case .skip(let reason) = eight { return reason.contains("already current") }
                return false
            }(),
            "8.2 must not be swapped to bundled 7.1-2, got \(eight)"
        )
        let seven = OpenClawCoreUpgradePolicy.eligibility(
            runningVersion: "2026.7.1-2",
            bundledVersion: "2026.7.1-2",
            gatewayServing: true,
            force: true
        )
        try expect(
            {
                if case .skip = seven { return true }
                return false
            }(),
            "force must still refuse to touch an already-current or newer core, got \(seven)"
        )
    }

    private static func nonSixTenIsSkipped() throws {
        let result = OpenClawCoreUpgradePolicy.eligibility(
            runningVersion: "2026.3.2",
            bundledVersion: "2026.7.1-2",
            gatewayServing: true,
            force: false
        )
        try expect(
            {
                if case .skip(let reason) = result { return reason.contains("not 2026.6.10") }
                return false
            }(),
            "only 6.10 is in scope, got \(result)"
        )
    }

    private static func missingVersionSkips() throws {
        let result = OpenClawCoreUpgradePolicy.eligibility(
            runningVersion: nil,
            bundledVersion: "2026.7.1-2",
            gatewayServing: true,
            force: false
        )
        try expect(
            {
                if case .skip(let reason) = result { return reason.contains("Cannot determine") }
                return false
            }(),
            "nil running version must skip, got \(result)"
        )
    }

    private static func automaticUpgradeRequiresServingGateway() throws {
        let result = OpenClawCoreUpgradePolicy.eligibility(
            runningVersion: "2026.6.10",
            bundledVersion: "2026.7.1-2",
            gatewayServing: false,
            force: false
        )
        try expect(
            {
                if case .skip(let reason) = result { return reason.contains("not serving") }
                return false
            }(),
            "automatic swap must wait until the gateway is healthy, got \(result)"
        )
    }

    private static func forceMayProceedWhenGatewayIsDown() throws {
        let result = OpenClawCoreUpgradePolicy.eligibility(
            runningVersion: "2026.6.10",
            bundledVersion: "2026.7.1-2",
            gatewayServing: false,
            force: true
        )
        try expect(
            result == .proceed(runningVersion: "2026.6.10"),
            "user-initiated force on a down 6.10 gateway may proceed, got \(result)"
        )
    }

    private static func locatesPackageDirFromPlistArguments() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("openclaw-running-core-\(UUID().uuidString)")
        let pkg = root.appendingPathComponent("lib/node_modules/openclaw")
        try fm.createDirectory(at: pkg.appendingPathComponent("dist"), withIntermediateDirectories: true)
        let json = #"{"name":"openclaw","version":"2026.8.2"}"#
        try json.data(using: .utf8)?.write(to: pkg.appendingPathComponent("package.json"))
        let args = [
            "/bin/sh",
            "/tmp/wrapper.sh",
            pkg.appendingPathComponent("dist/index.js").path,
            "gateway",
            "--port",
            "18789"
        ]
        let found = OpenClawRunningCoreLocator.packageDirectory(containingOpenClawPathIn: args, fileManager: fm)
        try expect(found?.path == pkg.path, "plist arguments must resolve to the openclaw package dir, got \(found?.path ?? "nil")")
        try expect(
            OpenClawRunningCoreLocator.version(atPackageDirectory: pkg, fileManager: fm) == "2026.8.2",
            "package.json version must be 2026.8.2"
        )
        try? fm.removeItem(at: root)
    }

    /// 8.x LaunchAgents wrap node+index.js; 6.10 typically points at openclaw.mjs.
    /// Walking ProgramArguments must still find the package, not the wrapper.
    private static func locatesPackageDirFromServiceEnvWrapper() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("openclaw-wrapper-core-\(UUID().uuidString)")
        let pkg = root.appendingPathComponent("node/lib/node_modules/openclaw")
        try fm.createDirectory(at: pkg.appendingPathComponent("dist"), withIntermediateDirectories: true)
        let json = #"{"name":"openclaw","version":"2026.8.2"}"#
        try json.data(using: .utf8)?.write(to: pkg.appendingPathComponent("package.json"))
        let args = [
            "/bin/sh",
            "/tmp/ai.openclaw.gateway-env-wrapper.sh",
            "/tmp/ai.openclaw.gateway.env",
            "/tmp/node/bin/node",
            "--max-old-space-size=8192",
            pkg.appendingPathComponent("dist/index.js").path,
            "gateway",
            "--port",
            "18789"
        ]
        let found = OpenClawRunningCoreLocator.packageDirectory(containingOpenClawPathIn: args, fileManager: fm)
        try expect(found?.path == pkg.path, "wrapper ProgramArguments must resolve to the openclaw package, got \(found?.path ?? "nil")")
        try? fm.removeItem(at: root)
    }
}
