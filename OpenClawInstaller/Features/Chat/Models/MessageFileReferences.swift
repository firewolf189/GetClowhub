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
    /// Document/asset extensions accepted for BARE file names (no directory
    /// part). Agents very often name a deliverable with no path at all —
    /// especially inside a "产出文件" table — so those must link too. The
    /// allowlist keeps prose like "v1.1.78" or "3.5" from being treated as a
    /// file name; existence on disk is still required on top of it.
    private static let bareNameExtensions =
        "md|markdown|txt|rtf|csv|tsv|json|ya?ml|xlsx?|docx?|pptx?|pdf|numbers|pages|key"
        + "|png|jpe?g|gif|svg|webp|heic|zip|gz|tar|7z|py|sh|swift|js|ts|tsx|rs|go|java|rb|php"
        + "|html?|css|log|mp4|mov|mp3|wav|m4a"

    /// A bare `name.ext` with no slash. Anchored so it never bites into a
    /// longer path (those are handled by the two patterns above).
    private static var bareNamePattern: String {
        #"(?<![\w/.~一-鿿])[\w\-一-鿿][\w\-一-鿿.]{0,80}\.(?:"# + bareNameExtensions + #")(?![\w])"#
    }

    /// Order matters: absolute, then relative, then bare. Later matches that
    /// overlap an already-staged range are skipped, so a bare name inside a
    /// longer path never double-matches.
    private static let regexes: [NSRegularExpression] = {
        [absolutePattern, relativePattern, bareNamePattern]
            .compactMap { try? NSRegularExpression(pattern: $0) }
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

    /// Custom URL scheme used to make in-prose file references tappable.
    /// `OpenURLAction` in the message view intercepts it and previews the file
    /// in the right inspector instead of handing it to the system.
    static let linkScheme = "gchfile"

    /// Rewrites every resolvable file path in `content` into a markdown link
    /// (`[name](gchfile://<percent-encoded-abs-path>)`) so MarkdownUI renders
    /// it underlined and clickable — Claude-style inline document links.
    ///
    /// Only paths that exist on disk are rewritten, and paths already inside a
    /// markdown link or a code span/fence are left alone (rewriting those would
    /// corrupt the source or produce nested links).
    static func linkify(
        content: String,
        workspaceRoot: String?,
        fileManager: FileManager = .default
    ) -> String {
        guard !content.isEmpty, !regexes.isEmpty else { return content }
        // Models most often present a saved path inside a code span
        // (`outputs/report.md`). Unwrap those FIRST when the span's entire
        // content is a resolvable file path, so the path becomes linkable —
        // Claude underlines these too. Spans holding anything else (real code)
        // stay untouched, and fenced blocks are never unwrapped.
        let content = unwrapPathOnlyCodeSpans(
            in: content, workspaceRoot: workspaceRoot, fileManager: fileManager
        )
        let protectedRanges = self.protectedRanges(in: content)

        // Collect (range, resolvedPath) then apply back-to-front so earlier
        // ranges stay valid while mutating.
        var edits: [(Range<String.Index>, String)] = []
        var seenRanges: [Range<String.Index>] = []
        let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)

        for regex in regexes {
            for match in regex.matches(in: content, range: nsRange) {
                guard var tokenRange = Range(match.range, in: content) else { continue }
                var token = String(content[tokenRange])
                var trimmed = 0
                while let last = token.last, ".,;:)".contains(last) {
                    token.removeLast()
                    trimmed += 1
                }
                guard token.count >= 3 else { continue }
                if trimmed > 0 {
                    tokenRange = tokenRange.lowerBound..<content.index(tokenRange.upperBound, offsetBy: -trimmed)
                }
                // Skip code spans / existing links.
                if protectedRanges.contains(where: { $0.overlaps(tokenRange) }) { continue }
                // Skip overlaps with an edit we already staged (the two
                // patterns can both match the same span).
                if seenRanges.contains(where: { $0.overlaps(tokenRange) }) { continue }
                guard let resolved = resolve(token, workspaceRoot: workspaceRoot, fileManager: fileManager) else {
                    continue
                }
                seenRanges.append(tokenRange)
                edits.append((tokenRange, resolved))
            }
        }
        guard !edits.isEmpty else { return content }

        var result = content
        for (range, resolved) in edits.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            let label = String(result[range])
            // Percent-encode so spaces/CJK survive as a URL; the path is the
            // link body, so `/` must be encoded too or it splits host/path.
            let encoded = resolved.addingPercentEncoding(
                withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            ) ?? resolved
            result.replaceSubrange(range, with: "[\(label)](\(linkScheme)://\(encoded))")
        }
        return result
    }

    /// Decodes a `gchfile://` link back into an absolute path.
    static func path(fromLinkURL url: URL) -> String? {
        guard url.scheme == linkScheme else { return nil }
        let raw = url.absoluteString.dropFirst("\(linkScheme)://".count)
        return String(raw).removingPercentEncoding
    }

    /// Strips the backticks from inline code spans whose ENTIRE content is a
    /// resolvable file path, so the following linkify pass can turn them into
    /// links. Fenced code blocks are excluded — code samples keep their paths
    /// verbatim.
    private static func unwrapPathOnlyCodeSpans(
        in content: String,
        workspaceRoot: String?,
        fileManager: FileManager
    ) -> String {
        guard content.contains("`") else { return content }
        guard let spanRegex = try? NSRegularExpression(pattern: #"`([^`\n]+)`"#) else { return content }
        let fenced = fencedRanges(in: content)
        let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)

        var edits: [(Range<String.Index>, String)] = []
        for match in spanRegex.matches(in: content, range: nsRange) {
            guard let full = Range(match.range, in: content),
                  let inner = Range(match.range(at: 1), in: content) else { continue }
            if fenced.contains(where: { $0.overlaps(full) }) { continue }
            let token = String(content[inner]).trimmingCharacters(in: .whitespaces)
            guard token.count >= 3,
                  resolve(token, workspaceRoot: workspaceRoot, fileManager: fileManager) != nil else { continue }
            edits.append((full, token))
        }
        guard !edits.isEmpty else { return content }

        var result = content
        for (range, token) in edits.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            result.replaceSubrange(range, with: token)
        }
        return result
    }

    private static func fencedRanges(in content: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: #"```[\s\S]*?```"#) else { return [] }
        let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
        return regex.matches(in: content, range: nsRange).compactMap { Range($0.range, in: content) }
    }

    /// Ranges that must not be rewritten: fenced code blocks, inline code
    /// spans, and the target/label of existing markdown links.
    private static func protectedRanges(in content: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        for pattern in [
            #"```[\s\S]*?```"#,          // fenced code
            #"`[^`\n]*`"#,               // inline code
            #"\[[^\]]*\]\([^)]*\)"#,     // existing markdown link
        ] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
            for match in regex.matches(in: content, range: nsRange) {
                if let r = Range(match.range, in: content) { ranges.append(r) }
            }
        }
        return ranges
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
            // Search bases, cheapest first:
            //  1. the workspace itself (also covers "outputs/x.md" style
            //     relative paths, which already carry their subdirectory),
            //  2. `<workspace>/main` — belt-and-braces for the openclaw
            //     2026.7.x nested-cwd layout if the resolver ever lags,
            //  3. immediate subdirectories, because a BARE name is very often
            //     a file the agent wrote into outputs/ or reports/,
            //  4. Desktop/Downloads, common "save it for me" destinations.
            var bases = [workspaceRoot, (workspaceRoot as NSString).appendingPathComponent("main")]
            for base in bases {
                let path = (base as NSString).appendingPathComponent(token)
                if existsAsFile(path, fileManager: fileManager) { return path }
            }
            if !token.contains("/") {
                bases = immediateSubdirectories(of: workspaceRoot, fileManager: fileManager)
                let home = fileManager.homeDirectoryForCurrentUser.path
                bases += [
                    (home as NSString).appendingPathComponent("Desktop"),
                    (home as NSString).appendingPathComponent("Downloads"),
                ]
                for base in bases {
                    let path = (base as NSString).appendingPathComponent(token)
                    if existsAsFile(path, fileManager: fileManager) { return path }
                }
            }
            return nil
        } else {
            return nil
        }

        return existsAsFile(candidate, fileManager: fileManager) ? candidate : nil
    }

    /// Immediate, non-hidden subdirectories of `root`, capped so a workspace
    /// with a huge tree can never make row-building expensive.
    private static func immediateSubdirectories(
        of root: String,
        fileManager: FileManager
    ) -> [String] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: root) else { return [] }
        var dirs: [String] = []
        for name in names.sorted() where !name.hasPrefix(".") {
            let path = (root as NSString).appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                dirs.append(path)
                if dirs.count >= 40 { break }
            }
        }
        return dirs
    }

    private static func existsAsFile(_ path: String, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
}
