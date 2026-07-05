import Foundation

// `swift` interprets a single file, but this guard exercises real app logic.
// Compile the app source(s) plus the embedded driver via swiftc and run it.

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appSources = [
    "OpenClawInstaller/Services/PluginCatalogService.swift",
    "OpenClawInstaller/Models/PluginCatalogItem.swift",
    "OpenClawInstaller/Services/I18nService.swift",
    "OpenClawInstaller/Services/LanguageManager.swift",
    "OpenClawInstaller/Models/MarketplaceAgent.swift",
    "OpenClawInstaller/Models/SkillCatalogItem.swift",
]

let driverSource = #"""
import Foundation

@main
struct VerifyGoogleCalendarOpenClawAdapter {
    static func main() throws {
        let pluginURL = PluginCatalogService.defaultCacheURL
            .appendingPathComponent("plugins")
            .appendingPathComponent("google-calendar")
        let packageURL = pluginURL.appendingPathComponent("package.json")
        let manifestURL = pluginURL.appendingPathComponent("openclaw.plugin.json")
        let adapterURL = pluginURL.appendingPathComponent("openclaw.adapter.js")

        expect(FileManager.default.fileExists(atPath: manifestURL.path), "google-calendar should include openclaw.plugin.json")
        expect(FileManager.default.fileExists(atPath: packageURL.path), "google-calendar should include package.json")
        expect(FileManager.default.fileExists(atPath: adapterURL.path), "google-calendar should include OpenClaw runtime entry")
        expect(!FileManager.default.fileExists(atPath: pluginURL.appendingPathComponent(".codex-plugin/plugin.json").path), "google-calendar should not keep a Codex source manifest")

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        expect(manifest?["id"] as? String == "google-calendar", "openclaw manifest should use google-calendar id")

        let packageData = try Data(contentsOf: packageURL)
        let package = try JSONSerialization.jsonObject(with: packageData) as? [String: Any]
        let openclaw = package?["openclaw"] as? [String: Any]
        let extensions = openclaw?["extensions"] as? [String]
        expect(extensions == ["./openclaw.adapter.js"], "package.json should expose ./openclaw.adapter.js as an OpenClaw extension")

        let adapterText = try String(contentsOf: adapterURL, encoding: .utf8)
        expect(adapterText.range(of: "codex", options: [.caseInsensitive]) == nil, "adapter should not mention Codex")

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

"""#

let fm = FileManager.default
let workDir = fm.temporaryDirectory
    .appendingPathComponent("verify_google_calendar_openclaw_adapter-\(UUID().uuidString)")
try! fm.createDirectory(at: workDir, withIntermediateDirectories: true)
let driverURL = workDir.appendingPathComponent("driver.swift")
try! driverSource.write(to: driverURL, atomically: true, encoding: .utf8)
let binaryURL = workDir.appendingPathComponent("verify")

@discardableResult
func run(_ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    do { try process.run() } catch {
        fputs("FAIL: could not launch \(arguments[0]): \(error)\n", stderr)
        exit(1)
    }
    process.waitUntilExit()
    return process.terminationStatus
}

var compileArgs = ["swiftc"]
compileArgs += appSources.map { repoRoot.appendingPathComponent($0).path }
compileArgs += [driverURL.path, "-o", binaryURL.path]
if run(compileArgs) != 0 {
    fputs("FAIL: app sources + verify_google_calendar_openclaw_adapter driver no longer compile\n", stderr)
    try? fm.removeItem(at: workDir)
    exit(1)
}
let status = run([binaryURL.path])
try? fm.removeItem(at: workDir)
exit(status)
