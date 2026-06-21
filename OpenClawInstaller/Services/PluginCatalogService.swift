import Foundation

enum PluginCatalogService {
    static let repositoryURL = "https://github.com/zephyrwing-ai/GetClawHubPlugins"
    static let repositoryIdentifier = "zephyrwing-ai/GetClawHubPlugins"

    static var defaultCacheURL: URL {
        URL(fileURLWithPath: NSString("~/.openclaw/getclowhub-plugins-catalog").expandingTildeInPath)
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

    static func installCommand(for item: PluginCatalogItem, cacheURL: URL = defaultCacheURL) -> String {
        let pluginURL = cacheURL.appendingPathComponent(item.relativePath)
        return "openclaw plugins install \(shellQuote(pluginURL.path))"
    }

    static func parseCatalog(rootURL: URL) throws -> [PluginCatalogItem] {
        let pluginsURL = rootURL.appendingPathComponent("plugins")
        guard FileManager.default.fileExists(atPath: pluginsURL.path) else {
            throw PluginCatalogError.missingPluginsDirectory
        }

        var itemsByName: [String: PluginCatalogItem] = [:]

        for item in try parseCatalogItems(rootURL: rootURL, source: .all) {
            itemsByName[item.name] = item
        }

        for item in try parseCatalogItems(rootURL: rootURL, source: .recommend) {
            itemsByName[item.name] = item
        }

        return itemsByName.values.sorted { lhs, rhs in
            if lhs.source != rhs.source {
                return sourceSortRank(lhs.source) < sourceSortRank(rhs.source)
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func parseCatalogItems(
        rootURL: URL,
        source: PluginCatalogSource
    ) throws -> [PluginCatalogItem] {
        let sourceURL = rootURL
            .appendingPathComponent("plugins")
            .appendingPathComponent(source == .all ? "All" : "recommend")

        return pluginDirectories(in: sourceURL).compactMap { pluginURL in
            parsePlugin(rootURL: rootURL, pluginURL: pluginURL, source: source)
        }
    }

    private static func pluginDirectories(in rootURL: URL) -> [URL] {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return directories
            .filter { (try? isDirectory($0)) == true }
            .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    private static func parsePlugin(
        rootURL: URL,
        pluginURL: URL,
        source: PluginCatalogSource
    ) -> PluginCatalogItem? {
        let codexManifestURL = pluginURL
            .appendingPathComponent(".codex-plugin")
            .appendingPathComponent("plugin.json")
        let packageURL = pluginURL.appendingPathComponent("package.json")
        let openClawManifestURL = pluginURL.appendingPathComponent("openclaw.plugin.json")

        let codexManifest: CodexPluginManifest? = decodeJSON(codexManifestURL)
        let packageManifest: PackageManifest? = decodeJSON(packageURL)
        let openClawManifest: OpenClawPluginManifest? = decodeJSON(openClawManifestURL)

        let folderName = pluginURL.lastPathComponent
        let name = codexManifest?.name.nilIfBlank
            ?? (openClawManifest?.id)?.nilIfBlank
            ?? unscopedPackageName(packageManifest?.name)
            ?? folderName
        let openClawPluginID = (openClawManifest?.id)?.nilIfBlank
            ?? unscopedPackageName(packageManifest?.name)
            ?? name
        let displayName = (codexManifest?.interface?.displayName)?.nilIfBlank
            ?? displayNameForPlugin(name)
        let description = (codexManifest?.interface?.shortDescription)?.nilIfBlank
            ?? (codexManifest?.description)?.nilIfBlank
            ?? (packageManifest?.description)?.nilIfBlank
            ?? "OpenClaw plugin"
        let longDescription = (codexManifest?.interface?.longDescription)?.nilIfBlank
            ?? readMarkdownSummary(in: pluginURL)
            ?? description
        let version = (codexManifest?.version)?.nilIfBlank
            ?? (packageManifest?.version)?.nilIfBlank
            ?? ""
        let developerName = (codexManifest?.interface?.developerName)?.nilIfBlank
            ?? (codexManifest?.author?.name)?.nilIfBlank
            ?? ""
        let category = (codexManifest?.interface?.category)?.nilIfBlank
            ?? categoryFromOpenClawManifest(openClawManifest, packageManifest: packageManifest)
        let capabilities = codexManifest?.interface?.capabilities ?? []
        let keywords = codexManifest?.keywords ?? []
        let relativePath = relativePath(from: rootURL, to: pluginURL)
        let iconURL = preferredIconURL(in: pluginURL, manifest: codexManifest)
        let hasExtensions = packageManifest?.openclaw?.extensions.isEmpty == false
        let isInstallable = hasExtensions && FileManager.default.fileExists(atPath: openClawManifestURL.path)

        return PluginCatalogItem(
            id: name,
            name: name,
            displayName: displayName,
            description: description,
            longDescription: longDescription,
            version: version,
            developerName: developerName,
            category: category,
            capabilities: capabilities,
            keywords: keywords,
            relativePath: relativePath,
            source: source,
            iconURL: iconURL,
            repositoryURL: (codexManifest?.repository)?.nilIfBlank,
            homepageURL: (codexManifest?.homepage)?.nilIfBlank ?? (codexManifest?.interface?.websiteURL)?.nilIfBlank,
            openClawPluginID: openClawPluginID,
            isOpenClawInstallable: isInstallable
        )
    }

    private static func decodeJSON<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func preferredIconURL(in pluginURL: URL, manifest: CodexPluginManifest?) -> URL? {
        let candidates = [
            manifest?.interface?.logo,
            manifest?.interface?.composerIcon
        ].compactMap { $0?.nilIfBlank }

        for candidate in candidates {
            if let url = assetURL(from: candidate, relativeTo: pluginURL) {
                return url
            }
        }

        let assetsURL = pluginURL.appendingPathComponent("assets")
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

    private static func assetURL(from value: String, relativeTo pluginURL: URL) -> URL? {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        guard !trimmed.isEmpty, !trimmed.contains("://") else { return nil }
        let url = trimmed.hasPrefix("/")
            ? URL(fileURLWithPath: trimmed)
            : pluginURL.appendingPathComponent(trimmed)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func imageRank(_ url: URL) -> Int {
        let name = url.lastPathComponent.lowercased()
        if name == "icon.png" || name == "logo.png" { return 0 }
        if name.hasSuffix(".png") { return 1 }
        if name.hasSuffix(".jpg") || name.hasSuffix(".jpeg") { return 2 }
        if name.hasSuffix(".webp") { return 3 }
        if name.hasSuffix(".svg") { return 4 }
        return 5
    }

    private static func categoryFromOpenClawManifest(
        _ manifest: OpenClawPluginManifest?,
        packageManifest: PackageManifest?
    ) -> String {
        if manifest?.channels.isEmpty == false {
            return "Communication"
        }
        if manifest?.kind == "memory" {
            return "Memory"
        }
        if packageManifest?.openclaw?.channel != nil {
            return "Communication"
        }
        return "Productivity"
    }

    private static func readMarkdownSummary(in pluginURL: URL) -> String? {
        let candidates = ["README.md", "readme.md"]
        for candidate in candidates {
            let url = pluginURL.appendingPathComponent(candidate)
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func unscopedPackageName(_ packageName: String?) -> String? {
        guard let packageName = packageName?.nilIfBlank else { return nil }
        if let slashIndex = packageName.lastIndex(of: "/") {
            return String(packageName[packageName.index(after: slashIndex)...])
        }
        return packageName
    }

    private static func displayNameForPlugin(_ name: String) -> String {
        name
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
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

    private static func sourceSortRank(_ source: PluginCatalogSource) -> Int {
        switch source {
        case .recommend:
            return 0
        case .all:
            return 1
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private enum PluginCatalogError: LocalizedError {
    case missingPluginsDirectory

    var errorDescription: String? {
        switch self {
        case .missingPluginsDirectory:
            return "Plugin catalog is missing the plugins directory."
        }
    }
}

private struct CodexPluginManifest: Decodable {
    let name: String
    let version: String?
    let description: String?
    let author: Author?
    let homepage: String?
    let repository: String?
    let keywords: [String]?
    let interface: Interface?

    struct Author: Decodable {
        let name: String?
    }

    struct Interface: Decodable {
        let displayName: String?
        let shortDescription: String?
        let longDescription: String?
        let developerName: String?
        let category: String?
        let capabilities: [String]?
        let websiteURL: String?
        let composerIcon: String?
        let logo: String?
    }
}

private struct PackageManifest: Decodable {
    let name: String?
    let version: String?
    let description: String?
    let openclaw: OpenClawPackageMetadata?
}

private struct OpenClawPackageMetadata: Decodable {
    let extensions: [String]
    let channel: OpenClawChannelMetadata?
}

private struct OpenClawChannelMetadata: Decodable {}

private struct OpenClawPluginManifest: Decodable {
    let id: String?
    let kind: String?
    let channels: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case channels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        channels = try container.decodeIfPresent([String].self, forKey: .channels) ?? []
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
