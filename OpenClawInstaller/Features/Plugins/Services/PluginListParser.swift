import Foundation

enum PluginListParser {
    static func parse(output: String?) -> [PluginInfo] {
        guard let output else { return [] }
        if let plugins = parseJSON(output: output) {
            return plugins
        }

        var results: [PluginInfo] = []
        var currentName: String?
        var currentId: String?
        var currentStatus: String?
        var currentSource: String?
        var currentVersion: String?
        var columnIndexes = ColumnIndexes.oldFormat

        func flushRow() {
            guard var name = currentName, let status = currentStatus else { return }
            var id = currentId ?? ""
            let source = currentSource ?? ""
            let version = currentVersion ?? ""

            if id.isEmpty, !source.isEmpty,
               let colonIdx = source.firstIndex(of: ":"),
               let slashIdx = source[source.index(after: colonIdx)...].firstIndex(of: "/") {
                id = String(source[source.index(after: colonIdx)..<slashIdx])
            }

            if id.isEmpty {
                id = name.replacingOccurrences(of: "@openclaw/", with: "")
            }

            if name.isEmpty { name = id }

            let statusLower = status.lowercased()
            let enabled = statusLower == "enabled" || statusLower == "loaded"
            let origin: PluginOrigin
            if source.hasPrefix("stock:") {
                origin = .bundled
            } else if source.hasPrefix("global:") {
                origin = .global
            } else {
                origin = .unknown
            }

            results.append(PluginInfo(
                channel: name,
                pluginId: id,
                installed: true,
                enabled: enabled,
                source: source,
                version: version,
                origin: origin,
                channelIds: []
            ))
        }

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("│") else { continue }

            let cells = trimmed.components(separatedBy: "│")
                .map { $0.trimmingCharacters(in: .whitespaces) }

            if let indexes = ColumnIndexes(headerCells: cells) {
                columnIndexes = indexes
                continue
            }

            guard cells.count > columnIndexes.status else { continue }

            let name = cell(at: columnIndexes.name, in: cells)
            let pluginId = cell(at: columnIndexes.id, in: cells)
            let status = cell(at: columnIndexes.status, in: cells)
            let source = cell(at: columnIndexes.source, in: cells)
            let version = columnIndexes.version.map { cell(at: $0, in: cells) } ?? ""

            if !status.isEmpty {
                flushRow()
                currentName = name
                currentId = pluginId
                currentStatus = status
                currentSource = source
                currentVersion = version
            } else {
                if !name.isEmpty, let existing = currentName {
                    if existing.hasSuffix("/") || existing.hasSuffix("-") {
                        currentName = existing + name
                    } else {
                        currentName = existing + " " + name
                    }
                }

                if !pluginId.isEmpty {
                    if let existing = currentId, !existing.isEmpty {
                        currentId = existing + pluginId
                    } else {
                        currentId = pluginId
                    }
                }
            }
        }
        flushRow()

        return results
    }

    private static func parseJSON(output: String) -> [PluginInfo]? {
        let jsonText = extractJSONObject(from: output) ?? output
        guard let data = jsonText.data(using: .utf8),
              let root = try? JSONDecoder().decode(PluginListResponse.self, from: data) else {
            return nil
        }

        return root.plugins.map { plugin in
            let statusLower = plugin.status?.lowercased()
            return PluginInfo(
                channel: plugin.name?.nilIfBlank ?? plugin.id,
                pluginId: plugin.id,
                installed: true,
                enabled: plugin.enabled ?? (statusLower == "enabled" || statusLower == "loaded"),
                source: plugin.source ?? "",
                version: plugin.version ?? "",
                origin: plugin.originValue,
                channelIds: plugin.channelIds ?? []
            )
        }
    }

    private static func extractJSONObject(from output: String) -> String? {
        guard let start = output.firstIndex(of: "{"),
              let end = output.lastIndex(of: "}"),
              start <= end else {
            return nil
        }
        return String(output[start...end])
    }

    private static func cell(at index: Int, in cells: [String]) -> String {
        guard cells.indices.contains(index) else { return "" }
        return cells[index]
    }

    private struct ColumnIndexes {
        let name: Int
        let id: Int
        let status: Int
        let source: Int
        let version: Int?

        static let oldFormat = ColumnIndexes(name: 1, id: 2, status: 3, source: 4, version: 5)

        init?(headerCells: [String]) {
            guard let name = headerCells.firstIndex(of: "Name"),
                  let id = headerCells.firstIndex(of: "ID"),
                  let status = headerCells.firstIndex(of: "Status"),
                  let source = headerCells.firstIndex(of: "Source") else {
                return nil
            }

            self.name = name
            self.id = id
            self.status = status
            self.source = source
            self.version = headerCells.firstIndex(of: "Version")
        }

        init(name: Int, id: Int, status: Int, source: Int, version: Int?) {
            self.name = name
            self.id = id
            self.status = status
            self.source = source
            self.version = version
        }
    }
}

private struct PluginListResponse: Decodable {
    let plugins: [JSONPluginInfo]
}

private struct JSONPluginInfo: Decodable {
    let id: String
    let name: String?
    let version: String?
    let source: String?
    let origin: String?
    let enabled: Bool?
    let status: String?
    let channelIds: [String]?

    var originValue: PluginOrigin {
        switch origin {
        case "bundled":
            return .bundled
        case "global":
            return .global
        default:
            if source?.hasPrefix("stock:") == true {
                return .bundled
            }
            if source?.hasPrefix("global:") == true {
                return .global
            }
            return .unknown
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
