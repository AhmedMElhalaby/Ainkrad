import Testing
import Foundation
import AinkradAppKit
@testable import Ainkrad

@MainActor
@Suite("RunTerminalTool")
struct RunTerminalToolTests {
    private func obj(_ d: [String: JSONValue]) -> JSONValue { .object(d) }

    @Test("captures stdout of a command")
    func capturesOutput() async throws {
        let hub = AgentActionRegistryHub()
        let tool = RunTerminalTool(actionHub: hub)
        let result = try await tool.execute(obj(["command": .string("echo hello-ainkrad")]))
        #expect(!result.isError)
        #expect(result.content.contains("hello-ainkrad"))
    }

    @Test("dispatches a terminal.echo action with command + output")
    func dispatchesEcho() async throws {
        let hub = AgentActionRegistryHub()
        var received: String?
        _ = hub.register(appID: "terminal", actionID: "terminal.echo") { json in
            received = json
            return AgentActionResult(text: "ok", isError: false)
        }
        let tool = RunTerminalTool(actionHub: hub)
        _ = try await tool.execute(obj(["command": .string("echo hi")]))
        let json = try #require(received)
        #expect(json.contains("\"command\""))
        #expect(json.contains("hi"))
    }

    @Test("missing echo handler is a no-op (best effort)")
    func echoNoOp() async throws {
        let hub = AgentActionRegistryHub()   // nothing registered
        let tool = RunTerminalTool(actionHub: hub)
        let result = try await tool.execute(obj(["command": .string("echo ok")]))
        #expect(!result.isError)
    }

    @Test("flags destructive commands irreversible")
    func irreversible() {
        let tool = RunTerminalTool(actionHub: AgentActionRegistryHub())
        #expect(tool.isIrreversible(obj(["command": .string("rm -rf /tmp/x")])))
        #expect(tool.isIrreversible(obj(["command": .string("dd if=/dev/zero of=x")])))
        #expect(!tool.isIrreversible(obj(["command": .string("ls -la")])))
    }

    @Test("a hung/never-terminating command is force-killed at the timeout, not left to hang")
    func timesOutOnHungCommand() async throws {
        let hub = AgentActionRegistryHub()
        var tool = RunTerminalTool(actionHub: hub)
        tool.timeout = 1
        let start = Date()
        let result = try await tool.execute(obj(["command": .string("sleep 5")]))
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 4, "expected the 1s timeout to fire, not the full 5s sleep (elapsed: \(elapsed)s)")
        #expect(result.isError)
        #expect(result.content.contains("[terminated: exceeded 1.0s]"))
    }

    @Test("a command that traps SIGTERM and SIGINT returns instead of crashing on terminationStatus")
    func unresponsiveCommandReturnsInsteadOfCrashing() async throws {
        // Regression test: reading `Process.terminationStatus` while the process is
        // still `isRunning` raises NSInvalidArgumentException and crashes the host.
        // A command that ignores both SIGTERM and SIGINT is still running when the
        // last-resort fallback fires, so the tool must detect that and avoid the read.
        let hub = AgentActionRegistryHub()
        var tool = RunTerminalTool(actionHub: hub)
        tool.timeout = 1
        let start = Date()
        let result = try await tool.execute(obj(["command": .string("trap '' TERM INT; sleep 100")]))
        let elapsed = Date().timeIntervalSince(start)
        // 1s timeout + 0.5s SIGTERM grace + 0.5s SIGINT grace ≈ 2s; give generous headroom
        // but still bound well under the 100s sleep so a regression that hangs is caught.
        #expect(elapsed < 6, "expected the fallback to resume promptly, not hang (elapsed: \(elapsed)s)")
        #expect(result.isError)
        #expect(result.content.contains("[terminated: exceeded 1.0s; process unresponsive to SIGTERM/SIGINT]"))
    }
}
