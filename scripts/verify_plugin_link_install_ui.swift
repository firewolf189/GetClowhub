import Foundation

let pluginsTabURL = URL(fileURLWithPath: "OpenClawInstaller/Views/Dashboard/Plugins/PluginsTabView.swift")
let pluginsModelURL = URL(fileURLWithPath: "OpenClawInstaller/Views/Dashboard/Plugins/PluginsTabModel.swift")
let viewModelURL = URL(fileURLWithPath: "OpenClawInstaller/ViewModels/DashboardViewModel.swift")
let pluginsTab = try String(contentsOf: pluginsTabURL, encoding: .utf8)
let pluginsModel = try String(contentsOf: pluginsModelURL, encoding: .utf8)
let viewModel = try String(contentsOf: viewModelURL, encoding: .utf8)

expect(pluginsTab.contains(#"case link = "Link""#), "install sheet should still expose Link method")
expect(pluginsTab.contains("private var linkSpec"), "Link method should use a typed link spec")
let enPluginsURL = URL(fileURLWithPath: "OpenClawInstaller/Resources/I18n/en/plugins.json")
let enPlugins = try String(contentsOf: enPluginsURL, encoding: .utf8)
expect(pluginsTab.contains(#"TextField(I18n.t("plugins.install.linkPlaceholder"), text: $linkSpec)"#), "Link method should show localized URL-style placeholder")
expect(enPlugins.contains(#""plugins.install.linkPlaceholder": "https://github.com/owner/repo""#), "Link placeholder should be a URL-style example in English strings")
expect(!pluginsTab.contains("case .link: return dirPath"), "Link method should not use a browsed directory path")
expect(!pluginsTab.contains("let isLink = installMethod == .link"), "Link method should not enable OpenClaw --link")
expect(!pluginsTab.contains("await model.installPlugin(spec: spec, link: isLink)"), "Link install should pass the typed spec without --link")
expect(pluginsTab.contains("guard installMethod == .npm"), "preset installed checks should only apply to npm installs")
expect(pluginsTab.contains("let isWeixin = installMethod == .npm && selectedPreset == .weixin"), "Weixin special installer should only run for npm method")

guard let methodSpecificInputRange = pluginsTab.range(of: "// Method-specific input"),
      let linkRange = pluginsTab[methodSpecificInputRange.upperBound...].range(of: "case .link:"),
      let footerRange = pluginsTab[linkRange.upperBound...].range(of: "// Footer") else {
    fail("should find Link case body")
}
let linkBody = String(pluginsTab[linkRange.lowerBound..<footerRange.lowerBound])
expect(!linkBody.contains("browseDirectory()"), "Link method should not open a directory browser")
expect(!linkBody.contains(".disabled(true)"), "Link method text field should be editable")
expect(linkBody.contains(#"I18n.t("plugins.install.pluginLink")"#), "Link method should label the input as a link")
expect(enPlugins.contains(#""plugins.install.pluginLink": "Plugin Link""#), "Link label should read Plugin Link in English strings")

expect(pluginsModel.contains("openclaw plugins install") || viewModel.contains("openclaw plugins install"), "manual install should use OpenClaw plugin install")

print("Plugin link install UI verification passed")

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

@discardableResult
func expect(_ condition: @autoclosure () -> Bool, _ message: String) -> Bool {
    if condition() {
        return true
    }
    fail(message)
}
