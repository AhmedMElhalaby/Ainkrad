// Sources/Ainkrad/Core/AgentKit/Sandbox/SeatbeltBackend.swift
import Foundation

/// Wraps execution in a generated deny-by-default macOS sandbox profile via
/// `sandbox-exec`. FAIL-CLOSED invariant: any failure along the way (SBPL
/// generation, temp-file write, `sandbox-exec` unavailable) yields a blocked/
/// failed result — there is NO path where the command falls through to
/// running unsandboxed on the host.
struct SeatbeltBackend: ExecutionBackend {
    let kind: SandboxBackendKind = .seatbelt
    var runner = SandboxProcessRunner()
    var sandboxExecPath = "/usr/bin/sandbox-exec"

    /// Feature detection only — a stat() check, never a spawn, so this can't
    /// hang or block on an unbounded subprocess.
    func isAvailable() async -> Bool {
        FileManager.default.isExecutableFile(atPath: sandboxExecPath)
    }

    func run(_ request: ExecutionRequest) async throws -> ExecutionResult {
        // Fail-closed: sandbox-exec missing/not executable → never run
        // unsandboxed. Reported as a blocked result, not silently skipped.
        guard await isAvailable() else {
            return ExecutionResult(
                output: "sandbox-exec not available at \(sandboxExecPath); command blocked (fail-closed).",
                exitCode: -1, timedOut: false, unresponsive: false)
        }

        let workspace = request.workingDir ?? NSHomeDirectory()

        let sbpl: String
        do {
            sbpl = try SeatbeltProfileGenerator.generate(
                fs: request.profile.fsPolicy,
                network: request.profile.networkPolicy,
                workspacePath: workspace)
        } catch {
            // Fail-closed: SBPL generation failure blocks the command outright.
            throw BackendError.profileGeneration("\(error)")
        }

        let profileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ain-sbx-\(UUID().uuidString).sb")
        do {
            try sbpl.write(to: profileURL, atomically: true, encoding: .utf8)
        } catch {
            // Fail-closed: can't write the profile → can't sandbox → don't run.
            throw BackendError.profileGeneration("Could not write SBPL: \(error)")
        }
        defer { try? FileManager.default.removeItem(at: profileURL) }

        // Non-login `-c` on purpose: a login shell reads ~/.zshrc/dotfiles that
        // live OUTSIDE the allowed path set, so `-lc` would fail (or behave
        // differently) for the wrong reason inside the sandbox. Contrast with
        // HostBackend's `-lc`, which is fine on the trusted, unrestricted host.
        return await runner.run(
            executable: sandboxExecPath,
            arguments: ["-f", profileURL.path, "/bin/zsh", "-c", request.command],
            workingDir: workspace,
            timeout: TimeInterval(request.profile.resourceLimits.timeoutSeconds))
    }
}
