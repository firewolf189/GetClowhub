import SwiftUI

struct SettingsShellView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var selectedSection: SettingsPageSection
    let onBackToApp: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            SettingsSectionSidebar(selectedSection: $selectedSection, onBackToApp: onBackToApp)
                .frame(width: 250)

            Divider()

            ConfigTabView(
                viewModel: viewModel,
                selectedSection: $selectedSection
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct SettingsSectionSidebar: View {
    @Binding var selectedSection: SettingsPageSection
    let onBackToApp: () -> Void
    @State private var searchText = ""

    private let groups: [(key: String, sections: [SettingsPageSection])] = [
        ("settings.group.account", [.profile, .preferences, .persona]),
        ("settings.group.system", [.status]),
        ("settings.group.configuration", [.gateway, .provider, .budget]),
        ("settings.group.advanced", [.models, .channels, .logs])
    ]

    private var filteredGroups: [(key: String, sections: [SettingsPageSection])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return groups }
        return groups.compactMap { group in
            let groupTitle = I18n.t(group.key).lowercased()
            let filteredSections = group.sections.filter {
                $0.localizedTitle().lowercased().contains(query)
            }
            if groupTitle.contains(query) {
                return group
            }
            return filteredSections.isEmpty ? nil : (group.key, filteredSections)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onBackToApp) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left")
                        .frame(width: 16)
                    Text(I18n.t("settings.shell.backToApp"))
                    Spacer()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 20)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(I18n.t("settings.shell.searchPlaceholder"), text: $searchText)
                    .textFieldStyle(.plain)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.textBackgroundColor).opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 12)

            SmoothScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(filteredGroups, id: \.key) { group in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(I18n.t(group.key))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 14)

                            ForEach(group.sections) { section in
                                SettingsSectionRow(
                                    section: section,
                                    isSelected: selectedSection == section
                                ) {
                                    selectedSection = section
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 18)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.42))
    }
}

private struct SettingsSectionRow: View {
    let section: SettingsPageSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: section.systemImage)
                    .frame(width: 16)
                Text(section.localizedTitle())
                Spacer()
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension SettingsShellView {
    var selectedSectionTitle: String {
        selectedSection.localizedTitle()
    }
}
