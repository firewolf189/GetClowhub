import Foundation

protocol ChatSessionSearchable {
    var title: String { get }
    var updatedAt: Date { get }
    var isPinned: Bool { get }
    var isArchived: Bool { get }
}

/// Cursor-style history filter: the default list is active chats, with an
/// explicit archived view and an optional combined list.
enum ChatSessionListFilter: String, CaseIterable, Codable, Sendable {
    case active
    case archived
    case all

    func includes(isArchived: Bool) -> Bool {
        switch self {
        case .active: return !isArchived
        case .archived: return isArchived
        case .all: return true
        }
    }

    var titleKey: String {
        switch self {
        case .active: return "dashboard.session.filter.active"
        case .archived: return "dashboard.session.filter.archived"
        case .all: return "dashboard.session.filter.all"
        }
    }

    var emptyCopyKey: String {
        switch self {
        case .active: return "dashboard.session.empty.active"
        case .archived: return "dashboard.session.empty.archived"
        case .all: return "dashboard.session.empty.all"
        }
    }
}

enum ChatSessionSearch {
    static func search<Session: ChatSessionSearchable>(
        _ sessions: [Session],
        query: String,
        includeArchived: Bool = false,
        filter: ChatSessionListFilter = .active
    ) -> [Session] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveFilter: ChatSessionListFilter = includeArchived ? .all : filter
        return sessions
            .filter { effectiveFilter.includes(isArchived: $0.isArchived) }
            .filter { meta in
                trimmed.isEmpty || meta.title.localizedCaseInsensitiveContains(trimmed)
            }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return lhs.updatedAt > rhs.updatedAt
            }
    }
}
