import SwiftUI

/// Composer control for per-request reasoning effort, styled after Claude's
/// thinking-effort interaction (and the Windows client): a compact badge that
/// opens a popover with a draggable capsule slider over the model's supported
/// tiers.
///
/// Only rendered when the active model exposes more than `.auto`. Selecting a
/// tier writes `viewModel.activeComposerEffort`, which the send path maps to the
/// `chat.send` `thinking` field and persists per model.
struct ComposerEffortSelector: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var isOpen = false

    private var supported: [ThinkingEffort] { viewModel.supportedComposerEfforts }

    var body: some View {
        if supported.count > 1 {
            Button {
                isOpen.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: viewModel.activeComposerEffort.iconSystemName)
                        .font(.system(size: 11, weight: .medium))
                    Text(I18n.t(viewModel.activeComposerEffort.labelKey))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isOpen, arrowEdge: .top) {
                ThinkingEffortSliderPopover(viewModel: viewModel, tiers: supported)
            }
            .unifiedTooltip(UnifiedTooltipContent(
                title: I18n.t("composer.effort.tooltip"),
                detail: I18n.t(viewModel.activeComposerEffort.labelKey)
            ))
        }
    }
}

/// The popover body: title + a capsule slider whose highlighted segment tracks
/// the current tier and follows tap / drag.
private struct ThinkingEffortSliderPopover: View {
    @ObservedObject var viewModel: DashboardViewModel
    let tiers: [ThinkingEffort]

    private var currentIndex: Int {
        tiers.firstIndex(of: viewModel.activeComposerEffort) ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Text(I18n.t("composer.effort.tooltip"))
                    .font(.system(size: 13, weight: .semibold))
            }

            GeometryReader { geo in
                let segmentWidth = geo.size.width / CGFloat(max(tiers.count, 1))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))

                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: segmentWidth)
                        .offset(x: segmentWidth * CGFloat(currentIndex))
                        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: currentIndex)

                    HStack(spacing: 0) {
                        ForEach(tiers) { tier in
                            Text(I18n.t(tier.labelKey))
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .foregroundColor(tier == viewModel.activeComposerEffort ? .white : .secondary)
                                .frame(width: segmentWidth, height: 30)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let raw = Int((value.location.x / segmentWidth).rounded(.down))
                            let index = min(max(raw, 0), tiers.count - 1)
                            let tier = tiers[index]
                            if tier != viewModel.activeComposerEffort {
                                viewModel.activeComposerEffort = tier
                            }
                        }
                )
            }
            .frame(height: 30)

            Text(I18n.t(
                "composer.effort.desc.\(viewModel.activeComposerEffort.rawValue)",
                fallback: I18n.t(viewModel.activeComposerEffort.labelKey)
            ))
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(width: 280)
    }
}
