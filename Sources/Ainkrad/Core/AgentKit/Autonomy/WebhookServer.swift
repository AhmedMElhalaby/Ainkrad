import Foundation
import Network

enum WebhookError: Error, Equatable { case unauthorized, unknownEndpoint, malformed }

struct WebhookRequest: Sendable, Equatable {
    let endpointID: String
    let bearer: String?
    let body: String
}

enum WebhookRequestValidator {
    static func validate(_ request: WebhookRequest, token: String,
                         knownEndpoints: Set<String>) -> Result<TriggerEvent, WebhookError> {
        guard let bearer = request.bearer, !token.isEmpty, constantTimeEquals(bearer, token) else {
            return .failure(.unauthorized)
        }
        guard let id = UUID(uuidString: request.endpointID), knownEndpoints.contains(request.endpointID) else {
            return .failure(.unknownEndpoint)
        }
        return .success(TriggerEvent(scheduleID: id, payload: request.body))
    }

    /// Constant-time string comparison to avoid leaking the shared token via timing side channels.
    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard aBytes.count == bBytes.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<aBytes.count { diff |= aBytes[i] ^ bBytes[i] }
        return diff == 0
    }
}

/// Local-only (127.0.0.1), token-authenticated webhook endpoint. OFF by default.
@MainActor
final class WebhookServer {
    private let port: UInt16
    private let token: String
    private let dispatcher: TriggerDispatcher
    private let schedulesProviding: @MainActor () -> Set<String>
    private var listener: NWListener?
    private(set) var isRunning = false
    private(set) var resolvedPort: UInt16?

    init(port: UInt16, token: String, dispatcher: TriggerDispatcher,
         schedulesProviding: @escaping @MainActor () -> Set<String>) {
        self.port = port
        self.token = token
        self.dispatcher = dispatcher
        self.schedulesProviding = schedulesProviding
    }

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global())
            Task { @MainActor in
                self?.receive(on: connection)
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, case .ready = state else { return }
            Task { @MainActor in
                self.resolvedPort = listener.port?.rawValue
            }
        }
        listener.start(queue: .main)
        self.listener = listener
        isRunning = true
    }

    func stop() { listener?.cancel(); listener = nil; isRunning = false; resolvedPort = nil }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, let raw = String(data: data, encoding: .utf8) else {
                connection.cancel(); return
            }
            Task { @MainActor in
                let parsed = Self.parse(raw)
                let response: String
                if let parsed {
                    let result = WebhookRequestValidator.validate(
                        parsed, token: self.token, knownEndpoints: self.schedulesProviding())
                    switch result {
                    case .success(let event): self.dispatcher.fire(event); response = "HTTP/1.1 202 Accepted\r\n\r\n"
                    case .failure(.unauthorized): response = "HTTP/1.1 401 Unauthorized\r\n\r\n"
                    default: response = "HTTP/1.1 404 Not Found\r\n\r\n"
                    }
                } else {
                    response = "HTTP/1.1 400 Bad Request\r\n\r\n"
                }
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    /// Minimal HTTP parse: `POST /hook/<id>` + `Authorization: Bearer <t>` + body.
    nonisolated static func parse(_ raw: String) -> WebhookRequest? {
        let parts = raw.components(separatedBy: "\r\n\r\n")
        let head = parts.first ?? ""
        let body = parts.count > 1 ? parts[1] : ""
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let tokens = requestLine.components(separatedBy: " ")
        guard tokens.count >= 2, tokens[0] == "POST" else { return nil }
        let path = tokens[1]
        guard let range = path.range(of: "/hook/") else { return nil }
        let endpointID = String(path[range.upperBound...])
        let bearer = lines.first { $0.lowercased().hasPrefix("authorization:") }
            .flatMap { $0.components(separatedBy: "Bearer ").last }
        return WebhookRequest(endpointID: endpointID, bearer: bearer, body: body)
    }
}
