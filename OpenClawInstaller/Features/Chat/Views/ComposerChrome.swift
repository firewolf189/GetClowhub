import SwiftUI
import SwiftTerm
import UniformTypeIdentifiers
import AVKit
import Combine
import Quartz
import AppKit
import WebKit
import os.log

// Split from DashboardView.swift — file move only, no behavior change.

struct ComposerInputCardBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct ComposerSelectorButtonBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct ComposerModelSelector: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var isOpen: Bool

    private var modelLabel: String {
        let raw = viewModel.activeComposerModel
        let resolved = raw.isEmpty ? viewModel.modelOverview.defaultModel : raw
        let cleaned = stripProviderPrefix(resolved)
        return cleaned.isEmpty || cleaned == "-" ? "Model" : cleaned
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isOpen.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cube")
                    .font(.system(size: 12, weight: .medium))

                Text(modelLabel)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("dashboard.tooltip.chooseModel"), detail: modelLabel))
        .anchorPreference(key: ComposerSelectorButtonBoundsKey.self, value: .bounds) { anchor in
            isOpen ? anchor : nil
        }
    }
}

struct ComposerModelPanel: View {
    let modelGroups: [ProviderModelGroup]
    let currentModel: String
    let defaultModel: String
    @Binding var isOpen: Bool
    let onSelectModel: (String) -> Void

    private static let maxModelPanelHeight: CGFloat = 420

    private var allModelIds: Set<String> {
        Set(modelGroups.flatMap { $0.models.map(\.runtimeId) })
    }

    private var effectiveSelectedModel: String {
        currentModel.isEmpty ? defaultModel : currentModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(I18n.t("dashboard.model.label"))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 10)

