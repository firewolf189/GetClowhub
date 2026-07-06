//
//  PluginManagement.swift
//  Dashboard compatibility facade for plugin feature state.
//

import Foundation

extension DashboardViewModel {
    func loadPlugins() async {
        await pluginListViewModel.loadPlugins()
    }

    func loadPluginMarket(forceSync: Bool = false) async {
        await pluginListViewModel.loadPluginMarket(forceSync: forceSync)
    }

    func installCatalogPlugin(_ item: PluginCatalogItem) async {
        await pluginListViewModel.installCatalogPlugin(item)
    }

    static func parsePluginList(output: String?) -> [PluginInfo] {
        PluginListParser.parse(output: output)
    }

    func enablePlugin(_ plugin: PluginInfo) async {
        await pluginListViewModel.enablePlugin(plugin)
    }

    func disablePlugin(_ plugin: PluginInfo) async {
        await pluginListViewModel.disablePlugin(plugin)
    }

    func installPlugin(spec: String, link: Bool = false) async {
        await pluginListViewModel.installPlugin(spec: spec, link: link)
    }

    @discardableResult
    func installPluginAndReturnSuccess(spec: String, link: Bool = false) async -> Bool {
        await pluginListViewModel.installPluginAndReturnSuccess(spec: spec, link: link)
    }

    func installWeixinPlugin() async {
        await pluginListViewModel.installWeixinPlugin()
    }

    func uninstallPlugin(_ plugin: PluginInfo) async {
        await pluginListViewModel.uninstallPlugin(plugin)
    }

    func updatePlugin(_ plugin: PluginInfo) async {
        await pluginListViewModel.updatePlugin(plugin)
    }

    func updateAllPlugins() async {
        await pluginListViewModel.updateAllPlugins()
    }

    func getPluginInfo(_ plugin: PluginInfo) async -> String? {
        await pluginListViewModel.getPluginInfo(plugin)
    }
}
