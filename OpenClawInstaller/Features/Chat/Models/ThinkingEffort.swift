import Foundation

/// User-selectable reasoning effort for a single chat run. Sent per-request in
/// the `chat.send` `thinking` field.
///
/// `.auto` sends no `thinking` field at all — the gateway/model picks its own
/// default. It is therefore the always-safe choice and the fallback the send
/// path degrades to whenever a model rejects an explicit tier (the gateway is
/// the real source of truth; these family rules are only an optimistic guess).
enum ThinkingEffort: String, CaseIterable, Codable, Equatable, Identifiable {
    case auto
    case off
    case minimal
    case low
    case medium
    case high

    var id: String { rawValue }

    /// The `chat.send` `params.thinking` value, or `nil` for `.auto` (omit the
    /// field so the gateway/model uses its own default).
    ///
    /// openclaw validates `thinking` as a plain STRING enum
    /// (`none`/`minimal`/`low`/`medium`/`high`) and normalizes it internally —
    /// sending an object is rejected with `at /thinking: must be string`.
    var wireValue: String? {
        switch self {
        case .auto:    return nil
        case .off:     return "none"
        case .minimal: return "minimal"
        case .low:     return "low"
        case .medium:  return "medium"
        case .high:    return "high"
        }
    }

    /// Value for `sessions.patch { thinkingLevel }` — the switch the gateway
    /// actually applies to a run. `nil` clears the session override so the
    /// agent's own `thinkingDefault` applies (our `.auto`).
    ///
    /// The session vocabulary is `off|minimal|low|medium|high|xhigh` (note
    /// `off`, not the `none` that `chat.send.thinking` uses).
    var sessionLevelValue: String? {
        switch self {
        case .auto: return nil
        case .off:  return "off"
        default:    return rawValue
        }
    }

    /// i18n key for the compact composer label / menu item.
    var labelKey: String { "composer.effort.\(rawValue)" }

    /// SF Symbol used on the composer badge.
    var iconSystemName: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .off:  return "brain.head.profile"
        default:    return "brain.head.profile.fill"
        }
    }

    // MARK: - Per-model support (family rules)

    /// Efforts a model is expected to accept, `.auto` always first.
    ///
    /// The gateway rejects unsupported tiers, so this is deliberately
    /// conservative and the send path degrades to `.auto` on rejection. Keyed by
    /// model-family prefix rather than baked into the preset so it can track
    /// gateway changes without a data-file bump.
    static func supported(forModelId modelId: String) -> [ThinkingEffort] {
        let id = strippedModelId(modelId).lowercased()
        func matches(_ needles: [String]) -> Bool {
            needles.contains { id.hasPrefix($0) || id.contains($0) }
        }

        // Tier sets mirror the Windows client's per-model adaptive tiers (the
        // gateway rejects unsupported values). Each list below is the effort
        // strings the model accepts; `.auto` (omit the field) is prepended as the
        // always-safe default, `.off` == the gateway's "none".

        // grok rejects every explicit effort EXCEPT "none" → auto + off only.
        if matches(["grok"]) { return [.auto, .off] }
        // OpenAI: none/minimal/low/medium/high (full ladder).
        if matches(["gpt", "o1", "o3", "o4"]) {
            return [.auto, .off, .minimal, .low, .medium, .high]
        }
        // Gemini: none/low/high.
        if matches(["gemini"]) { return [.auto, .off, .low, .high] }
        // DeepSeek: none/medium/high (no minimal, no low).
        if matches(["deepseek"]) { return [.auto, .off, .medium, .high] }
        // GLM / other getclawhub reasoning families: none/low/medium/high
        // (no minimal). Degrade to auto if a specific tier is still refused.
        if matches(["qwen", "glm", "minimax", "kimi", "doubao"]) {
            return [.auto, .off, .low, .medium, .high]
        }
        // Unknown / non-reasoning model → only auto (control stays hidden).
        return [.auto]
    }

    /// True when the model exposes any explicit tier beyond `.auto`.
    static func isConfigurable(forModelId modelId: String) -> Bool {
        supported(forModelId: modelId).count > 1
    }

    /// Clamp a chosen effort to what the (possibly newly-selected) model
    /// supports, falling back to `.auto`.
    static func clamp(_ effort: ThinkingEffort, toModelId modelId: String) -> ThinkingEffort {
        let allowed = supported(forModelId: modelId)
        return allowed.contains(effort) ? effort : .auto
    }

    /// Strip a leading `provider/` prefix: `getclawhub/deepseek-v4-pro` → `deepseek-v4-pro`.
    private static func strippedModelId(_ modelId: String) -> String {
        if let slash = modelId.lastIndex(of: "/") {
            return String(modelId[modelId.index(after: slash)...])
        }
        return modelId
    }
}

/// Persists the per-model reasoning-effort default across launches, mirroring
/// the Windows client's Models-page `thinkingDefault`. Stored as
/// `[modelId: rawValue]` in `UserDefaults`.
enum ThinkingEffortStore {
    private static let key = "composer.thinkingDefaultByModel"

    static func load() -> [String: ThinkingEffort] {
        guard let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: String] else {
            return [:]
        }
        return raw.reduce(into: [:]) { result, pair in
            if let effort = ThinkingEffort(rawValue: pair.value) { result[pair.key] = effort }
        }
    }

    static func save(_ defaults: [String: ThinkingEffort]) {
        UserDefaults.standard.set(defaults.mapValues(\.rawValue), forKey: key)
    }
}
