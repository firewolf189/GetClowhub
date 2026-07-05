import Foundation

@MainActor
final class RecommendedPluginBootstrapper {
    private struct Marker: Codable {
        var version: Int
        var attemptedPluginNames: [String]
        var installedPluginNames: [String]
        var failedPluginNames: [String]
        var completedAt: Date?
    }

    private enum Constants {
        static let markerVersion = 1
        static let markerFilename = "getclowhub-recommended-plugins-bootstrap.json"
        static let installSentinel = "__OPENCLAW_RECOMMENDED_PLUGIN_INSTALL_OK__"
    }

    private let openclawService: OpenClawService
    private var hasStarted = false

    init(openclawService: OpenClawService) {
        self.openclawService = openclawService
    }

    func bootstrapRecommendedPluginsIfNeeded() async {
        guard !hasStarted else { return }
        guard openclawService.status == .running else { return }
        guard !isCompleted else { return }

        hasStarted = true
        defer { hasStarted = false }

        PluginCatalogService.seedBundledCatalogIfNeeded()

        let catalog: [PluginCatalogItem]
        do {
            catalog = try PluginCatalogService.parseCatalog(rootURL: PluginCatalogService.defaultCacheURL)
        } catch {
            return
        }

        let recommendedPlugins = catalog.filter(\.isRecommended)
        guard !recommendedPlugins.isEmpty else {
            writeMarker(
                attemptedPluginNames: [],
                installedPluginNames: [],
                failedPluginNames: [],
                completedAt: Date()
            )
            return
        }

        let installedPluginIDs = await loadInstalledPluginIDs()
        let missingPlugins = recommendedPlugins.filter { !installedPluginIDs.contains($0.openClawPluginID) && !installedPluginIDs.contains($0.name) }

        var attempted: [String] = []
        var installed: [String] = recommendedPlugins
            .filter { installedPluginIDs.contains($0.openClawPluginID) || installedPluginIDs.contains($0.name) }
            .map(\.name)
        var failed: [String] = []

        for plugin in missingPlugins where plugin.isOpenClawInstallable {
            attempted.append(plugin.name)
            let command = PluginCatalogService.installCommand(for: plugin)
            let output = await openclawService.runCommand(
                "(\(command) 2>&1 && echo \(Constants.installSentinel)) | sed 's/\\x1b\\[[0-9;]*m//g'",
                timeout: 180
            )

            if output?.contains(Constants.installSentinel) == true {
                installed.append(plugin.name)
            } else {
                failed.append(plugin.name)
            }
        }

        let recommendedInstallableNames = Set(recommendedPlugins.filter(\.isOpenClawInstallable).map(\.name))
        let completed = failed.isEmpty && Set(installed).isSuperset(of: recommendedInstallableNames)
        writeMarker(
            attemptedPluginNames: attempted,
            installedPluginNames: installed,
            failedPluginNames: failed,
            completedAt: completed ? Date() : nil
        )
    }

    private var markerURL: URL {
        URL(fileURLWithPath: NSString(string: "~/.openclaw/\(Constants.markerFilename)").expandingTildeInPath)
    }

    private var isCompleted: Bool {
        guard let data = try? Data(contentsOf: markerURL),
              let marker = try? JSONDecoder().decode(Marker.self, from: data) else {
            return false
        }
        return marker.version == Constants.markerVersion && marker.completedAt != nil
    }

    private func loadInstalledPluginIDs() async -> Set<String> {
        let output = await openclawService.runCommand(
            "openclaw plugins list 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'",
            timeout: 30
        )
        return Set(
            PluginListParser.parse(output: output).flatMap { plugin in
                [plugin.pluginId, plugin.channel].filter { !$0.isEmpty }
            }
        )
    }

    private func writeMarker(
        attemptedPluginNames: [String],
        installedPluginNames: [String],
        failedPluginNames: [String],
        completedAt: Date?
    ) {
        try? FileManager.default.createDirectory(
            at: markerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let marker = Marker(
            version: Constants.markerVersion,
            attemptedPluginNames: attemptedPluginNames.sorted(),
            installedPluginNames: Array(Set(installedPluginNames)).sorted(),
            failedPluginNames: failedPluginNames.sorted(),
            completedAt: completedAt
        )
        if let data = try? JSONEncoder().encode(marker) {
            try? data.write(to: markerURL, options: .atomic)
        }
    }
}
