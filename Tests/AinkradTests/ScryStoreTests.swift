import Foundation
import CoreGraphics
import Testing
@testable import Ainkrad
import AinkradHostRuntime

@Suite("ScryStore")
@MainActor
struct ScryStoreTests {
    private func store(_ p: PersistenceStore = InMemoryPersistenceStore(),
                       key: String = "s1") -> ScryStore {
        ScryStore(persistence: p, sessionKey: key)
    }

    @Test func addAssignsIDAndZ() {
        let s = store()
        let id = s.add(ScryElement(id: "", kind: .text, body: "hi"))
        #expect(!id.isEmpty)
        #expect(s.model.elements.count == 1)
        #expect(s.model.elements.first?.z == 0)   // first element z == nextZ(0)
    }

    @Test func updateMutatesInPlace() {
        let s = store()
        let id = s.add(ScryElement(id: "e1", kind: .table, body: "row1"))
        s.update(id: id) { $0.body += "\nrow2" }
        #expect(s.model.elements.first?.body == "row1\nrow2")
    }

    @Test func moveAndResizeUpdateRect() {
        let s = store()
        let id = s.add(ScryElement(id: "e1", kind: .card, body: ""))
        s.move(id: id, to: CGPoint(x: 100, y: 120))
        s.resize(id: id, to: CGSize(width: 500, height: 300))
        let r = s.model.elements.first!.rect
        #expect(r.x == 100 && r.y == 120 && r.width == 500 && r.height == 300)
    }

    @Test func bringToFrontRaisesZ() {
        let s = store()
        let a = s.add(ScryElement(id: "a", kind: .text, body: ""))
        let b = s.add(ScryElement(id: "b", kind: .text, body: ""))
        s.bringToFront(id: a)
        let za = s.model.elements.first { $0.id == a }!.z
        let zb = s.model.elements.first { $0.id == b }!.z
        #expect(za > zb)
    }

    @Test func sessionKeySwapOnLiveStoreIsolatesLayouts() {
        let p = InMemoryPersistenceStore()
        let s = store(p, key: "A")
        let idA = s.add(ScryElement(id: "a", kind: .card, body: "in-A"))
        s.move(id: idA, to: CGPoint(x: 10, y: 20))

        s.sessionKey = "B"
        #expect(s.model.elements.isEmpty)

        let idB = s.add(ScryElement(id: "b", kind: .text, body: "in-B"))
        #expect(s.model.elements.first?.id == idB)

        s.sessionKey = "A"
        #expect(s.model.elements.count == 1)
        let a = s.model.elements.first!
        #expect(a.id == idA)
        #expect(a.body == "in-A")
        #expect(a.rect.x == 10 && a.rect.y == 20)
        #expect(!s.model.elements.contains { $0.id == idB })
    }

    @Test func persistsPerSessionKey() {
        let p = InMemoryPersistenceStore()
        let s1 = store(p, key: "alpha")
        _ = s1.add(ScryElement(id: "e", kind: .text, body: "kept"))
        // A fresh store for the same session sees the persisted canvas.
        let s2 = store(p, key: "alpha")
        #expect(s2.model.elements.first?.body == "kept")
        // A different session starts empty.
        let s3 = store(p, key: "beta")
        #expect(s3.model.elements.isEmpty)
    }
}
