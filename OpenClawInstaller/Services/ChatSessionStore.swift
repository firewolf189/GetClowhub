import Combine
import Foundation
import os.log

/// Local-only chat session persistence.
///
/// Layout:
///   ~/Library/Application Support/<bundleID>/chat-sessions/
///     ├── index.json                    # all metadata, loaded eagerly
///     └── <sessionId>.json              # full ChatSession including messages, loaded on demand
///
/// Why split: the index is small and read once on launch; per-session files
/// can grow large with months of history, so we don't want to deserialize
/// every thread just to render the sidebar list.
@MainActor
final class ChatSessionStore: ObservableObject {
    private let log = Logger(subsystem: "com.openclaw.installer", category: "ChatSessionStore")

    private let baseDir: URL
    private let indexURL: URL

    /// Cached metadata for every persisted session, sorted only on read.
    @Published private(set) var index: [ChatSessionMetadata] = []

    /// In-flight debounced save tasks, keyed by session id, so rapid writes
    /// to the same session collapse into one disk write.
    private var saveDebouncers: [UUID: Task<Void, Never>] = [:]

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let bundleId = Bundle.main.bundleIdentifier ?? "com.cc.OpenClawInstaller"
        self.baseDir = appSupport
            .appendingPathComponent(bundleId)
            .appendingPathComponent("chat-sessions")
        self.indexURL = baseDir.appendingPathComponent("index.json")

        try? FileManager.default.createDirectory(
            at: baseDir,
            withIntermediateDirectories: true
        )
        loadIndex()
    }

    // MARK: - Index I/O

    func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL) else {
            index = []
            return
        }
        do {
            index = try Self.decoder().decode([ChatSessionMetadata].self, from: data)
        } catch {
            log.error("Failed to decode index.json: \(error.localizedDescription, privacy: .public)")
            index = []
        }
    }

    private func writeIndex() {
        do {
            let data = try Self.encoder().encode(index)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            log.error("Failed to write index.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Session I/O

    /// Read a session's full content (including all messages) from disk.
    /// Returns nil if the file is missing or corrupt.
    func loadSession(id: UUID) -> ChatSession? {
        let url = sessionURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try Self.decoder().decode(ChatSession.self, from: data)
        } catch {
            log.error("Failed to decode session \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Persist a session immediately. Updates `index` in place so the UI
    /// reflects the new metadata (title, message count, …) right away.
    func saveSession(_ session: ChatSession) {
        let url = sessionURL(for: session.id)
        do {
            let data = try Self.encoder().encode(session)
            try data.write(to: url, options: .atomic)

            let meta = ChatSessionMetadata(from: session)
            if let idx = index.firstIndex(where: { $0.id == session.id }) {
                index[idx] = meta
            } else {
                index.append(meta)
            }
            writeIndex()
        } catch {
            log.error("Failed to save session \(session.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Defers the actual disk write by `delay` so a burst of streamed deltas
    /// (e.g. token-by-token assistant output) collapses into a single write.
    func saveSessionDebounced(_ session: ChatSession, delay: TimeInterval = 0.5) {
        saveDebouncers[session.id]?.cancel()
        saveDebouncers[session.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.saveSession(session)
        }
    }

    /// Force any pending debounced writes for a session to land synchronously.
    /// Useful before app shutdown or when switching active session.
    func flush(id: UUID, current: ChatSession?) {
        saveDebouncers[id]?.cancel()
        saveDebouncers[id] = nil
        if let s = current { saveSession(s) }
    }

    func deleteSession(id: UUID) {
        saveDebouncers[id]?.cancel()
        saveDebouncers[id] = nil
        try? FileManager.default.removeItem(at: sessionURL(for: id))
        index.removeAll { $0.id == id }
        writeIndex()
    }

    // MARK: - Queries

    /// Sessions for one agent, pinned first then newest first. Hides archived
    /// sessions unless `includeArchived` is true.
    func sessions(forAgent agentId: String, includeArchived: Bool = false) -> [ChatSessionMetadata] {
        index
            .filter { $0.agentId == agentId && (includeArchived || !$0.isArchived) }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    // MARK: - Helpers

    private func sessionURL(for id: UUID) -> URL {
        baseDir.appendingPathComponent("\(id.uuidString).json")
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
