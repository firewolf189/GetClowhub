import Foundation

// `swift` interprets a single file, but this guard exercises real app logic.
// Compile the app source(s) plus the embedded driver via swiftc and run it.

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appSources = [
    "OpenClawInstaller/Features/Plugins/Services/PluginCatalogService.swift",
    "OpenClawInstaller/Features/Plugins/Models/PluginCatalogItem.swift",
    "OpenClawInstaller/Localization/I18nService.swift",
    "OpenClawInstaller/Localization/LanguageManager.swift",
    "OpenClawInstaller/Features/Agents/Marketplace/MarketplaceAgent.swift",
    "OpenClawInstaller/Features/Skills/Models/SkillCatalogItem.swift",
]

let driverSource = #"""
import Foundation

@main
struct VerifyPluginCatalogOpenClawAdapters {
    static func main() throws {
        let cacheURL = PluginCatalogService.defaultCacheURL
        let items = try PluginCatalogService.parseCatalog(rootURL: cacheURL)
        expect(!items.isEmpty, "plugin catalog should not be empty")

        var failures: [String] = []
        let marketplaceURL = cacheURL
            .appendingPathComponent(".agents")
            .appendingPathComponent("plugins")
            .appendingPathComponent("marketplace.json")
        if let marketplaceText = try? String(contentsOf: marketplaceURL, encoding: .utf8),
           marketplaceText.range(of: "codex", options: [.caseInsensitive]) != nil {
            failures.append("marketplace.json should not contain Codex user-facing wording")
        }

        for item in items {
            let pluginURL = cacheURL.appendingPathComponent(item.relativePath)
            let packageURL = pluginURL.appendingPathComponent("package.json")
            let manifestURL = pluginURL.appendingPathComponent("openclaw.plugin.json")
            let sourceManifestURL = pluginURL
                .appendingPathComponent(".codex-plugin")
                .appendingPathComponent("plugin.json")
            var runtimeURLs: [URL] = []
            if let packageData = try? Data(contentsOf: packageURL),
               let packageJSON = try? JSONSerialization.jsonObject(with: packageData) as? [String: Any],
               let openclaw = packageJSON["openclaw"] as? [String: Any],
               let extensions = openclaw["extensions"] as? [String] {
                runtimeURLs = extensions.map { pluginURL.appendingPathComponent($0) }
            }

            if !FileManager.default.fileExists(atPath: packageURL.path) {
                failures.append("\(item.name): missing package.json")
            }
            if !FileManager.default.fileExists(atPath: manifestURL.path) {
                failures.append("\(item.name): missing openclaw.plugin.json")
            }
            if FileManager.default.fileExists(atPath: sourceManifestURL.path) {
                failures.append("\(item.name): should not keep .codex-plugin/plugin.json in the OpenClaw catalog")
            }
            if runtimeURLs.isEmpty {
                failures.append("\(item.name): package.json does not expose OpenClaw extensions")
            }
            for runtimeURL in runtimeURLs where !FileManager.default.fileExists(atPath: runtimeURL.path) {
                failures.append("\(item.name): missing OpenClaw extension \(runtimeURL.lastPathComponent)")
            }
            if !item.isOpenClawInstallable {
                failures.append("\(item.name): catalog item is not OpenClaw installable")
            }

            let userFacingURLs = [packageURL, manifestURL] + runtimeURLs
            for url in userFacingURLs where FileManager.default.fileExists(atPath: url.path) {
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                if text.range(of: "codex", options: [.caseInsensitive]) != nil {
                    failures.append("\(item.name): user-facing OpenClaw adapter mentions Codex in \(url.lastPathComponent)")
                }
            }
        }

        let installCommands = items.map { PluginCatalogService.installCommand(for: $0, cacheURL: cacheURL) }
        if installCommands.contains(where: { $0.range(of: "codex", options: [.caseInsensitive]) != nil }) {
            failures.append("install commands should not use Codex")
        }
        if installCommands.contains(where: { !$0.contains("openclaw plugins install") }) {
            failures.append("install commands should use openclaw plugins install")
        }

        if !failures.isEmpty {
            fputs("FAIL:\n\(failures.prefix(25).joined(separator: "\n"))\n", stderr)
            if failures.count > 25 {
                fputs("... \(failures.count - 25) more failures\n", stderr)
            }
            exit(1)
        }

        print("Verified \(items.count) plugin catalog items expose OpenClaw adapters")
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
    .appendingPathComponent("verify_plugin_catalog_openclaw_adapters-\(UUID().uuidString)")
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
    fputs("FAIL: app sources + verify_plugin_catalog_openclaw_adapters driver no longer compile\n", stderr)
    try? fm.removeItem(at: workDir)
    exit(1)
}
let status = run([binaryURL.path])
try? fm.removeItem(at: workDir)
exit(status)
