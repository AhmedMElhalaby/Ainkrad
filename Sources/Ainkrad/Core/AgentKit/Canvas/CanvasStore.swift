import Foundation
import CoreGraphics
import Observation

/// Observable CRUD + geometry store for the agent canvas, one `CanvasModel`
/// per `sessionKey`. Every mutation round-trips through `persistence.save`
/// so the active canvas survives relaunch and session switches persist
/// independently (switching `sessionKey` swaps the active canvas; each
/// session's layout is kept in `document.canvases[sessionKey]`).
@MainActor
@Observable
final class CanvasStore {
    private let persistence: PersistenceStore
    private var document: CanvasWorkspaceDocument

    var sessionKey: String

    init(persistence: PersistenceStore, sessionKey: String = "default") {
        self.persistence = persistence
        self.sessionKey = sessionKey
        self.document = persistence.load(CanvasWorkspaceDocument.self) ?? CanvasWorkspaceDocument()
    }

    /// The active session's canvas. Live-observable so `CanvasView` redraws.
    var model: CanvasModel {
        document.canvases[sessionKey] ?? CanvasModel()
    }

    @discardableResult
    func add(_ element: CanvasElement) -> String {
        var m = model
        var e = element
        if e.id.isEmpty { e = copy(e, id: UUID().uuidString) }
        if e.z == 0 { e.z = m.nextZ }
        m.upsert(e)
        commit(m)
        return e.id
    }

    /// Add-or-replace by id, unconditionally — unlike `update(id:mutate:)` this
    /// never guards on the id already existing. Used where the caller has
    /// already computed the full resulting element (e.g. `CanvasRenderTool`,
    /// which must match `CanvasReconstruction.apply`'s create-or-merge
    /// semantics so a live render and a transcript replay never diverge).
    func upsert(_ element: CanvasElement) {
        var m = model
        m.upsert(element)
        commit(m)
    }

    func update(id: String, mutate: (inout CanvasElement) -> Void) {
        var m = model
        guard var e = m.elements.first(where: { $0.id == id }) else { return }
        mutate(&e)
        m.upsert(e)
        commit(m)
    }

    func remove(id: String) {
        var m = model
        m.remove(id: id)
        commit(m)
    }

    func move(id: String, to point: CGPoint) {
        update(id: id) { $0.rect.x = Double(point.x); $0.rect.y = Double(point.y) }
    }

    func resize(id: String, to size: CGSize) {
        update(id: id) { $0.rect.width = Double(size.width); $0.rect.height = Double(size.height) }
    }

    func bringToFront(id: String) {
        let top = model.nextZ
        update(id: id) { $0.z = top }
    }

    func setPinned(id: String, _ pinned: Bool) {
        update(id: id) { $0.pinned = pinned }
    }

    func clear() {
        commit(CanvasModel())
    }

    // MARK: - helpers

    private func commit(_ m: CanvasModel) {
        document.canvases[sessionKey] = m
        persistence.save(document)
    }

    private func copy(_ e: CanvasElement, id: String) -> CanvasElement {
        CanvasElement(id: id, kind: e.kind, title: e.title, body: e.body,
                      language: e.language, rect: e.rect, z: e.z, pinned: e.pinned)
    }
}
