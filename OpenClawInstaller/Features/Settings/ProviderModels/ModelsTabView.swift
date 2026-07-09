import SwiftUI

struct ModelsTabView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        SmoothScrollView {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text(I18n.t("dashboard.models.title"))
                        .font(.headline)

                    if !viewModel.models.isEmpty {
                        Text(I18n.format("dashboard.count.configured", Int64(viewModel.models.count)))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        Task { await viewModel.loadModels() }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text(I18n.t("catalog.action.refresh"))
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoadingModels || viewModel.isPerformingAction)

                    SettingsInlineRefreshStatus(isRefreshing: viewModel.isLoadingModels)
                }

                // Overview card
                ModelOverviewCard(overview: viewModel.modelOverview)

                // Fallbacks section
                if !viewModel.fallbackModels.isEmpty || !viewModel.imageFallbackModels.isEmpty {
                    FallbacksCard(
                        fallbacks: viewModel.fallbackModels,
                        imageFallbacks: viewModel.imageFallbackModels,
                        isPerformingAction: viewModel.isPerformingAction,
                        onRemoveFallback: { modelId in
                            Task { await viewModel.removeFallback(modelId) }
                        },
                        onRemoveImageFallback: { modelId in
                            Task { await viewModel.removeImageFallback(modelId) }
                        }
                    )
                }

                if viewModel.models.isEmpty {
                    if viewModel.isLoadingModels {
                        SettingsStaticLoadingPlaceholder(
                            title: I18n.t("dashboard.models.loading"),
                            systemImage: "cpu"
                        )
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "cpu")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text(I18n.t("dashboard.models.empty"))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    }
                } else {
                    // Model list
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.models.enumerated()), id: \.element.id) { index, model in
                            ModelRow(
                                model: model,
                                imageModel: viewModel.modelOverview.imageModel,
                                isFallback: viewModel.fallbackModels.contains(model.modelId),
                                isImageFallback: viewModel.imageFallbackModels.contains(model.modelId),
                                isPerformingAction: viewModel.isPerformingAction,
                                onSetDefault: {
                                    Task { await viewModel.setDefaultModel(model) }
                                },
                                onSetImage: {
                                    Task { await viewModel.setImageModel(model) }
                                },
                                onAddFallback: {
                                    Task { await viewModel.addFallback(model) }
                                },
                                onAddImageFallback: {
                                    Task { await viewModel.addImageFallback(model) }
                                }
                            )

                            if index < viewModel.models.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)

                    // CLI hint
                    HStack {
                        Image(systemName: "terminal")
                            .foregroundColor(.secondary)
                        Text(I18n.t("dashboard.models.cliHint"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("openclaw models --help")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(24)
        }
        .task {
            await viewModel.loadModels()
        }
    }
}

// MARK: - Overview Card

struct ModelOverviewCard: View {
    let overview: ModelOverview

