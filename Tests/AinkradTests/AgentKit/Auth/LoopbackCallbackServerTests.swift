import Testing
import Foundation
import Network
@testable import Ainkrad

@Suite struct LoopbackCallbackServerTests {
    @Test func parsesCodeAndStateFromQuery() throws {
        let r = try LoopbackCallbackServer.parseCallback(query: "code=ABC&state=XYZ")
        #expect(r == CallbackResult(code: "ABC", state: "XYZ"))
    }

    @Test func rejectsQueryMissingCode() {
        #expect(throws: LoopbackError.malformedCallback) {
            _ = try LoopbackCallbackServer.parseCallback(query: "state=XYZ")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func roundTripsRealCallbackOverSocket() async throws {
        let testPort: UInt16 = 58_423
        let server = LoopbackCallbackServer(port: testPort)

        async let waited = server.waitForCallback(timeout: 20)

        // Give the listener a moment to bind before the client connects.
        try await Task.sleep(nanoseconds: 200_000_000)
        try await sendRawHTTPRequest(
            to: testPort,
            requestLine: "GET /callback?code=ABC&state=XYZ HTTP/1.1\r\nHost: localhost\r\n\r\n"
        )

        let result = try await waited
        #expect(result == CallbackResult(code: "ABC", state: "XYZ"))
    }

    @Test(.timeLimit(.minutes(1)))
    func timesOutWithoutAConnection() async throws {
        let testPort: UInt16 = 58_424
        let server = LoopbackCallbackServer(port: testPort)

        await #expect(throws: LoopbackError.timedOut) {
            _ = try await server.waitForCallback(timeout: 0.5)
        }
    }

    /// Opens a raw TCP connection to 127.0.0.1:port and writes an HTTP
    /// request line, exercising the server's real socket path end to end.
    private func sendRawHTTPRequest(to port: UInt16, requestLine: String) async throws {
        let connection = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )

        let resumeGuard = ResumeOnceGuard()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: Data(requestLine.utf8), completion: .contentProcessed { error in
                        guard resumeGuard.claim() else { return }
                        if let error { cont.resume(throwing: error) } else { cont.resume(returning: ()) }
                    })
                case .failed(let error):
                    guard resumeGuard.claim() else { return }
                    cont.resume(throwing: error)
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
        connection.cancel()
    }
}

/// Thread-safe single-claim latch so a `CheckedContinuation` captured across
/// multiple `NWConnection` callback paths is resumed exactly once.
private final class ResumeOnceGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
