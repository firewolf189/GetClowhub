import Foundation

/// The set of Node.js versions the installed OpenClaw core will actually run on.
///
/// This exists because the core's `engines.node` is **not** a single lower
/// bound. openclaw 2026.7.x declares:
///
///     >=22.22.3 <23 || >=24.15.0 <25 || >=25.9.0
///
/// and its launcher (`openclaw.mjs` → `ensureSupportedRuntimeVersion`) enforces
/// exactly that with a `process.exit(1)` *before* the gateway binds a port.
///
/// Modelling it as `>= 24.15.0` waves Node 25.0–25.8 through: the core swap
/// succeeds, `launchctl` reports the job as loaded, and the gateway exits on
/// every respawn. That is the "upgrade succeeded but the gateway will not
/// start, it wants a newer Node" failure. So the ranges are honoured literally.
struct NodeRuntimeRequirement: Equatable {
    /// A single half-open range: `>=lowerBound` and, when present, `<upperBound`.
    struct Range: Equatable {
        let lowerBound: String
        /// Exclusive. `nil` means open-ended (e.g. the trailing `>=25.9.0`).
        let upperBound: String?

        func contains(_ version: String) -> Bool {
            guard OpenClawVersionComparator.compare(version, lowerBound) != .orderedAscending else {
                return false
            }
            guard let upperBound else { return true }
            return OpenClawVersionComparator.compare(version, upperBound) == .orderedAscending
        }
    }

    let ranges: [Range]
    /// The requirement in the core's own words, for logs and for telling the
    /// user what their Node needs to be.
    let displayText: String

    /// Parses `">=22.22.3 <23 || >=24.15.0 <25 || >=25.9.0"`.
    ///
    /// Returns `nil` for a missing, blank, or unparseable expression. Failing
    /// open is deliberate: a manifest that predates this field, or one we cannot
    /// read, must not turn into a requirement that rejects every Node and blocks
    /// upgrades outright.
    init?(rangeExpression: String?) {
        guard let rangeExpression else { return nil }
        let trimmed = rangeExpression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parsed = trimmed
            .components(separatedBy: "||")
            .compactMap(Self.parseRange)
        guard !parsed.isEmpty else { return nil }

        self.ranges = parsed
        self.displayText = trimmed
    }

    /// A single clause such as `">=24.15.0 <25"` or `">=25.9.0"`.
    private static func parseRange(_ clause: String) -> Range? {
        var lowerBound: String?
        var upperBound: String?

        for token in clause.split(whereSeparator: { $0 == " " || $0 == "," }) {
            if token.hasPrefix(">=") {
                lowerBound = String(token.dropFirst(2))
            } else if token.hasPrefix("<") && !token.hasPrefix("<=") {
                upperBound = String(token.dropFirst(1))
            }
        }

        guard let lowerBound, Self.looksNumeric(lowerBound) else { return nil }
        if let upperBound, !Self.looksNumeric(upperBound) { return nil }
        return Range(lowerBound: lowerBound, upperBound: upperBound)
    }

    private static func looksNumeric(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard let first = trimmed.first else { return false }
        return first.isNumber
    }

    /// Whether `version` — typically raw `node --version` output — falls inside
    /// any supported range. Unparseable and absent versions fail closed: we would
    /// rather reinstall the bundled Node needlessly than hand the user a gateway
    /// that cannot boot.
    func isSatisfied(by version: String?) -> Bool {
        guard let version else { return false }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.looksNumeric(trimmed) else { return false }
        return ranges.contains { $0.contains(trimmed) }
    }
}
