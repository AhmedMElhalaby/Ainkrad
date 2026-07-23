// Sources/Ainkrad/Core/AgentKit/Sandbox/SSHArgsBuilder.swift
import Foundation

/// Pure builder for `ssh` argv. Mirrors the security posture of
/// `DockerArgsBuilder`/`SeatbeltProfileGenerator`: argv is built as a
/// `[String]`, never a shell-joined string, so a host/user/identity path or
/// remote command containing shell/ssh metacharacters can't inject an extra
/// `ssh` option or escape its argv slot — `Process` passes each element to
/// `ssh` verbatim, with no shell re-tokenization step. The only place shell
/// syntax appears is inside the single, final "remote command" argv element,
/// which the REMOTE shell interprets — never local `ssh` option parsing.
enum SSHArgsBuilder {
    static func args(_ conn: SSHConnectionInfo, command: String) -> [String] {
        var args: [String] = []
        if let id = conn.identityPath { args += ["-i", id] }
        if let port = conn.port { args += ["-p", "\(port)"] }
        args += ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]
        args.append("\(conn.user)@\(conn.host)")
        let remote = conn.remoteWorkingDir.map { "cd \($0) && \(command)" } ?? command
        args.append(remote)
        return args
    }
}
