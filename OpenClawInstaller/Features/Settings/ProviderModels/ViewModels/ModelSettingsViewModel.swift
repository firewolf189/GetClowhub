import Combine
import Foundation

@MainActor
final class ModelSettingsViewModel: ObservableObject {
    @Published var models: [ModelInfo] = []
    @Published var modelOverview: ModelOverview = ModelOverview()
    @Published var activeComposerModel: String = ""
    @Published var maxConcurrentTasks: Int = 4
    @Published var fallbackModels: [String] = []
    @Published var imageFallbackModels: [String] = []
    @Published var isLoadingModels = false
    @Published var availableModelGroups: [ProviderModelGroup] = []
    @Published var availableModelsForSettings: [ModelOption] = []

    var appliedSessionModels: [String: String] = [:]
}
