import SwiftUI

/// Top-of-response working status. Expansion stays local to the bubble so it
/// participates in normal SwiftUI layout without driving chat scroll state.
struct WorkStatusHeader: View {
    private static let expansionAnimation = Animation.spring(response: 0.28, dampingFraction: 0.86)

    let start: Date?
    let end: Date?
    let activityEvents: [ChatActivityEvent]
    @State private var isExpanded = false

    var body: some View {
        Group {
            if let start = start {
                if let end = end {
                    statusBody {
                        Text(WorkStatusDurationText.status(
                            elapsedSeconds: max(0, Int(end.timeIntervalSince(start))),
                            isFinished: true
                        ))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    }
                } else {
                    statusBody {
                        IsolatedElapsedWorkStatusText(start: start)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    headerButton {
                        Text(String(localized: "Working", bundle: LanguageManager.shared.localizedBundle))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    if isExpanded {
                        activityRows
                    }
                }
                .clipped()
            }
        }
        .animation(Self.expansionAnimation, value: isExpanded)
    }

    private func statusBody<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            headerButton {
                label()
            }
            if isExpanded {
                activityRows
            }
            Divider()
        }
        .clipped()
    }

    private var activityRows: some View {
        ActivitySummaryRows(events: activityEvents)
            .transition(.move(edge: .top).combined(with: .opacity))
            .clipped()
    }

    private func headerButton<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Button {
            withAnimation(Self.expansionAnimation) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                label()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.75))
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .animation(Self.expansionAnimation, value: isExpanded)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private enum WorkStatusDurationText {
    static func status(elapsedSeconds: Int, isFinished: Bool) -> String {
        let key = isFinished ? "Worked for %@" : "Working for %@"
        return String(
            format: String(localized: String.LocalizationValue(key), bundle: LanguageManager.shared.localizedBundle),
            localizedDuration(elapsedSeconds)
        )
    }

    private static func localizedDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes > 0 {
            return String(
                format: String(localized: "%lldm %llds", bundle: LanguageManager.shared.localizedBundle),
                Int64(minutes),
                Int64(remainingSeconds)
            )
        }
        return String(
            format: String(localized: "%llds", bundle: LanguageManager.shared.localizedBundle),
            Int64(remainingSeconds)
        )
    }
}

private struct IsolatedElapsedWorkStatusText: View {
    private static let reservedWidth: CGFloat = 156

    let start: Date

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { ctx in
            ShimmeringStatusText(
                text: WorkStatusDurationText.status(
                    elapsedSeconds: max(0, Int(ctx.date.timeIntervalSince(start))),
                    isFinished: false
                ),
                font: .system(size: 13, weight: .medium)
            )
            .monospacedDigit()
            .lineLimit(1)
            .frame(width: Self.reservedWidth, alignment: .leading)
        }
    }
}

private struct ActivitySummaryRows: View {
    private static let detailAnimation = Animation.spring(response: 0.24, dampingFraction: 0.86)

    let events: [ChatActivityEvent]
    @State private var expandedDetailKeys: Set<String> = []

    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(events) { event in
                    if event.kind == .progressUpdate {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(event.details.enumerated()), id: \.offset) { _, detail in
                                Text(detail)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else {
                        ActivitySummaryRow(
                            event: event,
                            expandedDetailKeys: $expandedDetailKeys,
                            animation: Self.detailAnimation
                        )
                    }
                }
            }
        }
    }
}

private struct ActivitySummaryRow: View {
    let event: ChatActivityEvent
    @Binding var expandedDetailKeys: Set<String>
    let animation: Animation

    private var disclosureKey: String { event.kind.rawValue }
    private var hasDetails: Bool { !event.details.isEmpty }
    private var isExpanded: Bool { expandedDetailKeys.contains(disclosureKey) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if hasDetails {
                Button {
                    toggleDetails()
                } label: {
                    header
                }
                .buttonStyle(.plain)
            } else {
                header
            }

            if hasDetails && isExpanded {
                detailRows
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .foregroundColor(.secondary.opacity(0.72))
        .clipped()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: event.kind.systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 14)
            Text(event.kind.title(count: event.count))
                .font(.system(size: 13, weight: .regular))
                .lineLimit(1)
            if hasDetails {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .opacity(0.75)
            }
        }
        .contentShape(Rectangle())
    }

    private var detailRows: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(event.details.enumerated()), id: \.offset) { _, detail in
                Text(detail)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .lineLimit(nil)
                    .textSelection(.enabled)
            }
        }
        .padding(.leading, 22)
        .foregroundColor(.secondary.opacity(0.66))
        .clipped()
    }

    private func toggleDetails() {
        withAnimation(animation) {
            if isExpanded {
                expandedDetailKeys.remove(disclosureKey)
            } else {
                expandedDetailKeys.insert(disclosureKey)
            }
        }
    }
}
