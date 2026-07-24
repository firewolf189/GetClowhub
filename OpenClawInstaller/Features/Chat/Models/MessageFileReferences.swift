import Foundation

/// Extracts openable local-file references from an assistant reply so the
/// bubble can surface one-click "open document" chips. Agents report where
/// they saved a deliverable as plain text (`~/Desktop/report.xlsx`,
/// `outputs/分析.xlsx`, `/Users/.../数据.csv`); users then had to copy the
/// path into Finder by hand. Relative paths resolve against the CURRENT
/// agent's workspace (or the session's bound project root) so the chips
/// always point into 对应智能体的对应路径.
enum MessageFileReferences {
    static let maxReferences = 4

    /// Candidate tokens, matched by TWO deliberately backtracking-safe
    /// patterns (a single alternation with nested `(x+/)+…\.` quantifiers
    /// exploded catastrophically on long CJK replies and stalled the
    /// timeline build — the chat rendered blank).
    ///
    /// - absolute / home paths: one flat character class, single quantifier,
    ///   linear scan. `(?<![:\w])` keeps URL tails (`https://host/a/b.pdf`)
    ///   from matching.
    /// - relative paths (`outputs/报告.xlsx`): dots are only allowed in the
    ///   final component's extension, segment count and lengths are bounded,
    ///   and no class overlaps a delimiter — no ambiguity, no backtracking.
    private static let absolutePattern =
        #"(?<![:\w])~?/[\w\-./一-鿿]{2,240}"#
    private static let relativePattern =
        #"(?<![\w/.一-鿿])[\w\-一-鿿]{1,64}(?:/[\w\-一-鿿.]{1,64}){1,6}\.[A-Za-z0-9]{1,8}"#
    private static let regexes: [NSRegularExpression] = {
        [absolutePattern, relativePattern].compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    static func extract(
        from content: String,
        workspaceRoot: String?,
        fileManager: FileManager = .default
    ) -> [String] {
        guard !content.isEmpty, !regexes.isEmpty else { return [] }
        // Deliverable paths live in prose; cap the scanned span so a huge
        // reply can never make row-building expensive.
        let scanned = content.count > 20_000 ? String(content.suffix(20_000)) : content
        let range = NSRange(scanned.startIndex..<scanned.endIndex, in: scanned)
        var seen = Set<String>()
        var results: [String] = []

        let matches = regexes.flatMap { $0.matches(in: scanned, range: range) }.prefix(32)
        for match in matches {
            guard results.count < maxReferences else { break }
            guard let tokenRange = Range(match.range, in: scanned) else { continue }
            var token = String(scanned[tokenRange])
            // Trim trailing punctuation the regex can swallow (sentence dots,
            // markdown emphasis leftovers).
            while let last = token.last, ".,;:)".contains(last) {
                token.removeLast()
            }
            guard token.count >= 3 else { continue }

            guard let resolved = resolve(token, workspaceRoot: workspaceRoot, fileManager: fileManager),
                  !seen.contains(resolved) else { continue }
            seen.insert(resolved)
            results.append(resolved)
        }
        return results
    }

    private static func resolve(
        _ token: String,
        workspaceRoot: String?,
        fileManager: FileManager
    ) -> String? {
        let candidate: String
        if token.hasPrefix("~") {
            candidate = (token as NSString).expandingTildeInPath
        } else if token.hasPrefix("/") {
            candidate = token
        } else if let workspaceRoot, !workspaceRoot.isEmpty {
            // openclaw 2026.7.x moved the main agent's cwd one level down
            // (~/.openclaw/workspace/main/); older cores and per-agent
            // workspaces write at the root. Try both bases.
            for base in [workspaceRoot, (workspaceRoot as NSString).appendingPathComponent("main")] {
                let path = (base as NSString).appendingPathComponent(token)
                if existsAsFile(path, fileManager: fileManager) { return path }
            }
            return nil
        } else {
            return nil
        }

        return existsAsFile(candidate, fileManager: fileManager) ? candidate : nil
    }

    private static func existsAsFile(_ path: String, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
}
