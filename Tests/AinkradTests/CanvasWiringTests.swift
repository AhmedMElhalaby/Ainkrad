import Foundation
import Testing
@testable import Ainkrad
import AinkradHostRuntime

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

    // Post-review fix (I1): `canvas_render` is bound to the FOREGROUND
    // `canvasStore` (sessionKey "default" — the same store `CanvasApp` reads).
    // The background/headless tool registry `AppEnvironment` builds for
    // `RunManager`-driven runs (background/schedule/trigger) MUST exclude it,
    // mirroring the exact `agentTools.filter { !($0 is CanvasRenderTool) }`
    // AppEnvironment applies when deriving `backgroundAgentTools` — otherwise
    // an autonomous run could silently mutate the canvas the user is viewing.
    @Test func backgroundRegistryExcludesCanvasRenderButForegroundKeepsIt() {
        let store = CanvasStore(persistence: InMemoryPersistenceStore(), sessionKey: "default")
        let agentTools: [any AgentTool] = [ReadFileTool(), CanvasRenderTool(store: store)]
        let foregroundRegistry = AgentToolRegistry(tools: agentTools)
        let backgroundAgentTools = agentTools.filter { !($0 is CanvasRenderTool) }
        let backgroundRegistry = AgentToolRegistry(tools: backgroundAgentTools)

        #expect(foregroundRegistry.tool(named: "canvas_render") != nil)
        #expect(backgroundRegistry.tool(named: "canvas_render") == nil)
        // Sanity: the filter didn't drop anything else.
        #expect(backgroundRegistry.tool(named: "read_file") != nil)
    }
}
