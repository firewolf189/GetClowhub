import Foundation

@main
struct VerifyPluginListStatusParsing {
    static func main() {
        let newFormatOutput = """
        Plugins (57/80 enabled)

        ┌──────────────┬──────────┬──────────┬──────────┬────────────────────────────────────┬───────────┐
        │ Name         │ ID       │ Format   │ Status   │ Source                             │ Version   │
        ├──────────────┼──────────┼──────────┼──────────┼────────────────────────────────────┼───────────┤
        │ Context Mode │ context- │ openclaw │ enabled  │ global:context-mode/index.js       │ v1.0.168  │
        │              │ mode     │          │          │                                    │           │
        │ Disabled One │ disabled │ openclaw │ disabled │ global:disabled-one/index.js       │ v1.0.0    │
        └──────────────┴──────────┴──────────┴──────────┴────────────────────────────────────┴───────────┘
        """

        let oldFormatOutput = """
        ┌──────────────┬──────────┬──────────┬────────────────────────────────────┬───────────┐
        │ Name         │ ID       │ Status   │ Source                             │ Version   │
        ├──────────────┼──────────┼──────────┼────────────────────────────────────┼───────────┤
        │ Loaded One   │ loaded   │ loaded   │ global:loaded-one/index.js         │ v1.0.0    │
        │ Disabled One │ disabled │ disabled │ global:disabled-one/index.js       │ v1.0.0    │
        └──────────────┴──────────┴──────────┴────────────────────────────────────┴───────────┘
        """

        let newPlugins = PluginListParser.parse(output: newFormatOutput)
        let contextMode = newPlugins.first { $0.pluginId == "context-mode" }
        let disabledNew = newPlugins.first { $0.pluginId == "disabled" }

        expect(contextMode?.enabled == true, "new format enabled status should parse as enabled")
        expect(contextMode?.source == "global:context-mode/index.js", "new format source should not be shifted into status")
        expect(contextMode?.version == "v1.0.168", "new format version should parse from version column")
        expect(disabledNew?.enabled == false, "new format disabled status should parse as disabled")

        let oldPlugins = PluginListParser.parse(output: oldFormatOutput)
        let loadedOld = oldPlugins.first { $0.pluginId == "loaded" }
        let disabledOld = oldPlugins.first { $0.pluginId == "disabled" }

        expect(loadedOld?.enabled == true, "old format loaded status should remain enabled")
        expect(disabledOld?.enabled == false, "old format disabled status should remain disabled")

        print("Plugin list status parsing verification passed")
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
