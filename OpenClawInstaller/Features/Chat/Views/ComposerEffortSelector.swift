import SwiftUI

/// Composer control for per-request reasoning effort, styled after Claude's
/// thinking-effort interaction (and the Windows client): a compact badge that
/// opens a popover with a **draggable** capsule slider over the model's
/// supported tiers.
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

/// Popover body: title + a draggable slider whose thumb follows the cursor and
/// snaps to the nearest tier, + tier labels and the current tier's description.
private struct ThinkingEffortSliderPopover: View {
    @ObservedObject var viewModel: DashboardViewModel
    let tiers: [ThinkingEffort]
    /// Live thumb x while dragging (nil = resting on the selected tier).
    @State private var dragX: CGFloat?

    private var currentIndex: Int {
        tiers.firstIndex(of: viewModel.activeComposerEffort) ?? 0
    }

    private let thumbSize: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Text(I18n.t("composer.effort.tooltip"))
                    .font(.system(size: 13, weight: .semibold))
            }

            slider

            HStack(spacing: 0) {
                ForEach(tiers) { tier in
                    Text(I18n.t(tier.labelKey))
                        .font(.system(size: 10, weight: tier == viewModel.activeComposerEffort ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundColor(tier == viewModel.activeComposerEffort ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            Text(I18n.t(
                "composer.effort.desc.\(viewModel.activeComposerEffort.rawValue)",
                fallback: I18n.t(viewModel.activeComposerEffort.labelKey)
            ))
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(width: 300)
    }

    private var slider: some View {
        GeometryReader { geo in
            let count = max(tiers.count, 1)
            let cellWidth = geo.size.width / CGFloat(count)
            let stopX: (Int) -> CGFloat = { cellWidth * (CGFloat($0) + 0.5) }
            let thumbX = dragX ?? stopX(currentIndex)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 4)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(thumbX, 4), height: 4)

                ForEach(Array(tiers.indices), id: \.self) { index in
                    Circle()
                        .fill(index <= currentIndex ? Color.accentColor : Color.primary.opacity(0.28))
                        .frame(width: 5, height: 5)
                        .offset(x: stopX(index) - 2.5)
                }

                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 2.5))
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.18), radius: 2.5, y: 1)
                    .offset(x: thumbX - thumbSize / 2)
                    .animation(dragX == nil ? .spring(response: 0.26, dampingFraction: 0.8) : nil, value: thumbX)
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragX = min(max(value.location.x, thumbSize / 2), geo.size.width - thumbSize / 2)
                        let index = min(max(Int(value.location.x / cellWidth), 0), count - 1)
                        if tiers[index] != viewModel.activeComposerEffort {
                            viewModel.activeComposerEffort = tiers[index]
                        }
                    }
                    .onEnded { _ in dragX = nil }
            )
        }
        .frame(height: thumbSize)
    }
}
