import Testing
import Foundation
@testable import Ainkrad
import AinkradHostRuntime

@MainActor
@Suite("WorkspaceControlTool")
struct WorkspaceControlToolTests {
    private func obj(_ d: [String: JSONValue]) -> JSONValue { .object(d) }

    @Test("createWorkspace adds a workspace and returns success")
    func createWorkspace() async throws {
        let wm = WorkspaceManager()
        let tool = WorkspaceControlTool(workspaces: wm)
        let before = wm.workspaces.count
        let result = try await tool.execute(obj(["action": .string("createWorkspace")]))
        #expect(!result.isError)
        #expect(wm.workspaces.count == before + 1)
    }

    @Test("switchToWorkspace by index changes the active workspace")
    func switchByIndex() async throws {
        let wm = WorkspaceManager()
        _ = wm.createWorkspace()               // index 1 exists now
        let tool = WorkspaceControlTool(workspaces: wm)
        _ = try await tool.execute(obj(["action": .string("switchToWorkspace"),
                                        "index": .number(0)]))
        #expect(wm.activeWorkspaceID == wm.workspaces[0].id)
    }

    @Test("deleteWorkspace removes a non-main workspace")
    func deleteWorkspace() async throws {
        let wm = WorkspaceManager()
        let created = wm.createWorkspace()
        let tool = WorkspaceControlTool(workspaces: wm)
        _ = try await tool.execute(obj(["action": .string("deleteWorkspace"),
                                        "id": .string(created.id.uuidString)]))
        #expect(!wm.workspaces.contains { $0.id == created.id })
    }

    @Test("deleteWorkspace is flagged irreversible; others are not")
    func irreversibility() {
        let tool = WorkspaceControlTool(workspaces: WorkspaceManager())
        #expect(tool.isIrreversible(obj(["action": .string("deleteWorkspace"), "id": .string("x")])))
        #expect(!tool.isIrreversible(obj(["action": .string("createWorkspace")])))
    }

    @Test("unknown action returns an error result")
    func unknownAction() async throws {
        let tool = WorkspaceControlTool(workspaces: WorkspaceManager())
        let result = try await tool.execute(obj(["action": .string("nope")]))
        #expect(result.isError)
    }

    @Test("switchToWorkspace rejects non-finite, out-of-range, and fractional indices without crashing")
    func switchByIndexRejectsInvalidValues() async throws {
        let wm = WorkspaceManager()
        let tool = WorkspaceControlTool(workspaces: wm)

        let infResult = try await tool.execute(obj(["action": .string("switchToWorkspace"),
                                                     "index": .number(Double.infinity)]))
        #expect(infResult.isError)

        let nanResult = try await tool.execute(obj(["action": .string("switchToWorkspace"),
                                                     "index": .number(Double.nan)]))
        #expect(nanResult.isError)

        let hugeResult = try await tool.execute(obj(["action": .string("switchToWorkspace"),
                                                      "index": .number(1e30)]))
        #expect(hugeResult.isError)

        let fractionalResult = try await tool.execute(obj(["action": .string("switchToWorkspace"),
                                                            "index": .number(2.5)]))
        #expect(fractionalResult.isError)

        let negativeResult = try await tool.execute(obj(["action": .string("switchToWorkspace"),
                                                          "index": .number(-1)]))
        #expect(negativeResult.isError)
    }
}
