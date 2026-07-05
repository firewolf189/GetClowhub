//
//  DashboardViewModel+ModelManagement.swift
//  Model management extracted from DashboardViewModel.
//  P1 refactor: file split only, no behavior change.
//

import Foundation

extension DashboardViewModel {

    // MARK: - Model Management

    /// Load models overview, model list, and fallback lists
    func loadModels() async {
        isLoadingModels = true
        async let statusOutput = openclawService.runCommand(
            "openclaw models status 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        async let listOutput = openclawService.runCommand(
            "openclaw models list 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        async let fbOutput = openclawService.runCommand(
            "openclaw models fallbacks list 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        async let imgFbOutput = openclawService.runCommand(
            "openclaw models image-fallbacks list 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        modelOverview = Self.parseModelStatus(output: await statusOutput)
        ensureActiveComposerModel()
        models = Self.parseModelList(output: await listOutput)
            .sorted { a, b in
                // Image-capable models first
                if a.supportsImage != b.supportsImage { return a.supportsImage }
                // Then by context length descending
                let aCtx = Self.parseContextLength(a.contextLength)
                let bCtx = Self.parseContextLength(b.contextLength)
                if aCtx != bCtx { return aCtx > bCtx }
                return a.modelId.localizedCaseInsensitiveCompare(b.modelId) == .orderedAscending
            }
        fallbackModels = Self.parseFallbackList(output: await fbOutput)
        imageFallbackModels = Self.parseFallbackList(output: await imgFbOutput)
        isLoadingModels = false
    }

    /// Parse `models status` output for overview info
    static func parseModelStatus(output: String?) -> ModelOverview {
        guard let output = output else { return ModelOverview() }

        var overview = ModelOverview()
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()

            if lower.hasPrefix("default") {
                if let value = Self.extractStatusValue(trimmed) {
                    overview.defaultModel = value
                }
            } else if lower.hasPrefix("image model") {
                if let value = Self.extractStatusValue(trimmed) {
                    overview.imageModel = value == "-" ? nil : value
                }
            } else if lower.hasPrefix("fallbacks") {
                if let value = Self.extractStatusValue(trimmed) {
                    overview.fallbacks = value == "-" ? "" : value
                }
            } else if lower.hasPrefix("image fallbacks") {
                if let value = Self.extractStatusValue(trimmed) {
                    overview.imageFallbacks = value == "-" ? "" : value
                }
            } else if lower.hasPrefix("aliases") {
                if let value = Self.extractStatusValue(trimmed) {
                    overview.aliases = value == "-" ? "" : value
                }
            }
        }
        return overview
    }

