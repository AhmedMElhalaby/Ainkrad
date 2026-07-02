import Testing
import Foundation
@testable import Ainkrad

@Suite("TerminalSession")
@MainActor
struct TerminalSessionTests {

    @Test("a new session starts running with the given shell and working directory")
    func startsRunning() {
        let workingDirectory = URL(fileURLWithPath: "/tmp")
        let session = TerminalSession(workingDirectory: workingDirectory, shellPath: "/bin/zsh")

        #expect(session.isRunning)
        #expect(session.workingDirectory == workingDirectory)
        #expect(session.shellPath == "/bin/zsh")
    }

    @Test("terminate() transitions the session to not running")
    func terminateStopsSession() {
        let session = TerminalSession(workingDirectory: URL(fileURLWithPath: "/tmp"), shellPath: "/bin/zsh")

        session.terminate()

        #expect(!session.isRunning)
    }
}
