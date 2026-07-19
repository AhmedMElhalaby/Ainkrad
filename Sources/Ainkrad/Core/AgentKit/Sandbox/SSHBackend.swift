// Sources/Ainkrad/Core/AgentKit/Sandbox/SSHBackend.swift
import Foundation

/// Runs on a configured remote host over SSH. No local isolation — the
/// remote host is the boundary. FAIL-CLOSED, matching `DockerBackend`/
/// `SeatbeltBackend`: as of this slice, Leyline/AinkradSSH has no host-side
/// connection bridge (see `SSHConnectionInfo`), so every caller wires this
/// with `connection: nil`. With no connection configured — or when the
/// configured host is unreachable — there is NO path where the command
/// falls through to running unsandboxed on the local host: `run` either
/// throws `.unavailable` before spawning anything, or the `ssh` invocation
/// itself fails and its failure is surfaced in the result (never silently
/// swallowed into a local re-run).
struct SSHBackend: ExecutionBackend {
    let kind: SandboxBackendKind = .ssh
    var runner = SandboxProcessRunner()
    var sshPath = "/usr/bin/ssh"
    let connection: SSHConnectionInfo?

    func isAvailable() async -> Bool {
        connection != nil && FileManager.default.isExecutableFile(atPath: sshPath)
    }

    func run(_ request: ExecutionRequest) async throws -> ExecutionResult {
        guard let conn = connection else {
            throw BackendError.unavailable(
                "No SSH host is configured for this run — blocked, not executed locally. " +
                "Configure a Leyline (AinkradSSH) connection first.")
        }
        let args = SSHArgsBuilder.args(conn, command: request.command)
        // BatchMode=yes + ConnectTimeout=10 (baked into SSHArgsBuilder) means
        // an unreachable/unauthorized host fails fast with a non-zero exit —
        // never hangs waiting on a password prompt, and never falls through
        // to any local execution path. SandboxProcessRunner's own timeout is
        // a second, independent bound on top of that.
        return await runner.run(executable: sshPath, arguments: args,
                                workingDir: nil,
                                timeout: TimeInterval(request.profile.resourceLimits.timeoutSeconds))
    }
}