            ScrollView(showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if !effectiveSelectedModel.isEmpty
                        && effectiveSelectedModel != "-"
                        && !allModelIds.contains(effectiveSelectedModel) {
                        Button {
                            selectModel(effectiveSelectedModel)
                        } label: {
                            selectorRow(
                                title: stripProviderPrefix(effectiveSelectedModel),
                                subtitle: nil,
                                selected: true,
                                showsDisclosure: false
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(modelGroups) { group in
                        if !group.models.isEmpty {
                            sectionHeader(for: group)

                            ForEach(group.models) { model in
                                Button {
                                    selectModel(model.runtimeId)
                                } label: {
                                    selectorRow(
                                        title: stripProviderPrefix(model.name),
                                        subtitle: nil,
                                        selected: model.runtimeId == effectiveSelectedModel,
                                        showsDisclosure: false
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 300)
        .frame(maxHeight: Self.maxModelPanelHeight)
        .panelChrome(cornerRadius: 22)
    }

    private func sectionHeader(for group: ProviderModelGroup) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider()
                .opacity(0.55)
                .padding(.top, 6)
            HStack(spacing: 7) {
                Image(systemName: group.providerKey == "getclawhub" ? "cloud" : "slider.horizontal.3")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(group.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(group.models.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.8))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private func selectorRow(
        title: String,
        subtitle: String?,
        selected: Bool,
        showsDisclosure: Bool
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.secondary)
            }
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: subtitle == nil ? 44 : 52)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.secondary.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private func selectModel(_ model: String) {
        withAnimation(.easeInOut(duration: 0.16)) {
            onSelectModel(model)
            isOpen = false
        }
    }
}

private extension View {
    func panelChrome(cornerRadius: CGFloat) -> some View {
        self
            .padding(6)
            .background(Color(NSColor.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
    }
}

private func stripProviderPrefix(_ s: String) -> String {
    if let slash = s.lastIndex(of: "/") {
        return String(s[s.index(after: slash)...])
    }
    return s
}

// MARK: - Chat Welcome View

struct ChatWelcomeView: View {
    var body: some View {
        VStack {
            Spacer()
            Text(String(localized: "What should we build today?", bundle: LanguageManager.shared.localizedBundle))
                .font(.system(size: 26, weight: .regular))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Background Task Notification

struct BackgroundTaskNotification: View {
    let message: ChatMessageRowModel
    let scrollProxy: ScrollViewProxy

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 6) {
                Text(message.content)
                    .font(.callout)

                Button(action: {
                    if let targetId = message.scrollTargetId {
                        withAnimation {
                            scrollProxy.scrollTo(targetId, anchor: .top)
                        }
                    }
                }) {
                    Text(I18n.t("dashboard.chat.viewResult"))
                        .font(.callout)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.08))
            .cornerRadius(12)

            Spacer(minLength: 60)
        }
    }
}

// MARK: - Thinking Indicator

struct ThinkingIndicator: View, Equatable {
    let message: ChatLoadingRowModel
    let onRetryConnection: (UUID) -> Void

    static func == (lhs: ThinkingIndicator, rhs: ThinkingIndicator) -> Bool {
        lhs.message == rhs.message
    }

    var body: some View {
        WorkStatusHeader(
            start: message.timestamp,
            end: nil,
            activityEvents: message.activityEvents,
            runState: message.runState,
            onRetry: { onRetryConnection(message.id) }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Model Picker Row (right-sidebar SessionDetailsPanel)

/// Extracted into its own view so we can use the working
/// `@State + .onChange(of:)` pattern (mirrors `SubAgentsTabView`'s model
/// picker, which actually works). The previous inline `Binding(get:set:)`
/// in `SessionDetailsPanel.modelRow` looked correct but the picker's
/// selection often failed to fire `set:` in SwiftUI on macOS — net
/// result: dropdown opens, user picks an option, nothing happens.
///
/// Source-of-truth flow:
///   - external: `viewModel.availableAgents[i].model` (raw, "" means inherit)
///   - `@State selection`: kept in sync with external via `.onAppear` and
///     `.onChange(of: currentRawModel)`
///   - user picks → `.onChange(of: selection)` fires →
///     `viewModel.updateAgentModel(model:)` writes to disk → reload →
///     `currentRawModel` flips → external observer syncs `selection`.
struct ModelPickerRow: View {
    @ObservedObject var viewModel: DashboardViewModel
    let currentRawModel: String
    let resolvedDefaultModel: String

    @State private var selection: String = ""

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "cube.fill")
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
            Picker("", selection: $selection) {
                if resolvedDefaultModel.isEmpty {
                    Text(I18n.t("dashboard.model.defaultInherit")).tag("")
                } else {
                    Text(I18n.format("dashboard.model.defaultWithValue", resolvedDefaultModel)).tag("")
                }
                // Always include the currently-set model so the Picker
                // can render the active selection even if the available
                // list hasn't loaded yet or doesn't contain that id.
                if !currentRawModel.isEmpty
                   && !viewModel.availableModelsForSettings.contains(where: { $0.id == currentRawModel }) {
                    Text(SessionDetailsPanel.stripProviderPrefix(currentRawModel))
                        .tag(currentRawModel)
                }
                ForEach(viewModel.availableModelsForSettings) { m in
                    Text(SessionDetailsPanel.stripProviderPrefix(m.name)).tag(m.id)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .onAppear { selection = currentRawModel }
        .onChange(of: currentRawModel) { newRaw in
            // External truth changed (agent switched, or another panel
            // wrote a different model). Sync our local @State.
            if selection != newRaw {
                selection = newRaw
            }
        }
        .onChange(of: selection) { newValue in
            // User picked something. Only write through when it differs
            // from the external raw — same guard as before, but now the
            // .onChange contract guarantees this fires even with
            // identity-shaped equality, unlike the manual Binding pattern.
            if newValue != currentRawModel {
                viewModel.updateAgentModel(model: newValue)
            }
        }
    }
}

struct PendingComposerQueueView: View {
    let messages: [PendingComposerMessage]
    let onSend: (PendingComposerMessage) -> Void
    let onEdit: (PendingComposerMessage) -> Void
    let onDelete: (PendingComposerMessage) -> Void

    var body: some View {
        VStack(spacing: 6) {
            ForEach(messages) { message in
                HStack(spacing: 8) {
                    Text(message.text.isEmpty ? attachmentSummary(for: message) : message.text)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !message.attachments.isEmpty {
                        Text("\(message.attachments.count)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }

                    MessageActionIcon(
                        systemName: "paperplane",
                        tint: .secondary,
                        help: "发送这条",
                        action: { onSend(message) }
                    )

                    MessageActionIcon(
                        systemName: "pencil",
                        tint: .secondary,
                        help: "编辑待发送内容",
                        action: { onEdit(message) }
                    )

                    MessageActionIcon(
                        systemName: "xmark",
                        tint: .secondary,
                        help: "删除待发送内容",
                        action: { onDelete(message) }
                    )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func attachmentSummary(for message: PendingComposerMessage) -> String {
        message.attachments.count == 1 ? "1 个附件" : "\(message.attachments.count) 个附件"
    }
}

