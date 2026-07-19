// Tests/AinkradTests/MCPStdioTransportTests.swift
import Foundation
import Testing
@testable import Ainkrad

@Suite("StdioTransport (real subprocess)")
struct MCPStdioTransportTests {
    /// A `cat`-based echo server: newline-delimited JSON in → same line out.
    /// Verifies real spawn + framing without a heavyweight MCP binary.
    @Test func echoesNewlineDelimitedJSON() async throws {
        let t = StdioTransport(command: "/bin/cat", args: [], env: [:])
        try await t.start()
        defer { Task { await t.stop() } }

        var iterator = t.incoming().makeAsyncIterator()
        try await t.send(.object(["jsonrpc": .string("2.0"), "id": .string("1"),
                                  "method": .string("ping"), "params": .object([:])]))
        let received = try await iterator.next()
        #expect(received?["id"]?.stringValue == "1")
        #expect(received?["method"]?.stringValue == "ping")
    }

    @Test func startFailsForMissingExecutable() async {
        let t = StdioTransport(command: "/nonexistent/bin/does-not-exist", args: [], env: [:])
        await #expect(throws: MCPError.self) { try await t.start() }
    }
}
