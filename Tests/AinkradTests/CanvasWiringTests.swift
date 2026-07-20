import Foundation
import Testing
@testable import Ainkrad

@Suite("Canvas wiring")
@MainActor
struct CanvasWiringTests {
    @Test func canvasAppHasStableID() {
        #expect(CanvasApp.id == "canvas")
        #expect(!CanvasApp.displayName.isEmpty)
    }

    @Test func toolMutatesTheWiredStore() async throws {
        let store = CanvasStore(persistence: InMemoryPersistenceStore(), sessionKey: "default")
        let registry = AgentToolRegistry(tools: [CanvasRenderTool(store: store)])
        let result = await registry.run(ToolCall(
            id: "1", name: "canvas_render",
            input: .object(["op": .string("add"), "id": .string("a"),
                            "kind": .string("text"), "body": .string("hello")])))
        #expect(!result.isError)
        #expect(store.model.elements.first?.body == "hello")
    }
}
