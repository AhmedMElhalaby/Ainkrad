import Foundation
import Testing
@testable import Ainkrad

@Suite("MemoryConsolidator")
@MainActor
struct MemoryConsolidatorTests {
    private func service() throws -> (MemoryService, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("con-\(UUID().uuidString)")
        return (try MemoryService(paths: MemoryPaths(root: root), persistence: InMemoryPersistenceStore()), root)
    }

    @Test func dedupesDuplicateLinesAndLogsIt() throws {
        let (svc, root) = try service(); defer { try? FileManager.default.removeItem(at: root) }
        svc.store.write("a\nb\na\nc\nb", to: .memory)
        MemoryConsolidator.consolidate(svc)
        #expect(svc.store.read(.memory) == "a\nb\nc")
        #expect(svc.log.entries().first?.provenance == .consolidation)
    }

    @Test func noOpWhenNothingToConsolidate() throws {
        let (svc, root) = try service(); defer { try? FileManager.default.removeItem(at: root) }
        svc.store.write("a\nb\nc", to: .memory)
        MemoryConsolidator.consolidate(svc)
        #expect(svc.store.read(.memory) == "a\nb\nc")
        #expect(svc.log.entries().isEmpty)   // unchanged content → no write, no log churn
    }
}
