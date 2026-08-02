import Foundation
import Testing
@testable import Ainkrad
import AinkradHostRuntime

@Suite("ScryReconstruction")
struct ScryReconstructionTests {
    private func call(_ op: String, id: String, kind: String? = nil, body: String? = nil) -> AgentContentBlock {
        var fields: [String: JSONValue] = ["op": .string(op), "id": .string(id)]
        if let kind { fields["kind"] = .string(kind) }
        if let body { fields["body"] = .string(body) }
        return .toolUse(id: UUID().uuidString, name: "scry_render", input: .object(fields))
    }

    @Test func replaysAddThenUpdate() {
        let messages = [
            AgentMessage(role: .assistant, content: [call("add", id: "t1", kind: "table", body: "r1")]),
            AgentMessage(role: .assistant, content: [call("update", id: "t1", body: "r1\nr2")]),
        ]
        let model = ScryReconstruction.rebuild(from: messages)
        #expect(model.elements.count == 1)
        #expect(model.elements.first?.body == "r1\nr2")
    }

    @Test func replaysRemove() {
        let messages = [
            AgentMessage(role: .assistant, content: [call("add", id: "a", kind: "text", body: "x")]),
            AgentMessage(role: .assistant, content: [call("remove", id: "a")]),
        ]
        #expect(ScryReconstruction.rebuild(from: messages).elements.isEmpty)
    }

    @Test func ignoresNonCanvasToolCalls() {
        let messages = [
            AgentMessage(role: .assistant,
                content: [.toolUse(id: "z", name: "read_file", input: .object(["path": .string("/x")]))]),
        ]
        #expect(ScryReconstruction.rebuild(from: messages).elements.isEmpty)
    }
}
