import Testing
import Foundation
@testable import Ainkrad

@Suite("Connection migration")
struct ConnectionMigrationTests {
    private func decode(_ json: String) throws -> Connection {
        try JSONDecoder().decode(Connection.self, from: Data(json.utf8))
    }

    @Test("legacy openai connection migrates to OpenAI-compatible preset")
    func legacyOpenAI() throws {
        let c = try decode("""
        {"id":"\(UUID().uuidString)","provider":"openai","displayName":"OpenAI Key","createdAt":0}
        """)
        #expect(c.presetID == "openai")
        #expect(c.kind == .openAICompatible)
        #expect(c.baseURL == "https://api.openai.com/v1")
    }

    @Test("legacy claude connection migrates to claude preset")
    func legacyClaude() throws {
        let c = try decode("""
        {"id":"\(UUID().uuidString)","provider":"claude","displayName":"Claude Key","createdAt":0}
        """)
        #expect(c.presetID == "claude")
        #expect(c.kind == .claude)
    }

    @Test("new-format connection decodes as-is")
    func newFormat() throws {
        let c = try decode("""
        {"id":"\(UUID().uuidString)","presetID":"groq","kind":"openAICompatible","displayName":"Groq","baseURL":"https://api.groq.com/openai/v1","createdAt":0}
        """)
        #expect(c.presetID == "groq")
        #expect(c.baseURL == "https://api.groq.com/openai/v1")
    }
}
