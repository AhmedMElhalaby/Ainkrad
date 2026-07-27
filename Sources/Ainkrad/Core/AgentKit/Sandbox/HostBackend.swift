// Sources/Ainkrad/Core/AgentKit/Sandbox/HostBackend.swift
import Foundation

/// Runs on the host with NO isolation — reserved for the trusted main
/// interactive session. Fs/network policies on the profile are NOT applied
/// at this layer; the router (Task 9) is responsible for never selecting
/// this backend for a non-main/untrusted tier.
struct HostBackend: ExecutionBackend {
    let kind: SandboxBackendKind = .host
    var runner = SandboxProcessRunner()

    func isAvailable() async -> Bool { true }

    func run(_ request: ExecutionRequest) async throws -> ExecutionResult {
        await runner.run(
            executable: "/bin/zsh",
            arguments: ["-lc", request.command],
            workingDir: request.workingDir,
            timeout: TimeInterval(request.profile.resourceLimits.timeoutSeconds),
            onOutput: request.onOutput, controller: request.processController)
    }
}
