// Sources/Ainkrad/Core/AgentKit/Sandbox/ExecutionBackend.swift
import Foundation

/// A single request to run a command under a given sandbox profile. The
/// backend (host/seatbelt/docker/ssh) interprets `command` and `profile`
/// into a concrete argv and delegates the actual spawn to `SandboxProcessRunner`.
struct ExecutionRequest: Sendable {
    let command: String        // shell command line (runner wraps with the backend's argv)
    let workingDir: String?
    let profile: SandboxProfile
}

/// The fully-captured outcome of one execution. See the streaming open item
/// in the M7 Slice 6 plan — this preserves `RunTerminalTool`'s "capture fully,
/// return once" behavior; no incremental token stream yet.
struct ExecutionResult: Sendable, Equatable {
    let output: String
    let exitCode: Int32
    let timedOut: Bool
    let unresponsive: Bool
    var isError: Bool { timedOut || unresponsive || exitCode != 0 }
}

enum BackendError: Error, Equatable {
    case unavailable(String)         // backend not installed/running — actionable guidance
    case launch(String)              // process failed to launch
    case profileGeneration(String)   // seatbelt SBPL could not be generated/written (fail-closed)
}

/// A pluggable execution isolation backend. `run` returns a fully-captured result
/// (see the streaming open item in the plan). `isAvailable` feature-detects.
protocol ExecutionBackend: Sendable {
    var kind: SandboxBackendKind { get }
    func isAvailable() async -> Bool
    func run(_ request: ExecutionRequest) async throws -> ExecutionResult
}
