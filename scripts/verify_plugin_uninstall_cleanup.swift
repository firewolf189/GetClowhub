import Foundation

@main
struct VerifyPluginUninstallCleanup {
    static func main() throws {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("openclaw-plugin-uninstall-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: rootURL) }

        let pluginURL = rootURL.appendingPathComponent("linear")
        let siblingURL = rootURL.appendingPathComponent("google-calendar")
        try fileManager.createDirectory(at: pluginURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: siblingURL, withIntermediateDirectories: true)
        try "runtime".write(to: pluginURL.appendingPathComponent("openclaw.adapter.js"), atomically: true, encoding: .utf8)

        let resolvedURL = PluginUninstallCleanup.globalInstallURL(
            pluginID: "linear",
            source: "global:linear/openclaw.adapter.js",
            extensionsRoot: rootURL
        )
        expect(resolvedURL?.standardizedFileURL.path == pluginURL.standardizedFileURL.path, "should resolve global plugin install directory")

        let stockURL = PluginUninstallCleanup.globalInstallURL(
            pluginID: "linear",
            source: "stock:linear/openclaw.adapter.js",
            extensionsRoot: rootURL
        )
        expect(stockURL == nil, "should not resolve stock plugins for uninstall cleanup")

        let traversalURL = PluginUninstallCleanup.globalInstallURL(
            pluginID: "linear",
            source: "global:../linear/openclaw.adapter.js",
            extensionsRoot: rootURL
        )
        expect(traversalURL == nil, "should reject paths outside the global extensions root")

        let removedURL = try PluginUninstallCleanup.removeGlobalInstallDirectory(
            pluginID: "linear",
            source: "global:linear/openclaw.adapter.js",
            extensionsRoot: rootURL
        )
        expect(removedURL?.standardizedFileURL.path == pluginURL.standardizedFileURL.path, "should report removed directory")
        expect(!fileManager.fileExists(atPath: pluginURL.path), "should remove the global plugin directory")
        expect(fileManager.fileExists(atPath: siblingURL.path), "should not remove sibling plugin directories")

        print("Plugin uninstall cleanup verification passed")
    }

    @discardableResult
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) -> Bool {
        if condition() {
            return true
        }
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
