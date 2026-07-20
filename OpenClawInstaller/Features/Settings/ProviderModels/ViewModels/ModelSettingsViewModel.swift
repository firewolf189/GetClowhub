import Combine
import Foundation

@MainActor
final class ModelSettingsViewModel: ObservableObject {
    @Published var models: [ModelInfo] = []
    @Published var modelOverview: ModelOverview = ModelOverview()
    @Published var activeComposerModel: String = ""
    /// Per-request reasoning effort chosen in the composer. `.auto` sends no
    /// explicit `thinking` field. Clamped to the active model's supported tiers
    /// whenever the composer model changes.
    @Published var activeComposerEffort: ThinkingEffort = .auto
    /// Remembered effort per model id, restored across launches / model switches.
    @Published var thinkingDefaultByModel: [String: ThinkingEffort] = ThinkingEffortStore.load()
    @Published var maxConcurrentTasks: Int = 4
    @Published var fallbackModels: [String] = []
    @Published var imageFallbackModels: [String] = []
    @Published var isLoadingModels = false
    @Published var availableModelGroups: [ProviderModelGroup] = []
    @Published var availableModelsForSettings: [ModelOption] = []

    var appliedSessionModels: [String: String] = [:]
    /// Last reasoning level successfully patched onto each gateway session,
    /// so the send path can skip a redundant `sessions.patch` round-trip.
    var appliedSessionThinking: [String: ThinkingEffort] = [:]
}
