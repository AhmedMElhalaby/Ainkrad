// Sources/Ainkrad/Core/AgentKit/MCP/StdioTransport.swift
import Foundation

/// Spawns a local MCP server subprocess and speaks newline-delimited JSON-RPC
/// over its stdio. Mirrors the `Process`+`Pipe` pattern used by `RunTerminalTool`
/// / `DittoUnzipper`, but keeps the process alive for the session. Process
/// sandboxing is Slice 6 — the env is controlled but the process is not jailed.
actor StdioTransport: MCPTransport {
    private let command: String
    private let args: [String]
    private let env: [String: String]
    private var process: Process?
    // `nonisolated(unsafe)`: `Pipe`/`FileHandle` are kernel-backed and safe to
    // touch off-actor. `send()` (actor-isolated) writes to `stdin` and the
    // `nonisolated incoming()` reads `stdout` from a `readabilityHandler`
    // callback that never runs on the actor's executor — both are required
    // to satisfy the protocol's non-actor-isolated `incoming()` requirement.
    private nonisolated(unsafe) let stdin = Pipe()
    private nonisolated(unsafe) let stdout = Pipe()

    init(command: String, args: [String], env: [String: String]) {
        self.command = command
        self.args = args
        self.env = env
    }

    func start() async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: command)
        p.arguments = args
        // Start from the current environment (so PATH resolves node/npx/python)
        // then overlay the configured, secret-injected values.
        var merged = ProcessInfo.processInfo.environment
        for (k, v) in env { merged[k] = v }
        p.environment = merged
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = Pipe()   // drained to /dev/null implicitly (never read)
        do {
            try p.run()
        } catch {
            throw MCPError.transport("could not launch \(command): \(error.localizedDescription)")
        }
        process = p
    }

    func send(_ message: JSONValue) async throws {
        guard process?.isRunning == true else { throw MCPError.notConnected }
        let obj = message.toFoundationObject()
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else {
            throw MCPError.protocolError("could not serialize outbound message")
        }
        var line = data
        line.append(0x0A)   // '\n' — newline-delimited framing
        stdin.fileHandleForWriting.write(line)
    }

    nonisolated func incoming() -> AsyncThrowingStream<JSONValue, Error> {
        let handle = stdout.fileHandleForReading
        return AsyncThrowingStream { continuation in
            let parser = LineParser()   // buffers partial lines across chunks
            handle.readabilityHandler = { fh in
                let chunk = fh.availableData
                guard !chunk.isEmpty else { continuation.finish(); return } // EOF
                for line in parser.push(chunk) {
                    if let value = JSONValue.parse(line) { continuation.yield(value) }
                    // Non-JSON stdout noise (server banners) is ignored, never fatal.
                }
            }
            continuation.onTermination = { _ in handle.readabilityHandler = nil }
        }
    }

    func stop() async {
        stdout.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
    }
}

/// Accumulates bytes and emits complete `\n`-terminated UTF-8 lines. Only ever
/// touched from the single serial `readabilityHandler` callback captured in
/// `incoming()`, so the mutable `buffer` is safe without a lock — `@unchecked
/// Sendable` only tells the compiler that invariant holds (mirrors
/// `OutputAccumulator` in `RunTerminalTool`, which documents the same pattern).
private final class LineParser: @unchecked Sendable {
    private var buffer = Data()
    func push(_ chunk: Data) -> [String] {
        buffer.append(chunk)
        var lines: [String] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            let s = String(decoding: lineData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { lines.append(s) }
        }
        return lines
    }
}
