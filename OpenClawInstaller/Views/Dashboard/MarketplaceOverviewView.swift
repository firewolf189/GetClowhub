import SwiftUI

struct MarketplaceOverviewView: View {
    let onSelect: (MarketplaceAgent) -> Void

    @EnvironmentObject var languageManager: LanguageManager
    @State private var searchText = ""

    private static let divisionEmoji: [String: String] = [
        "Academic": "🎓",
        "Design": "🎨",
        "Engineering": "⚙️",
        "Game Development": "🎮",
        "Marketing": "📣",
        "Paid Media": "💰",
        "Product": "📦",
        "Project Management": "📋",
        "Sales": "🤝",
        "Spatial Computing": "🥽",
        "Specialized": "⭐",
        "Support": "🛟",
        "Testing": "🧪",
    ]

    private var groupedAgents: [(division: String, agents: [MarketplaceAgent])] {
        let catalog = MarketplaceCatalog.shared
        if searchText.isEmpty {
            return catalog.divisions.compactMap { div in
                let agents = catalog.search(query: "", division: div)
                guard !agents.isEmpty else { return nil }
                return (division: div, agents: agents)
            }
        } else {
            let filtered = catalog.search(query: searchText)
            guard !filtered.isEmpty else { return [] }
            // Group search results by division
            let grouped = Dictionary(grouping: filtered) { $0.division }
            return catalog.divisions.compactMap { div in
                guard let agents = grouped[div], !agents.isEmpty else { return nil }
                return (division: div, agents: agents)
            }
        }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(
                    String(localized: "Search agents...", bundle: languageManager.localizedBundle),
                    text: $searchText
                )
                .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // Content
            ScrollView {
                if groupedAgents.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text(String(localized: "No matching agents", bundle: languageManager.localizedBundle))
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(60)
                } else {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(groupedAgents, id: \.division) { group in
                            divisionSection(group)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Division Section

    private func divisionSection(_ group: (division: String, agents: [MarketplaceAgent])) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack(spacing: 6) {
                Text(Self.divisionEmoji[group.division] ?? "📁")
                    .font(.system(size: 16))
                Text(group.division)
                    .font(.system(size: 15, weight: .semibold))
                Text("(\(group.agents.count))")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .padding(.leading, 4)

            // Agent cards grid
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(group.agents) { agent in
                    AgentCard(agent: agent, onSelect: onSelect)
                }
            }
        }
    }
}

// MARK: - Agent Card

private struct AgentCard: View {
    let agent: MarketplaceAgent
    let onSelect: (MarketplaceAgent) -> Void

    @State private var isHovering = false
    @State private var isInstalled = false

    var body: some View {
        Button {
            onSelect(agent)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Top: emoji + name + status
                HStack(spacing: 8) {
                    Text(agent.emoji)
                        .font(.system(size: 28))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(agent.division)
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if isInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                    }
                }

                // Description
                Text(agent.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovering
                          ? Color(nsColor: .controlBackgroundColor)
                          : Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isHovering ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onAppear {
            checkInstalled()
        }
    }

    private func checkInstalled() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let agentId = agent.id
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let agentDir = "\(homeDir)/.openclaw/agents/\(agentId)/agent"
        isInstalled = FileManager.default.fileExists(atPath: agentDir)
    }
}