    var body: some View {
        HStack(spacing: 24) {
            OverviewItem(
                icon: "star.fill",
                label: I18n.t("dashboard.models.default"),
                value: overview.defaultModel,
                color: .blue
            )

            Divider().frame(height: 40)

            OverviewItem(
                icon: "photo",
                label: I18n.t("dashboard.models.imageModel"),
                value: overview.imageModel ?? I18n.t("dashboard.models.notSet"),
                color: overview.imageModel != nil ? .green : .secondary
            )

            Divider().frame(height: 40)

            OverviewItem(
                icon: "arrow.triangle.branch",
                label: I18n.t("dashboard.models.fallbacks"),
                value: overview.fallbacks.isEmpty ? I18n.t("dashboard.models.none") : overview.fallbacks,
                color: overview.fallbacks.isEmpty ? .secondary : .orange
            )

            Divider().frame(height: 40)

            OverviewItem(
                icon: "arrow.triangle.branch",
                label: I18n.t("dashboard.models.imageFallbacks"),
                value: overview.imageFallbacks.isEmpty ? I18n.t("dashboard.models.none") : overview.imageFallbacks,
                color: overview.imageFallbacks.isEmpty ? .secondary : .teal
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct OverviewItem: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Fallbacks Card

struct FallbacksCard: View {
    let fallbacks: [String]
    let imageFallbacks: [String]
    let isPerformingAction: Bool
    let onRemoveFallback: (String) -> Void
    let onRemoveImageFallback: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !fallbacks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(I18n.t("dashboard.models.fallbackModels"))
                        .font(.subheadline)
                        .fontWeight(.medium)

                    FlowLayout(spacing: 6) {
                        ForEach(fallbacks, id: \.self) { modelId in
                            FallbackTag(
                                modelId: modelId,
                                color: .orange,
                                isPerformingAction: isPerformingAction,
                                onRemove: { onRemoveFallback(modelId) }
                            )
                        }
                    }
                }
            }

            if !imageFallbacks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(I18n.t("dashboard.models.imageFallbackModels"))
                        .font(.subheadline)
                        .fontWeight(.medium)

                    FlowLayout(spacing: 6) {
                        ForEach(imageFallbacks, id: \.self) { modelId in
                            FallbackTag(
                                modelId: modelId,
                                color: .green,
                                isPerformingAction: isPerformingAction,
                                onRemove: { onRemoveImageFallback(modelId) }
                            )
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct FallbackTag: View {
    let modelId: String
    let color: Color
    let isPerformingAction: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(modelId)
                .font(.system(.caption, design: .monospaced))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .disabled(isPerformingAction)
            .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("dashboard.models.action.remove", fallback: "Remove model")))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .cornerRadius(6)
    }
}

/// Simple flow layout for wrapping tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

// MARK: - Model Row

struct ModelRow: View {
    let model: ModelInfo
    let imageModel: String?
    let isFallback: Bool
    let isImageFallback: Bool
    let isPerformingAction: Bool
    let onSetDefault: () -> Void
    let onSetImage: () -> Void
    let onAddFallback: () -> Void
    let onAddImageFallback: () -> Void

    private var isImageModel: Bool {
        guard let img = imageModel else { return false }
        return model.modelId == img
    }

    var body: some View {
        HStack(spacing: 12) {
            // Model icon
            Image(systemName: model.supportsImage ? "eye" : "cube.box")
                .font(.system(size: 18))
                .foregroundColor(model.isDefault ? .blue : .secondary)
                .frame(width: 28)

            // Model info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.modelId)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(model.isDefault ? .bold : .regular)

                    if model.isDefault {
                        BadgeView(text: I18n.t("dashboard.models.badge.default"), color: .blue)
                    }

                    if isImageModel {
                        BadgeView(text: I18n.t("dashboard.models.badge.image"), color: .green)
                    }

                    if isFallback {
                        BadgeView(text: I18n.t("dashboard.models.badge.fallback"), color: .orange)
                    }

                    if isImageFallback {
                        BadgeView(text: I18n.t("dashboard.models.badge.imageFallback"), color: .teal)
                    }
                }

                HStack(spacing: 10) {
                    Label(model.input, systemImage: model.supportsImage ? "photo.on.rectangle" : "doc.text")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label(model.contextLength, systemImage: "arrow.left.and.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if model.local {
                        Label(I18n.t("dashboard.models.local"), systemImage: "desktopcomputer")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }

                    if model.authenticated {
                        Label(I18n.t("dashboard.models.auth"), systemImage: "checkmark.shield.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 6) {
                if model.supportsImage {
                    Button(isImageModel ? I18n.t("dashboard.models.imageModel") : I18n.t("dashboard.models.action.setImage")) {
                        onSetImage()
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .controlSize(.small)
                    .disabled(isPerformingAction || isImageModel)

                    Button(isImageFallback ? I18n.t("dashboard.models.imageFallbacks") : I18n.t("dashboard.models.action.setImageFallback")) {
                        onAddImageFallback()
                    }
                    .buttonStyle(.bordered)
                    .tint(.teal)
                    .controlSize(.small)
                    .disabled(isPerformingAction || isImageFallback || isImageModel)
                }

                Button(isFallback ? I18n.t("dashboard.models.action.fallback") : I18n.t("dashboard.models.action.setFallback")) {
                    onAddFallback()
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .controlSize(.small)
                .disabled(isPerformingAction || isFallback || model.isDefault)

                if !model.isDefault {
                    Button(I18n.t("dashboard.models.action.setDefault")) {
                        onSetDefault()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isPerformingAction)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct BadgeView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(3)
    }
}

#Preview {
    ModelsTabView(
        viewModel: DashboardViewModel(
            openclawService: OpenClawService(
                commandExecutor: CommandExecutor(
                    permissionManager: PermissionManager()
                )
            ),
            settings: AppSettingsManager(),
            systemEnvironment: SystemEnvironment(
                commandExecutor: CommandExecutor(
                    permissionManager: PermissionManager()
                )
            ),
            commandExecutor: CommandExecutor(
                permissionManager: PermissionManager()
            )
        )
    )
    .frame(width: 700, height: 600)
}
