import Testing
import Foundation
@testable import Ainkrad
@testable import AinkradHostRuntime

/// Migration tests for the v0.16.0 app rename. Each seeds a schema-v1 envelope
/// on disk — the shape a shipped v0.15.0 build leaves behind — then loads it
/// through the real store and asserts the user's state arrived under the new id.
@Suite("App id migrations")
struct AppIDMigrationTests {
    private func seedV1(_ documentID: String, payload: [String: Any], in dir: URL) throws {
        let envelope: [String: Any] = [
            "schemaVersion": 1,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "payload": payload,
        ]
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: envelope)
        try data.write(to: dir.appendingPathComponent("\(documentID).json"))
    }

    @Test("appearance entries carry the user's opacity and blur onto the new id")
    func migratesAppearance() throws {
        let dir = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try seedV1("app-appearance", payload: [
            "entries": [
                "assistant": ["surfaceOpacity": 0.6, "blurEnabled": true],
                "gitmage": ["surfaceOpacity": 0.9, "blurEnabled": false],
            ],
        ], in: dir)

        let store = FileDocumentStore(rootURL: dir)
        let doc = try #require(store.load(AppAppearanceDocument.self))

        #expect(doc.entries["sage"]?.surfaceOpacity == 0.6)
        #expect(doc.entries["sage"]?.blurEnabled == true)
        #expect(doc.entries["assistant"] == nil)
        #expect(doc.entries["gitmage"]?.surfaceOpacity == 0.9)
    }

    @Test("a disabled app stays disabled under its new id")
    func migratesRegistryState() throws {
        let dir = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try seedV1("registry-enabled-state", payload: [
            "enabled": ["files": false, "leyline": true],
        ], in: dir)

        let store = FileDocumentStore(rootURL: dir)
        let doc = try #require(store.load(RegistryStateDocument.self))

        #expect(doc.enabled["hoard"] == false)
        #expect(doc.enabled["files"] == nil)
        #expect(doc.enabled["leyline"] == true)
    }
}
