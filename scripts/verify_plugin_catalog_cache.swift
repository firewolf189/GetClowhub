import Foundation

// This guard exercises the real PluginCatalogService against the local plugin
// catalog cache. `swift` can only interpret a single file, so we compile the
// app sources together with an embedded behavioral driver via swiftc and run
// the result.

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appSources = [
    "OpenClawInstaller/Features/Plugins/Services/PluginCatalogService.swift",
    "OpenClawInstaller/Features/Plugins/Models/PluginCatalogItem.swift",
]

let driverSource = #"""
import Foundation

// Test shim: PluginCatalogItem only needs I18n.t for display strings, which
// are not under test here.
enum I18n {
    static func t(_ key: String) -> String { key }
}

@main
struct VerifyPluginCatalogCache {
    static func main() throws {
        let cacheURL = PluginCatalogService.defaultCacheURL
        let items = try PluginCatalogService.parseCatalog(rootURL: cacheURL)
        let recommendedItems = items.filter(\.isRecommended)
        let iconItems = items.filter { $0.iconURL != nil }
        let legacyPathItems = items.filter {
            $0.relativePath.hasPrefix("plugins/All/") ||
            $0.relativePath.hasPrefix("plugins/recommend/")
        }

        expect(items.count >= 50, "expected the plugin cache to expose the remote marketplace catalog")
        expect(!recommendedItems.isEmpty, "expected the plugin cache marketplace JSON to tag recommended plugins")
        expect(!iconItems.isEmpty, "expected plugin icons to resolve from repository assets")
        expect(legacyPathItems.isEmpty, "plugin cache should not use legacy plugins/All or plugins/recommend paths")

        print("Plugin catalog cache verification passed")
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
    .appendingPathComponent("verify_plugin_catalog_cache-\(UUID().uuidString)")
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
    fputs("FAIL: PluginCatalogService app sources + verification driver no longer compile\n", stderr)
    try? fm.removeItem(at: workDir)
    exit(1)
}
let status = run([binaryURL.path])
try? fm.removeItem(at: workDir)
exit(status)
