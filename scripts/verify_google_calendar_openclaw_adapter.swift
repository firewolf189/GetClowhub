import Foundation

@main
struct VerifyGoogleCalendarOpenClawAdapter {
    static func main() throws {
        let pluginURL = PluginCatalogService.defaultCacheURL
            .appendingPathComponent("plugins")
            .appendingPathComponent("google-calendar")
        let packageURL = pluginURL.appendingPathComponent("package.json")
        let manifestURL = pluginURL.appendingPathComponent("openclaw.plugin.json")
        let indexURL = pluginURL.appendingPathComponent("index.js")

        expect(FileManager.default.fileExists(atPath: manifestURL.path), "google-calendar should include openclaw.plugin.json")
        expect(FileManager.default.fileExists(atPath: packageURL.path), "google-calendar should include package.json")
        expect(FileManager.default.fileExists(atPath: indexURL.path), "google-calendar should include index.js runtime entry")

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        expect(manifest?["id"] as? String == "google-calendar", "openclaw manifest should use google-calendar id")

        let packageData = try Data(contentsOf: packageURL)
        let package = try JSONSerialization.jsonObject(with: packageData) as? [String: Any]
        let openclaw = package?["openclaw"] as? [String: Any]
        let extensions = openclaw?["extensions"] as? [String]
        expect(extensions == ["./index.js"], "package.json should expose ./index.js as an OpenClaw extension")

        let items = try PluginCatalogService.parseCatalog(rootURL: PluginCatalogService.defaultCacheURL)
        let item = items.first { $0.name == "google-calendar" }
        expect(item?.isOpenClawInstallable == true, "catalog should mark google-calendar as OpenClaw installable")

        print("Google Calendar OpenClaw adapter verification passed")
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
