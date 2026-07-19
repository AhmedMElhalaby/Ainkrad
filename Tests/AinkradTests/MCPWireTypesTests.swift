import Foundation
import Testing
@testable import Ainkrad

@Suite("MCP wire types")
struct MCPWireTypesTests {
    @Test func buildsJSONRPCRequest() {
        let req = MCPRPC.request(id: "7", method: "tools/list", params: .object([:]))
        #expect(req["jsonrpc"]?.stringValue == "2.0")
        #expect(req["id"]?.stringValue == "7")
        #expect(req["method"]?.stringValue == "tools/list")
        #expect(req["params"] != nil)
    }

    @Test func notificationHasNoID() {
        let n = MCPRPC.notification(method: "notifications/initialized", params: .object([:]))
        #expect(n["method"]?.stringValue == "notifications/initialized")
        #expect(n["id"] == nil)
    }

    @Test func decodesSuccessResponse() {
        let msg = JSONValue.object([
            "jsonrpc": .string("2.0"), "id": .string("7"),
            "result": .object(["ok": .bool(true)]),
        ])
        guard case .success(let (id, result)) = MCPRPC.decodeResponse(msg) else {
            Issue.record("expected success"); return
        }
        #expect(id == "7")
        #expect(result["ok"] != nil)
    }

    @Test func decodesRPCError() {
        let msg = JSONValue.object([
            "jsonrpc": .string("2.0"), "id": .string("9"),
            "error": .object(["code": .number(-32601), "message": .string("Method not found")]),
        ])
        guard case .failure(.rpc(let code, let message)) = MCPRPC.decodeResponse(msg) else {
            Issue.record("expected rpc error"); return
        }
        #expect(code == -32601)
        #expect(message == "Method not found")
    }

    @Test func decodesRPCErrorWithOutOfRangeCodeDoesNotCrash() {
        let msg = JSONValue.object([
            "jsonrpc": .string("2.0"), "id": .string("9"),
            "error": .object(["code": .number(1e300), "message": .string("huge code")]),
        ])
        guard case .failure(.rpc(let code, let message)) = MCPRPC.decodeResponse(msg) else {
            Issue.record("expected rpc error"); return
        }
        #expect(code == 0)
        #expect(message == "huge code")
    }

    @Test func decodesRPCErrorWithNaNCodeDoesNotCrash() {
        let msg = JSONValue.object([
            "jsonrpc": .string("2.0"), "id": .string("9"),
            "error": .object(["code": .number(.nan), "message": .string("nan code")]),
        ])
        guard case .failure(.rpc(let code, let message)) = MCPRPC.decodeResponse(msg) else {
            Issue.record("expected rpc error"); return
        }
        #expect(code == 0)
        #expect(message == "nan code")
    }

    @Test func decodesToolList() {
        let result = JSONValue.object(["tools": .array([
            .object(["name": .string("search"),
                     "description": .string("web search"),
                     "inputSchema": .object(["type": .string("object")])]),
            .object(["name": .string("fetch")]),   // missing desc/schema tolerated
        ])])
        let tools = MCPRPC.decodeToolList(result)
        #expect(tools.count == 2)
        #expect(tools.first?.name == "search")
        #expect(tools.first?.description == "web search")
        #expect(tools.last?.description == "")
    }
}
