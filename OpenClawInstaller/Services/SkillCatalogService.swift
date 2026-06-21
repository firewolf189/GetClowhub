import Foundation

enum SkillCatalogService {
    static let repositoryURL = "https://github.com/zephyrwing-ai/GetClowHubSkills"
    static let repositoryIdentifier = "zephyrwing-ai/GetClowHubSkills"

    static var defaultCacheURL: URL {
        URL(fileURLWithPath: NSString("~/.openclaw/getclowhub-skills-catalog").expandingTildeInPath)
    }

    static func syncCommand(cacheURL: URL = defaultCacheURL) -> String {
        let cachePath = shellQuote(cacheURL.path)
        let repo = shellQuote(repositoryURL)
        return """
        if [ -d \(cachePath)/.git ]; then \
        git -C \(cachePath) pull --ff-only; \
        else rm -rf \(cachePath) && git clone --depth 1 \(repo) \(cachePath); fi
        """
    }

    static func installCommand(for item: SkillCatalogItem, cacheURL: URL = defaultCacheURL) -> String {
        let source = FileManager.default.fileExists(atPath: cacheURL.path)
            ? shellQuote(cacheURL.path)
            : shellQuote(repositoryURL)
        return "npx --yes --prefer-offline skills add \(source) --skill \(shellQuote(item.name)) -g -y"
    }

    static func parseCatalog(rootURL: URL) throws -> [SkillCatalogItem] {
        var items: [SkillCatalogItem] = []
        for skillURL in catalogSkillDirectories(rootURL: rootURL) {
            let skillMarkdownURL = skillURL.appendingPathComponent("SKILL.md")
            let markdown = try String(contentsOf: skillMarkdownURL, encoding: .utf8)
            let frontmatter = parseFrontmatter(markdown)
            let folderName = skillURL.lastPathComponent
            let name = frontmatter["name"]?.nilIfBlank ?? folderName
            let description = frontmatter["description"]?.nilIfBlank ?? firstParagraph(in: markdown)
            let documentationMarkdown = markdownBody(in: markdown, fallback: description)

            items.append(
                SkillCatalogItem(
                    id: name,
                    name: name,
                    displayName: displayName(for: name),
                    description: description,
                    documentationMarkdown: documentationMarkdown,
                    category: .builtIn,
                    relativePath: relativePath(from: rootURL, to: skillURL),
                    iconURL: preferredIconURL(in: skillURL, frontmatter: frontmatter)
                )
            )
        }

        return items.sorted { lhs, rhs in
            if lhs.category != rhs.category {
                return categorySortRank(lhs.category) < categorySortRank(rhs.category)
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func catalogSkillDirectories(rootURL: URL) -> [URL] {
        let builtInURL = rootURL
            .appendingPathComponent("skills")
            .appendingPathComponent(SkillCatalogCategory.builtIn.rawValue)
        return directSkillDirectories(in: builtInURL)
    }

    private static func directSkillDirectories(in rootURL: URL) -> [URL] {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return directories
            .filter { (try? isDirectory($0)) == true }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("SKILL.md").path) }
            .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    private static func relativePath(from rootURL: URL, to childURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let childPath = childURL.standardizedFileURL.path
        let prefix = rootPath + "/"
        guard childPath.hasPrefix(prefix) else {
            return childURL.lastPathComponent
        }
        return String(childPath.dropFirst(prefix.count))
    }

    private static func isDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true
    }

    private static func parseFrontmatter(_ markdown: String) -> [String: String] {
        let lines = markdown.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return [:]
        }

        var result: [String: String] = [:]
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "---" { break }
            guard let separator = trimmed.firstIndex(of: ":") else { continue }

            let key = trimmed[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = trimmed[trimmed.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            result[key] = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return result
    }

    private static func firstParagraph(in markdown: String) -> String {
        let withoutFrontmatter = stripFrontmatter(from: markdown)

        return withoutFrontmatter
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                !line.isEmpty && !line.hasPrefix("#") && !line.hasPrefix("```")
            } ?? ""
    }

    private static func markdownBody(in markdown: String, fallback: String) -> String {
        let body = stripFrontmatter(from: markdown)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? fallback : body
    }

    private static func stripFrontmatter(from markdown: String) -> String {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else {
            return markdown
        }

        let searchStart = normalized.index(normalized.startIndex, offsetBy: 4)
        guard let endRange = normalized.range(
            of: "\n---",
            options: [],
            range: searchStart..<normalized.endIndex
        ) else {
            return markdown
        }

        return String(normalized[endRange.upperBound...])
    }

    private static func preferredIconURL(in skillURL: URL, frontmatter: [String: String]) -> URL? {
        for key in ["icon", "image", "logo"] {
            if let value = frontmatter[key]?.nilIfBlank,
               let url = imageURL(from: value, relativeTo: skillURL) {
                return url
            }
        }

        let assetsURL = skillURL.appendingPathComponent("assets")
        guard let enumerator = FileManager.default.enumerator(
            at: assetsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        let imageFiles = enumerator.compactMap { entry -> URL? in
            guard let file = entry as? URL,
                  ["png", "jpg", "jpeg", "webp", "svg"].contains(file.pathExtension.lowercased()) else {
                return nil
            }
            return file
        }

        return imageFiles.sorted { lhs, rhs in
            imageRank(lhs) < imageRank(rhs)
        }.first
    }

    private static func imageURL(from value: String, relativeTo skillURL: URL) -> URL? {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        guard !trimmed.isEmpty, !trimmed.contains("://") else { return nil }

        let url = trimmed.hasPrefix("/")
            ? URL(fileURLWithPath: trimmed)
            : skillURL.appendingPathComponent(trimmed)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func imageRank(_ url: URL) -> Int {
        let name = url.lastPathComponent.lowercased()
        let path = url.path.lowercased()
        let isNested = path.contains("/assets/")
        let nestedPenalty = isNested ? 0 : 10

        if name == "icon.png" { return 0 + nestedPenalty }
        if name.hasSuffix(".png") { return 1 + nestedPenalty }
        if name.hasSuffix(".jpg") || name.hasSuffix(".jpeg") { return 2 + nestedPenalty }
        if name.hasSuffix(".webp") { return 3 + nestedPenalty }
        if name == "icon.svg" { return 4 + nestedPenalty }
        if name.contains("small") && name.hasSuffix(".svg") { return 5 + nestedPenalty }
        if name.hasSuffix(".svg") { return 6 + nestedPenalty }
        return 7 + nestedPenalty
    }

    private static func displayName(for skillName: String) -> String {
        skillName
            .split(separator: "-")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func categorySortRank(_ category: SkillCatalogCategory) -> Int {
        switch category {
        case .builtIn:
            return 1
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
