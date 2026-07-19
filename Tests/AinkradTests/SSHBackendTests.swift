// Tests/AinkradTests/SSHBackendTests.swift
import Foundation
import Testing
@testable import Ainkrad

@Suite("SSHBackend")
struct SSHBackendTests {
    @Test func unavailableWhenNoConnectionConfigured() async {
        let b = SSHBackend(connection: nil)
        #expect(await b.isAvailable() == false)
        await #expect(throws: BackendError.self) {
            _ = try await b.run(ExecutionRequest(command: "ls", workingDir: nil,
                                                 profile: BuiltInSandboxProfiles.networkedBuild))
        }
    }

    // Fail-closed: with no connection configured, the command must never
    // fall through to running unsandboxed on the local host. Prove it with
    // a marker file the (never-run) command would create locally.
    @Test func unconfiguredNeverFallsThroughToLocalExecution() async {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("ain-ssh-fail-closed-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: marker) }

        let b = SSHBackend(connection: nil)
        await #expect(throws: BackendError.self) {
            _ = try await b.run(ExecutionRequest(command: "touch \(marker.path)", workingDir: nil,
                                                 profile: BuiltInSandboxProfiles.networkedBuild))
        }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func unavailableErrorCarriesGuidanceText() async {
        let b = SSHBackend(connection: nil)
        do {
            _ = try await b.run(ExecutionRequest(command: "ls", workingDir: nil,
                                                 profile: BuiltInSandboxProfiles.networkedBuild))
            Issue.record("expected BackendError.unavailable to be thrown")
        } catch let BackendError.unavailable(message) {
            #expect(message.localizedCaseInsensitiveContains("ssh"))
        } catch {
            Issue.record("expected BackendError.unavailable, got \(error)")
        }
    }

    @Test func sshFailureSurfacesAsError() async throws {
        // Deterministic, no network: point sshPath at /usr/bin/false so the
        // "ssh" invocation exits non-zero — exactly what a real unreachable
        // host does (BatchMode=yes + ConnectTimeout=10 exit 255).
        let conn = SSHConnectionInfo(host: "h", user: "u", port: nil,
                                     identityPath: nil, remoteWorkingDir: nil)
        var b = SSHBackend(connection: conn)
        b.sshPath = "/usr/bin/false"
        let r = try await b.run(ExecutionRequest(command: "echo hi", workingDir: nil,
                                                 profile: BuiltInSandboxProfiles.networkedBuild))
        #expect(r.isError)   // failure surfaced, never a silent success
    }

    @Test func kindIsSSH() { #expect(SSHBackend(connection: nil).kind == .ssh) }
}
