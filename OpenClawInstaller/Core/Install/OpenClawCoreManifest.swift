import Foundation

struct OpenClawCoreManifest: Codable, Equatable {
    let version: Int
    let openclawVersion: String
    let bundleName: String
    let minimumAppVersion: String?
    /// Legacy single Node floor. Superseded by `supportedNodeRanges` but still
    /// decoded so an older manifest keeps working; only used as a fallback.
    let minimumNodeVersion: String?
    /// The bundled core's `engines.node` verbatim, e.g.
    /// `">=22.22.3 <23 || >=24.15.0 <25 || >=25.9.0"`.
    ///
    /// This is a set of DISJOINT ranges, not a floor: openclaw 2026.7.x rejects
    /// Node 23.x and Node 25.0–25.8 outright. The upgrade coordinator brings Node
    /// into one of these ranges BEFORE swapping the core in — swapping first
    /// leaves the gateway unable to boot at all.
    let supportedNodeRanges: String?
    let releaseNotes: String?

    /// What the bundled core will actually run on. Prefers the declared range
    /// set; falls back to treating a legacy `minimumNodeVersion` as an
    /// open-ended floor. `nil` when the manifest declares neither.
    var nodeRuntimeRequirement: NodeRuntimeRequirement? {
        if let requirement = NodeRuntimeRequirement(rangeExpression: supportedNodeRanges) {
            return requirement
        }
        guard let minimumNodeVersion, !minimumNodeVersion.isEmpty else { return nil }
        return NodeRuntimeRequirement(rangeExpression: ">=\(minimumNodeVersion)")
    }

    static let resourceName = "openclaw-core-version"
    static let resourceExtension = "json"

    static func loadBundled(bundle: Bundle = .main) throws -> OpenClawCoreManifest? {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(OpenClawCoreManifest.self, from: data)
    }

    var normalizedOpenClawVersion: String {
        OpenClawVersionComparator.normalizedVersion(openclawVersion)
    }

    func isBundledVersionNewer(than installedVersion: String?) -> Bool {
        guard let installedVersion, !installedVersion.isEmpty else {
            return true
        }
        return OpenClawVersionComparator.compare(openclawVersion, installedVersion) == .orderedDescending
    }
}

enum OpenClawVersionComparator {
    static func normalizedVersion(_ raw: String) -> String {
        normalizedComponents(raw)
            .map(String.init)
            .joined(separator: ".")
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = normalizedComponents(lhs)
        let right = normalizedComponents(rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l > r { return .orderedDescending }
            if l < r { return .orderedAscending }
        }
        return .orderedSame
    }

    static func normalizedComponents(_ raw: String) -> [Int] {
        let trimmed = extractVersionString(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let stablePart = trimmed
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? trimmed

        return stablePart
            .split(separator: ".")
            .map { part in
                let digits = part.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
    }

    static func extractVersionString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"v?(\d+(?:\.\d+){1,3})"#
        if let range = trimmed.range(of: pattern, options: .regularExpression) {
            return String(trimmed[range]).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        }
        return trimmed
    }
}