    /// Extract value after ": " in a status line
    private static func extractStatusValue(_ line: String) -> String? {
        guard let colonIdx = line.firstIndex(of: ":") else { return nil }
        let value = line[line.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Parse `fallbacks list` or `image-fallbacks list` output.
    /// Format: "Fallbacks (N):" followed by "- model1" lines, or "- none"
    static func parseFallbackList(output: String?) -> [String] {
        guard let output = output else { return [] }
        var results: [String] = []
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else { continue }
            let value = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if value.lowercased() == "none" || value.isEmpty { continue }
            results.append(value)
        }
        return results
    }

    /// Parse context length string like "128k", "200k", "1M" into a comparable integer.
    static func parseContextLength(_ str: String) -> Int {
        let s = str.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasSuffix("m") {
            return (Int(s.dropLast()) ?? 0) * 1_000_000
        } else if s.hasSuffix("k") {
            return (Int(s.dropLast()) ?? 0) * 1_000
        }
        return Int(s) ?? 0
    }

    /// Parse `models list` output using fixed column positions from header.
    static func parseModelList(output: String?) -> [ModelInfo] {
        guard let output = output else { return [] }

        var results: [ModelInfo] = []
        // Column positions parsed from header
        var colInput = 0
        var colCtx = 0
        var colLocal = 0
        var colAuth = 0
        var colTags = 0
        var headerFound = false

        for line in output.components(separatedBy: .newlines) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            // Detect header and extract column positions
            if !headerFound {
                if let rModel = line.range(of: "Model"),
                   let rInput = line.range(of: "Input"),
                   let rCtx = line.range(of: "Ctx"),
                   let rAuth = line.range(of: "Auth"),
                   let rTags = line.range(of: "Tags") {
                    colInput = line.distance(from: line.startIndex, to: rInput.lowerBound)
                    colCtx = line.distance(from: line.startIndex, to: rCtx.lowerBound)
                    // Local column is optional
                    if let rLocal = line.range(of: "Local") {
                        colLocal = line.distance(from: line.startIndex, to: rLocal.lowerBound)
                    } else {
                        colLocal = colAuth
                    }
                    colAuth = line.distance(from: line.startIndex, to: rAuth.lowerBound)
                    colTags = line.distance(from: line.startIndex, to: rTags.lowerBound)
                    headerFound = true
                }
                continue
            }

            // Extract columns by position
            let len = line.count
            guard len > colInput else { continue }

            func substr(from: Int, to: Int) -> String {
                guard from < len else { return "" }
                let end = min(to, len)
                let start = line.index(line.startIndex, offsetBy: from)
                let finish = line.index(line.startIndex, offsetBy: end)
                return String(line[start..<finish]).trimmingCharacters(in: .whitespaces)
            }

            let modelId = substr(from: 0, to: colInput)
            let input = substr(from: colInput, to: colCtx)
            let ctx = substr(from: colCtx, to: colLocal)
            let local = substr(from: colLocal, to: colAuth)
            let auth = substr(from: colAuth, to: colTags)
            let tags = len > colTags ? String(line[line.index(line.startIndex, offsetBy: colTags)...]).trimmingCharacters(in: .whitespaces) : ""

            guard !modelId.isEmpty else { continue }

            let isDefault = tags.lowercased().contains("default")
            let supportsImage = input.lowercased().contains("image")

            results.append(ModelInfo(
                modelId: modelId,
                input: input,
                contextLength: ctx,
                local: local.lowercased() == "yes",
                authenticated: auth.lowercased() == "yes",
                isDefault: isDefault,
                supportsImage: supportsImage,
                tags: tags
            ))
        }

        return results
    }

    /// Set default model
    func setDefaultModel(_ model: ModelInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw models set '\(model.modelId)' 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage(I18n.format("dashboard.models.toast.setDefaultFailed", output))
        } else {
            showSuccessMessage(I18n.format("dashboard.models.toast.defaultSet", model.modelId))
        }
        await loadModels()
        isPerformingAction = false
    }

    /// Set image model
    func setImageModel(_ model: ModelInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw models set-image '\(model.modelId)' 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage(I18n.format("dashboard.models.toast.setImageFailed", output))
        } else {
            showSuccessMessage(I18n.format("dashboard.models.toast.imageSet", model.modelId))
        }
        await loadModels()
        isPerformingAction = false
    }

    /// Add a model to fallback list
    func addFallback(_ model: ModelInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw models fallbacks add '\(model.modelId)' 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage(I18n.format("dashboard.models.toast.addFallbackFailed", output))
        } else {
            showSuccessMessage(I18n.format("dashboard.models.toast.fallbackAdded", model.modelId))
        }
        await loadModels()
        isPerformingAction = false
    }

    /// Remove a model from fallback list
    func removeFallback(_ modelId: String) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw models fallbacks remove '\(modelId)' 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage(I18n.format("dashboard.models.toast.removeFallbackFailed", output))
        } else {
            showSuccessMessage(I18n.format("dashboard.models.toast.fallbackRemoved", modelId))
        }
        await loadModels()
        isPerformingAction = false
    }

    /// Add a model to image fallback list
    func addImageFallback(_ model: ModelInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw models image-fallbacks add '\(model.modelId)' 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage(I18n.format("dashboard.models.toast.addImageFallbackFailed", output))
        } else {
            showSuccessMessage(I18n.format("dashboard.models.toast.imageFallbackAdded", model.modelId))
        }
        await loadModels()
        isPerformingAction = false
    }

    /// Remove a model from image fallback list
    func removeImageFallback(_ modelId: String) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw models image-fallbacks remove '\(modelId)' 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage(I18n.format("dashboard.models.toast.removeImageFallbackFailed", output))
        } else {
            showSuccessMessage(I18n.format("dashboard.models.toast.imageFallbackRemoved", modelId))
        }
        await loadModels()
        isPerformingAction = false
    }

}
