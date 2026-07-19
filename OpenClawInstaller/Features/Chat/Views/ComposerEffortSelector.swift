import SwiftUI

/// Compact composer control for the per-request reasoning effort.
///
/// Rendered next to the model selector. It only appears when the active model
/// exposes more than `.auto` (i.e. it is a reasoning model), mirroring the
/// Windows client's effort badge. Selecting a tier writes
/// `viewModel.activeComposerEffort`, which the send path maps to the
/// `chat.send` `thinking` field.
struct ComposerEffortSelector: View {
    @ObservedObject var viewModel: DashboardViewModel

    private var supported: [ThinkingEffort] { viewModel.supportedComposerEfforts }

    var body: some View {
        if supported.count > 1 {
            Menu {
                Picker(
                    selection: Binding(
                        get: { viewModel.activeComposerEffort },
                        set: { viewModel.activeComposerEffort = $0 }
                    ),
                    label: EmptyView()
                ) {
                    ForEach(supported) { effort in
                        Text(I18n.t(effort.labelKey)).tag(effort)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: viewModel.activeComposerEffort.iconSystemName)
                        .font(.system(size: 11, weight: .medium))
                    Text(I18n.t(viewModel.activeComposerEffort.labelKey))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .unifiedTooltip(UnifiedTooltipContent(
                title: I18n.t("composer.effort.tooltip"),
                detail: I18n.t(viewModel.activeComposerEffort.labelKey)
            ))
        }
    }
}
