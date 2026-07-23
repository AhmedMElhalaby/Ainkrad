import Foundation
import Testing
@testable import Ainkrad

@Suite("CanvasElement")
struct CanvasElementTests {
    @Test func roundTripsCodable() throws {
        let e = CanvasElement(id: "a", kind: .markdown, title: "T", body: "# hi",
                              rect: .defaultCard, z: 3)
        let data = try JSONEncoder().encode(e)
        #expect(try JSONDecoder().decode(CanvasElement.self, from: data) == e)
    }

    @Test func unknownKindDecodesToPlaceholder() throws {
        let json = #"{"id":"x","kind":"hologram","body":"","rect":{"x":0,"y":0,"width":10,"height":10},"z":0,"pinned":false}"#
        let e = try JSONDecoder().decode(CanvasElement.self, from: Data(json.utf8))
        #expect(e.kind == .unknown)
    }

    @Test func upsertReplacesByID() {
        var m = CanvasModel()
        m.upsert(CanvasElement(id: "a", kind: .text, body: "one", rect: .defaultCard, z: 0))
        m.upsert(CanvasElement(id: "a", kind: .text, body: "two", rect: .defaultCard, z: 0))
        #expect(m.elements.count == 1)
        #expect(m.elements.first?.body == "two")
    }

    @Test func orderedSortsByZ() {
        var m = CanvasModel()
        m.upsert(CanvasElement(id: "a", kind: .text, body: "", rect: .defaultCard, z: 5))
        m.upsert(CanvasElement(id: "b", kind: .text, body: "", rect: .defaultCard, z: 1))
        #expect(m.ordered.map(\.id) == ["b", "a"])
    }

    @Test func removeDropsElement() {
        var m = CanvasModel()
        m.upsert(CanvasElement(id: "a", kind: .text, body: "", rect: .defaultCard, z: 0))
        m.remove(id: "a")
        #expect(m.elements.isEmpty)
    }

    @Test func documentIDIsStable() {
        #expect(CanvasWorkspaceDocument.documentID == "agent-canvas")
    }
}
