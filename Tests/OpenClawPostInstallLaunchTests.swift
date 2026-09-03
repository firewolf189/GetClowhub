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
private enum OpenClawPostInstallLaunchTests {
    static func main() throws {
        try noPidMeansKickstart()
        try servingMeansDoNotTouch()
        try livePidWaitsInsteadOfRestart()
        try parsesLaunchctlListFormats()
        try missingServiceIsNoPid()
        print("PASS: post-install launch contract")
    }

    private static func noPidMeansKickstart() throws {
        try expect(
            OpenClawPostInstallLaunchPolicy.decide(serving: false, launchdPid: nil) == .kickstart,
            "install --force with no PID must kickstart"
        )
        try expect(
            OpenClawPostInstallLaunchPolicy.decide(serving: false, launchdPid: 0) == .kickstart,
            "PID 0 is launchd's 'not running' and must kickstart"
        )
    }

    private static func servingMeansDoNotTouch() throws {
        try expect(
            OpenClawPostInstallLaunchPolicy.decide(serving: true, launchdPid: nil) == .alreadyServing,
            "an answering gateway must not be restarted"
        )
        try expect(
            OpenClawPostInstallLaunchPolicy.decide(serving: true, launchdPid: 4242) == .alreadyServing,
            "health wins over PID when the port already answers"
        )
    }

    private static func livePidWaitsInsteadOfRestart() throws {
        try expect(
            OpenClawPostInstallLaunchPolicy.decide(serving: false, launchdPid: 59205)
                == .waitForExistingProcess(pid: 59205),
            "a live PID that has not bound /health must wait, not restart"
        )
    }

    private static func parsesLaunchctlListFormats() throws {
        let plist = """
        {
            "Label" = "ai.openclaw.gateway";
            "PID" = 30626;
            "LimitLoadToSessionType" = "Aqua";
        }
        """
        try expect(
            OpenClawPostInstallLaunchPolicy.launchdPid(fromListOutput: plist) == 30626,
            "plist-style launchctl list must yield PID 30626"
        )
        let tab = "4054\t0\tai.openclaw.gateway"
        try expect(
            OpenClawPostInstallLaunchPolicy.launchdPid(fromListOutput: tab) == 4054,
            "tab-separated launchctl list must yield PID 4054"
        )
        let printLine = "    pid = 88112"
        try expect(
            OpenClawPostInstallLaunchPolicy.launchdPid(fromListOutput: printLine) == 88112,
            "launchctl print pid = N must yield N"
        )
        let loadedNoProcess = "-\t0\tai.openclaw.gateway"
        try expect(
            OpenClawPostInstallLaunchPolicy.launchdPid(fromListOutput: loadedNoProcess) == nil,
            "a dash PID is not a running process"
        )
        let zeroPid = "\"PID\" = 0;"
        try expect(
            OpenClawPostInstallLaunchPolicy.launchdPid(fromListOutput: zeroPid) == nil,
            "PID 0 means loaded but not running"
        )
    }

    private static func missingServiceIsNoPid() throws {
        try expect(
            OpenClawPostInstallLaunchPolicy.launchdPid(fromListOutput: "Could not find service \"ai.openclaw.gateway\" in domain") == nil,
            "a missing LaunchAgent is no PID"
        )
        try expect(
            OpenClawPostInstallLaunchPolicy.launchdPid(fromListOutput: nil) == nil,
            "nil launchctl output is no PID"
        )
    }
}
