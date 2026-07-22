import Foundation
import Observation

@MainActor
@Observable
final class AssistantSessionStore {
    private(set) var sessions: [SavedSession] = []
    private(set) var activeID: UUID?

    private let persistence: PersistenceStore
    private let now: () -> Date

    init(persistence: PersistenceStore, now: @escaping () -> Date = Date.init) {
        self.persistence = persistence
        self.now = now
        let doc = persistence.load(AssistantSessionsDocument.self) ?? AssistantSessionsDocument()
        sessions = doc.sessions.sorted { $0.updatedAt > $1.updatedAt }
        activeID = doc.activeID ?? sessions.first?.id
        if sessions.isEmpty { seedActive() }
    }

    func syncActive(messages: [AgentMessage]) {
        guard let id = activeID, let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].messages = messages
        sessions[idx].title = Self.title(from: messages)
        sessions[idx].updatedAt = now()
        resort(); save()
    }

    func startNewSession() {
        let session = SavedSession(createdAt: now(), updatedAt: now())
        sessions.insert(session, at: 0)
        activeID = session.id
        resort(); save()
    }

    @discardableResult
    func activate(_ id: UUID) -> [AgentMessage] {
        activeID = id; save()
        return sessions.first(where: { $0.id == id })?.messages ?? []
    }

    func delete(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if activeID == id { activeID = sessions.first?.id }
        if sessions.isEmpty { seedActive() } else { save() }
    }

    /// Messages of the currently-active session — used at launch to restore the
    /// live AgentSession so the first edit doesn't clobber the saved transcript.
    var activeMessages: [AgentMessage] {
        sessions.first(where: { $0.id == activeID })?.messages ?? []
    }

    func results(for query: String) -> [SavedSession] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return sessions }
        return sessions.filter { s in
            s.title.lowercased().contains(q)
                || s.messages.contains { $0.text.lowercased().contains(q) }
        }
    }

    // MARK: - Private

    private func seedActive() {
        let session = SavedSession(createdAt: now(), updatedAt: now())
        sessions = [session]; activeID = session.id; save()
    }

    private func resort() { sessions.sort { $0.updatedAt > $1.updatedAt } }

    private func save() {
        persistence.save(AssistantSessionsDocument(sessions: sessions, activeID: activeID))
    }

    private static func title(from messages: [AgentMessage]) -> String {
        let first = messages.first { $0.role == .user }?.text
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !first.isEmpty else { return "New chat" }
        return String(first.prefix(40))
    }
}
