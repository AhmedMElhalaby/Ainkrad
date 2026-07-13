import Foundation

/// `LLMProvider` conformer that streams from `POST https://api.anthropic.com/v1/messages`.
struct ClaudeProvider: LLMProvider {
    private let http: StreamingHTTPClient

    init(http: StreamingHTTPClient) {
        self.http = http
    }

    func send(
        messages: [AgentMessage],
        system: String,
        model: AgentModelConfig,
        apiKey: String
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = Self.makeRequest(messages: messages, system: system, model: model, apiKey: apiKey)
                    let bytes = try await http.post(request)

                    var stopReason: String?
                    for try await payload in SSEParser.events(from: bytes) {
                        guard let data = payload.data(using: .utf8) else { continue }
                        guard let envelope = try? JSONDecoder().decode(SSEEnvelope.self, from: data) else { continue }

                        switch envelope.type {
                        case "content_block_delta":
                            if let delta = envelope.delta {
                                switch delta.type {
                                case "thinking_delta":
                                    if let thinking = delta.thinking {
                                        continuation.yield(.thinkingDelta(thinking))
                                    }
                                case "text_delta":
                                    if let text = delta.text {
                                        continuation.yield(.textDelta(text))
                                    }
                                default:
                                    break
                                }
                            }
                        case "message_delta":
                            if let reason = envelope.delta?.stopReason {
                                stopReason = reason
                            }
                        case "message_stop":
                            continuation.yield(.done(stopReason: stopReason))
                        case "error":
                            let message = envelope.error?.message ?? "Anthropic API error"
                            continuation.yield(.failed(message))
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch StreamingHTTPError.status(_, let body) {
                    continuation.yield(.failed(Self.errorMessage(fromResponseBody: body)))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed("Streaming failed: \(error.localizedDescription)"))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Request building

    private static func makeRequest(
        messages: [AgentMessage],
        system: String,
        model: AgentModelConfig,
        apiKey: String
    ) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model.model,
            "max_tokens": 64000,
            "stream": true,
            "system": system,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.text] },
            "thinking": ["type": "adaptive", "display": "summarized"],
            "output_config": ["effort": model.effort],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Best-effort human-readable message from a non-2xx response body. Never echoes the API key
    /// (the body is the server's response, not the request — the key never appears in it).
    private static func errorMessage(fromResponseBody body: String) -> String {
        if let data = body.data(using: .utf8),
           let envelope = try? JSONDecoder().decode(SSEEnvelope.self, from: data),
           let message = envelope.error?.message {
            return message
        }
        return "Anthropic API request failed"
    }

    // MARK: - Wire types

    private struct SSEEnvelope: Decodable {
        struct Delta: Decodable {
            let type: String?
            let thinking: String?
            let text: String?
            let stopReason: String?

            enum CodingKeys: String, CodingKey {
                case type, thinking, text
                case stopReason = "stop_reason"
            }
        }
        struct ErrorPayload: Decodable {
            let message: String?
        }

        let type: String
        let delta: Delta?
        let error: ErrorPayload?
    }
}
