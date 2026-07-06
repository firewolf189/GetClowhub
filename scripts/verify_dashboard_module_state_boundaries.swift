#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

func contents(_ path: String) throws -> String {
    let url = root.appendingPathComponent(path)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CheckFailure(description: "Missing expected file: \(path)")
    }
    return try String(contentsOf: url)
}

func require(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw CheckFailure(description: message)
    }
}

do {
    let skillsView = try contents("OpenClawInstaller/Features/Skills/Views/SkillsTabView.swift")
    let skillsModel = try contents("OpenClawInstaller/Features/Skills/ViewModels/SkillsViewModel.swift")
    let pluginsView = try contents("OpenClawInstaller/Features/Plugins/Views/PluginsTabView.swift")
    let pluginsModel = try contents("OpenClawInstaller/Features/Plugins/ViewModels/PluginListViewModel.swift")

    try require(!skillsView.contains("@ObservedObject var viewModel: DashboardViewModel"),
                "SkillsTabView must not observe the full DashboardViewModel.")
    try require(skillsView.contains("@StateObject") && skillsView.contains("SkillsViewModel"),
                "SkillsTabView should own a local SkillsViewModel.")
    try require(skillsModel.contains("final class SkillsViewModel: ObservableObject"),
                "SkillsViewModel should be the Skills module state owner.")
    try require(skillsModel.contains("loadSkillMarket"),
                "SkillsViewModel should own skill catalog loading.")
    try require(skillsModel.contains("installCatalogSkill"),
                "SkillsViewModel should own skill install actions.")

    try require(!pluginsView.contains("@ObservedObject var viewModel: DashboardViewModel"),
                "PluginsTabView must not observe the full DashboardViewModel.")
    try require(pluginsView.contains("@StateObject") && pluginsView.contains("PluginListViewModel"),
                "PluginsTabView should own a local PluginListViewModel.")
    try require(pluginsModel.contains("final class PluginListViewModel: ObservableObject"),
                "PluginListViewModel should be the Plugins module state owner.")
    try require(pluginsModel.contains("loadPluginMarket"),
                "PluginListViewModel should own plugin catalog loading.")
    try require(pluginsModel.contains("installCatalogPlugin"),
                "PluginListViewModel should own plugin install actions.")

    print("dashboard module state boundary checks passed")
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
