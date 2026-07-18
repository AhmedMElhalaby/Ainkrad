import Foundation
import Testing
@testable import Ainkrad

@Suite("UserProfile")
@MainActor
struct UserProfileTests {
    private func make() -> (UserProfileStore, MemoryStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("up-\(UUID().uuidString)")
        let mem = MemoryStore(paths: MemoryPaths(root: root))
        let store = UserProfileStore(persistence: InMemoryPersistenceStore(), memory: mem)
        return (store, mem, root)
    }

    @Test func setPersistsAndProjectsToUserMd() {
        let (store, mem, root) = make(); defer { try? FileManager.default.removeItem(at: root) }
        store.set("automotiveai", for: "employer")
        #expect(store.all()["employer"] == "automotiveai")
        #expect(mem.read(.user).contains("employer: automotiveai"))
    }
}
