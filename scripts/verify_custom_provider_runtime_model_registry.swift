import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func require(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let appSettings = read("OpenClawInstaller/Shared/Models/AppSettings.swift")
let agentOption = read("OpenClawInstaller/Features/Agents/Models/AgentOption.swift")
let providerModelSettings = read("OpenClawInstaller/Features/Settings/ProviderModels/ProviderModelSettings.swift")
let dashboardView = read("OpenClawInstaller/Features/Dashboard/DashboardView.swift")
let chatHelpers = read("OpenClawInstaller/Features/Chat/ChatHelpers.swift")
let englishCommon = read("OpenClawInstaller/Resources/I18n/en/common.json")
let simplifiedChineseCommon = read("OpenClawInstaller/Resources/I18n/zh-Hans/common.json")
let traditionalChineseCommon = read("OpenClawInstaller/Resources/I18n/zh-Hant/common.json")

let saveToFile = slice(
    appSettings,
    from: "    func saveToFile() -> Bool {",
    to: "    // MARK: - Open config file in editor"
)
require(
    saveToFile.contains("mergedRuntimeModelEntries"),
    "AppSettingsManager.saveToFile must build gateway runtime model entries from all configured providers"
)
require(
    saveToFile.contains("defaults[\"models\"] = mergedRuntimeModelEntries"),
    "AppSettingsManager.saveToFile must write the merged runtime model registry to agents.defaults.models"
)
require(
    saveToFile.contains("activeProviderRuntimeModelEntries"),
    "AppSettingsManager.saveToFile must keep active provider default selection separate from the merged runtime registry"
)

let getClawHubWriter = slice(
    appSettings,
    from: "    static func writeGetClawHubProvider",
    to: "    // MARK: - Helpers"
)
require(
    getClawHubWriter.contains("mergedRuntimeModelEntries"),
    "writeGetClawHubProvider must preserve custom provider runtime model entries when syncing official provider models"
)

require(
    agentOption.contains("let runtimeId: String"),
    "ModelOption must distinguish UI selection id from the runtime model id sent to gateway"
)
require(
    agentOption.contains("init(id: String, name: String, tags: [String], runtimeId: String? = nil)"),
    "ModelOption must offer a compatibility initializer that defaults runtimeId to id"
)

require(
    providerModelSettings.contains("runtimeId: runtimeModelId") &&
        providerModelSettings.contains("let runtimeModelId ="),
    "Provider model option creation must compute an explicit runtime id without pushing this logic into the View"
)
require(
    providerModelSettings.contains("first?.runtimeId"),
    "Default composer model selection must use ModelOption.runtimeId"
)

require(
    dashboardView.contains("selectModel(model.runtimeId)") &&
        dashboardView.contains("selected: model.runtimeId == effectiveSelectedModel"),
    "Composer model panel must select and compare using ModelOption.runtimeId"
)

let sendModelPatch = slice(
    chatHelpers,
    from: "        // Apply the composer model as a session-level override.",
    to: "        // Send the message"
)
require(
    sendModelPatch.contains("return") &&
        !sendModelPatch.contains("sending with the session's current model"),
    "Chat send path must not silently continue with the current model after an explicit composer model patch fails"
)
require(
    !chatHelpers.contains("running image review chunk with the session's current model") &&
        chatHelpers.contains("aborting image review chunk to avoid silent model fallback"),
    "Local image review chunks must not silently continue with the current model after an explicit composer model patch fails"
)

for (language, common) in [
    ("en", englishCommon),
    ("zh-Hans", simplifiedChineseCommon),
    ("zh-Hant", traditionalChineseCommon)
] {
    require(
        common.contains("\"dashboard.chat.modelSwitchFailedNotSent\""),
        "\(language) common.json must include the explicit model switch failure copy"
    )
}

print("Custom provider runtime model registry verification passed")
