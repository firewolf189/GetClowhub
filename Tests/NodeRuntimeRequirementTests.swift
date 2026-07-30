import Foundation

// The gateway's own launcher refuses to boot on an unsupported Node BEFORE it
// binds a port (openclaw.mjs: ensureSupportedRuntimeVersion -> process.exit(1)).
// Its `engines` field is NOT a single floor — it is a set of disjoint ranges:
//
//     >=22.22.3 <23 || >=24.15.0 <25 || >=25.9.0
//
// A client that models this as one `>= 24.15.0` floor waves Node 25.0–25.8
// through, swaps the core, and hands the user a gateway that exits immediately.
// These cases pin the range semantics so that regression cannot come back.

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
private enum NodeRuntimeRequirementTests {
    static func main() throws {
        try parsesTheCoreDeclaredRangeSet()
        try acceptsOnlyVersionsTheCoreAccepts()
        try rejectsTheNode25GapThatBricksTheGateway()
        try prefersAnUpgradeTargetInsideASupportedRange()
        try treatsAMissingOrUnreadableNodeAsUnsatisfied()
        try survivesRealWorldVersionStrings()
        try degradesToPermissiveWhenNoRequirementIsDeclared()

        print("PASS: node runtime requirement")
    }

    // MARK: - Parsing

    private static func parsesTheCoreDeclaredRangeSet() throws {
        let requirement = try requireParsed(">=22.22.3 <23 || >=24.15.0 <25 || >=25.9.0")
        try expect(requirement.ranges.count == 3, "the core declares three disjoint supported ranges")
        try expect(
            requirement.displayText == ">=22.22.3 <23 || >=24.15.0 <25 || >=25.9.0",
            "a requirement must be able to state itself back to the user verbatim"
        )
    }

    // MARK: - The whole point: agree with the core, version by version

    private static func acceptsOnlyVersionsTheCoreAccepts() throws {
        let requirement = try requireParsed(">=22.22.3 <23 || >=24.15.0 <25 || >=25.9.0")

        // (version, does the core's own isSupportedNodeVersion() accept it)
        let cases: [(String, Bool)] = [
            ("v22.22.2", false),  // below the 22 floor
            ("v22.22.3", true),   // exactly the 22 floor
            ("v22.30.1", true),
            ("v23.0.0", false),   // 23 is excluded entirely
            ("v23.11.0", false),
            ("v24.14.0", false),  // below the 24 floor
            ("v24.15.0", true),   // exactly the 24 floor
            ("v24.18.0", true),   // what the app bundles
            ("v25.0.0", false),   // THE GAP
            ("v25.8.9", false),   // THE GAP, upper edge
            ("v25.9.0", true),    // exactly the 25 floor
            ("v26.0.0", true),    // future majors are open-ended
        ]

        for (version, coreAccepts) in cases {
            try expect(
                requirement.isSatisfied(by: version) == coreAccepts,
                "Node \(version): client says \(requirement.isSatisfied(by: version) ? "OK" : "unsupported"), core says \(coreAccepts ? "OK" : "unsupported") — they must agree or the gateway dies after a 'successful' upgrade"
            )
        }
    }

    private static func rejectsTheNode25GapThatBricksTheGateway() throws {
        let requirement = try requireParsed(">=22.22.3 <23 || >=24.15.0 <25 || >=25.9.0")

        // Spelled out separately because this is the exact reported failure:
        // "upgrade succeeded, gateway will not start, it wants a newer Node".
        for version in ["v25.0.0", "v25.1.0", "v25.5.2", "v25.8.0", "v25.8.99"] {
            try expect(
                !requirement.isSatisfied(by: version),
                "Node \(version) sits in the 25.0–25.8 hole; letting it pass reproduces the reported 'upgraded but cannot start' failure"
            )
        }
    }

    // MARK: - What to install when unsatisfied

    private static func prefersAnUpgradeTargetInsideASupportedRange() throws {
        let requirement = try requireParsed(">=22.22.3 <23 || >=24.15.0 <25 || >=25.9.0")

        try expect(
            requirement.isSatisfied(by: BundledRuntimeVersions.nodeJSVersion),
            "the Node the app bundles (\(BundledRuntimeVersions.nodeJSVersion)) must itself satisfy the core, otherwise reinstalling it cannot fix anything"
        )
    }

    // MARK: - Degenerate inputs

    private static func treatsAMissingOrUnreadableNodeAsUnsatisfied() throws {
        let requirement = try requireParsed(">=24.15.0 <25")

        try expect(!requirement.isSatisfied(by: nil), "no Node at all cannot satisfy a requirement")
        try expect(!requirement.isSatisfied(by: ""), "an empty version string cannot satisfy a requirement")
        try expect(
            !requirement.isSatisfied(by: "not a version"),
            "an unparseable `node --version` must fail closed, not be waved through"
        )
    }

    private static func survivesRealWorldVersionStrings() throws {
        let requirement = try requireParsed(">=24.15.0 <25")

        // `node --version` prints "v24.18.0\n"; some shells add stray whitespace.
        try expect(requirement.isSatisfied(by: "v24.18.0\n"), "a trailing newline from `node --version` must not matter")
        try expect(requirement.isSatisfied(by: "  v24.18.0  "), "surrounding whitespace must not matter")
        try expect(requirement.isSatisfied(by: "24.18.0"), "a missing `v` prefix must not matter")
        try expect(
            requirement.isSatisfied(by: "v24.18.0-nightly20260101"),
            "a prerelease suffix must not defeat the numeric comparison"
        )
    }

    private static func degradesToPermissiveWhenNoRequirementIsDeclared() throws {
        try expect(
            NodeRuntimeRequirement(rangeExpression: nil) == nil,
            "a manifest that declares no Node requirement must yield no requirement, so old manifests keep working"
        )
        try expect(
            NodeRuntimeRequirement(rangeExpression: "   ") == nil,
            "a blank requirement is the same as no requirement"
        )
        try expect(
            NodeRuntimeRequirement(rangeExpression: "gibberish") == nil,
            "an unparseable requirement must not silently become a requirement that rejects every Node"
        )
    }

    // MARK: - Helpers

    private static func requireParsed(_ expression: String) throws -> NodeRuntimeRequirement {
        guard let requirement = NodeRuntimeRequirement(rangeExpression: expression) else {
            throw TestFailure.assertion("could not parse the core's declared range set: \(expression)")
        }
        return requirement
    }
}
