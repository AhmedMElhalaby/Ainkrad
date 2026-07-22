import Testing
import Foundation
@testable import Ainkrad

@Suite struct AssistantSessionsDocumentTests {
    @Test func roundTripsThroughPersistence() throws {
        let store = InMemoryPersistenceStore()
        let fixed = Date(timeIntervalSince1970: 1_000)
        let session = SavedSession(id: UUID(), title: "Hi", createdAt: fixed,
                                   updatedAt: fixed, messages: [AgentMessage(role: .user, text: "hi")])
        store.save(AssistantSessionsDocument(sessions: [session], activeID: session.id))
        let loaded = store.load(AssistantSessionsDocument.self)
        #expect(loaded?.sessions == [session])
        #expect(loaded?.activeID == session.id)
    }

    @Test func defaultsMissingFields() {
        let doc = AssistantSessionsDocument()
        #expect(doc.sessions.isEmpty)
        #expect(doc.activeID == nil)
    }
}
