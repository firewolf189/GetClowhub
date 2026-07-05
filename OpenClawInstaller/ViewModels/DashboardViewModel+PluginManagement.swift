//
//  DashboardViewModel+PluginManagement.swift
//  Plugin management extracted from DashboardViewModel.
//  P1 refactor: file split only, no behavior change.
//

import Foundation

extension DashboardViewModel {

    // MARK: - Plugin Management

    /// Refresh the installed plugins list by running `openclaw plugins list`
    func loadPlugins() async {
        isLoadingPlugins = true
        // Strip ANSI color codes for clean parsing
        let output = await openclawService.runCommand(
            "openclaw plugins list 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        plugins = Self.parsePluginList(output: output)
            .sorted { a, b in
                if a.enabled != b.enabled { return a.enabled }
                return a.channel.localizedCaseInsensitiveCompare(b.channel) == .orderedAscending
            }
        isLoadingPlugins = false
    }

    /// Load the curated plugin catalog from the GetClowHub plugin repository.
    func loadPluginMarket(forceSync: Bool = false) async {
        if hasLoadedPluginCatalog && !forceSync {
            await loadPlugins()
            return
        }

        guard !isLoadingPluginCatalog else { return }

        isLoadingPluginCatalog = true
        pluginCatalogError = nil

        let cacheGitURL = PluginCatalogService.defaultCacheURL.appendingPathComponent(".git")
        let shouldSync = forceSync || !FileManager.default.fileExists(atPath: cacheGitURL.path)
        let syncOutput: String?
        if shouldSync {
            syncOutput = await openclawService.runCommand(
                "\(PluginCatalogService.syncCommand()) 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'",
                timeout: 120
            )
        } else {
            syncOutput = nil
        }

        do {
            pluginCatalog = try PluginCatalogService.parseCatalog(rootURL: PluginCatalogService.defaultCacheURL)
            hasLoadedPluginCatalog = true
        } catch {
            let detail = syncOutput?.trimmingCharacters(in: .whitespacesAndNewlines)
            pluginCatalogError = detail?.isEmpty == false ? detail : error.localizedDescription
            pluginCatalog = []
            hasLoadedPluginCatalog = false
        }

        await loadPlugins()
        isLoadingPluginCatalog = false
    }

    func installCatalogPlugin(_ item: PluginCatalogItem) async {
        guard installingCatalogPluginName == nil else { return }
        guard item.isOpenClawInstallable else {
            showErrorMessage("\(item.displayName) is not installable by OpenClaw.")
            return
        }

        installingCatalogPluginName = item.name
        let command = PluginCatalogService.installCommand(for: item)
        let output = await openclawService.runCommand(
            "(\(command) 2>&1 && echo __OPENCLAW_PLUGIN_INSTALL_OK__) | sed 's/\\x1b\\[[0-9;]*m//g'",
            timeout: 180
        )
        installingCatalogPluginName = nil

        if output?.contains("__OPENCLAW_PLUGIN_INSTALL_OK__") == true {
            await loadPlugins()
            showSuccessMessage("Installed plugin \(item.displayName)")
        } else {
            let trimmed = output?.trimmingCharacters(in: .whitespacesAndNewlines)
            showErrorMessage("Failed to install \(item.displayName): \(trimmed?.isEmpty == false ? trimmed! : "unknown error")")
        }
    }

    static func parsePluginList(output: String?) -> [PluginInfo] {
        PluginListParser.parse(output: output)
    }

    /// Enable a plugin
    func enablePlugin(_ plugin: PluginInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand("openclaw plugins enable \(plugin.pluginId) 2>&1")
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to enable \(plugin.channel): \(output)")
        } else {
            showSuccessMessage("\(plugin.channel) enabled")
        }
        await loadPlugins()
        isPerformingAction = false
    }

    /// Disable a plugin
    func disablePlugin(_ plugin: PluginInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand("openclaw plugins disable \(plugin.pluginId) 2>&1")
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to disable \(plugin.channel): \(output)")
        } else {
            showSuccessMessage("\(plugin.channel) disabled")
        }
        await loadPlugins()
        isPerformingAction = false
    }

    /// Install a plugin from npm package name or local path
    /// - Parameters:
    ///   - spec: npm package name (e.g. `@openclaw/discord`) or local file/directory path
    ///   - link: if true, uses `--link` flag (for local directory development)
    func installPlugin(spec: String, link: Bool = false) async {
        isPerformingAction = true
        let escapedSpec = spec.replacingOccurrences(of: "'", with: "'\\''")
        var cmd = "openclaw plugins install '\(escapedSpec)'"
        if link {
            cmd += " --link"
        }
        cmd += " 2>&1"
        let output = await openclawService.runCommand(cmd, timeout: 120)
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to install plugin: \(output)")
        } else {
            showSuccessMessage("Plugin installed successfully")
        }
        await loadPlugins()
        isPerformingAction = false
    }

    /// Install the Weixin plugin via npx
    func installWeixinPlugin() async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "npx -y @tencent-weixin/openclaw-weixin-cli@latest install 2>&1", timeout: 120
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to install Weixin plugin: \(output)")
        } else {
            showSuccessMessage("Weixin plugin installed successfully")
        }
        await loadPlugins()
        isPerformingAction = false
    }

    /// Uninstall a user-installed (global) plugin
    func uninstallPlugin(_ plugin: PluginInfo) async {
        guard plugin.origin == .global else {
            showErrorMessage("Built-in plugins cannot be uninstalled. Use Disable instead.")
            return
        }
        isPerformingAction = true
        defer { isPerformingAction = false }

        let output = await openclawService.runCommand(
            "openclaw plugins uninstall \(Self.shellQuote(plugin.pluginId)) --force 2>&1 && echo __OPENCLAW_PLUGIN_UNINSTALL_OK__"
        )
        guard output?.contains("__OPENCLAW_PLUGIN_UNINSTALL_OK__") == true else {
            let detail = output?.trimmingCharacters(in: .whitespacesAndNewlines)
            showErrorMessage("Failed to uninstall \(plugin.channel): \(detail?.isEmpty == false ? detail! : "unknown error")")
            await loadPlugins()
            return
        }

        do {
            _ = try PluginUninstallCleanup.removeGlobalInstallDirectory(
                pluginID: plugin.pluginId,
                source: plugin.source
            )
            showSuccessMessage("\(plugin.channel) uninstalled")
        } catch {
            showErrorMessage("Failed to remove \(plugin.channel) files: \(error.localizedDescription)")
        }

        await loadPlugins()
    }

    /// Update a single plugin
    func updatePlugin(_ plugin: PluginInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw plugins update \(plugin.pluginId) 2>&1", timeout: 120
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to update \(plugin.channel): \(output)")
        } else {
            showSuccessMessage("\(plugin.channel) updated")
        }
        await loadPlugins()
        isPerformingAction = false
    }

    /// Update all plugins
    func updateAllPlugins() async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw plugins update --all 2>&1", timeout: 120
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to update plugins: \(output)")
        } else {
            showSuccessMessage("All plugins updated")
        }
        await loadPlugins()
        isPerformingAction = false
    }

    /// Get detailed info about a plugin
    func getPluginInfo(_ plugin: PluginInfo) async -> String? {
        let output = await openclawService.runCommand(
            "openclaw plugins info \(plugin.pluginId) 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        return output
    }

}
