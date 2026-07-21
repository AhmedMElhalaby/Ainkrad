import Foundation
import Network

struct CallbackResult: Equatable { let code: String; let state: String }
enum LoopbackError: Error, Equatable { case bindFailed, timedOut, malformedCallback }

/// One-shot loopback HTTP listener on 127.0.0.1:<port>. Captures the OAuth
/// redirect's `code`/`state`, serves a "you can close this tab" page, then stops.
actor LoopbackCallbackServer {
    private let port: UInt16
    private var listener: NWListener?

    init(port: UInt16 = 53692) { self.port = port }

    /// Pure parser for the callback query string.
    static func parseCallback(query: String) throws -> CallbackResult {
        var comps = URLComponents()
        comps.query = query
        let items = comps.queryItems ?? []
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw LoopbackError.malformedCallback
        }
        let state = items.first(where: { $0.name == "state" })?.value ?? ""
        return CallbackResult(code: code, state: state)
    }

    func waitForCallback(timeout: TimeInterval) async throws -> CallbackResult {
        let listener: NWListener
        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: .init(rawValue: port)!)
        } catch { throw LoopbackError.bindFailed }
        self.listener = listener

        return try await withThrowingTaskGroup(of: CallbackResult.self) { group in
            group.addTask { try await self.accept(on: listener) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw LoopbackError.timedOut
            }
            defer { listener.cancel() }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func accept(on listener: NWListener) async throws -> CallbackResult {
        try await withCheckedThrowingContinuation { cont in
            listener.newConnectionHandler = { connection in
                connection.start(queue: .global())
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                    guard let data, let request = String(data: data, encoding: .utf8),
                          let firstLine = request.split(separator: "\r\n").first,
                          let path = firstLine.split(separator: " ").dropFirst().first,
                          let queryStart = path.firstIndex(of: "?") else {
                        cont.resume(throwing: LoopbackError.malformedCallback); return
                    }
                    let query = String(path[path.index(after: queryStart)...])
                    let html = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n" +
                               "<html><body style='font-family:-apple-system'>Signed in. You can close this tab.</body></html>"
                    connection.send(content: Data(html.utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                    do { cont.resume(returning: try Self.parseCallback(query: query)) }
                    catch { cont.resume(throwing: error) }
                }
            }
            listener.start(queue: .global())
        }
    }
}
