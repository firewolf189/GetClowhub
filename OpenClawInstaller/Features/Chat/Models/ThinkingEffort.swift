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

    /// The `chat.send` `params.thinking` object, or `nil` for `.auto` (omit the
    /// field entirely). openclaw accepts `{ type: "disabled" }` to turn thinking
    /// off and `{ effort: <tier> }` for an explicit level.
    var wireValue: [String: Any]? {
        switch self {
        case .auto:    return nil
        case .off:     return ["type": "disabled"]
        case .minimal: return ["effort": "minimal"]
        case .low:     return ["effort": "low"]
        case .medium:  return ["effort": "medium"]
        case .high:    return ["effort": "high"]
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

        // grok currently rejects any explicit thinking → auto only.
        if matches(["grok"]) { return [.auto] }
        // OpenAI reasoning family supports the full ladder incl. minimal.
        if matches(["gpt", "o1", "o3", "o4"]) {
            return [.auto, .off, .minimal, .low, .medium, .high]
        }
        // Gemini exposes only low/high.
        if matches(["gemini"]) { return [.auto, .off, .low, .high] }
        // DeepSeek: none / medium / high (empirically no "low").
        if matches(["deepseek"]) { return [.auto, .off, .medium, .high] }
        // Other getclawhub reasoning families — offer the full ladder, degrade
        // to auto if a specific tier is refused.
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
