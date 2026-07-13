import Foundation

/// `LLMProvider` conformer that streams from `POST https://api.openai.com/v1/chat/completions`.
struct OpenAIProvider: LLMProvider {
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

                    var finishReason: String?
                    for try await payload in SSEParser.events(from: bytes) {
                        guard let data = payload.data(using: .utf8) else { continue }
                        guard let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data) else { continue }

                        if let errorMessage = chunk.error?.message {
                            continuation.yield(.failed(errorMessage))
                            continue
                        }

                        guard let choice = chunk.choices?.first else { continue }
                        if let content = choice.delta?.content, !content.isEmpty {
                            continuation.yield(.textDelta(content))
                        }
                        if let reason = choice.finishReason {
                            finishReason = reason
                        }
                    }
                    continuation.yield(.done(stopReason: finishReason))
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
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var wireMessages: [[String: String]] = [["role": "system", "content": system]]
        wireMessages.append(contentsOf: messages.map { ["role": $0.role.rawValue, "content": $0.text] })

        let body: [String: Any] = [
            "model": model.model,
            "stream": true,
            "messages": wireMessages,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Best-effort human-readable message from a non-2xx response body. Never echoes the API key
    /// (the body is the server's response, not the request — the key never appears in it).
    private static func errorMessage(fromResponseBody body: String) -> String {
        if let data = body.data(using: .utf8),
           let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data),
           let message = chunk.error?.message {
            return message
        }
        return "OpenAI API request failed"
    }

    // MARK: - Wire types

    private struct ChatCompletionChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }
            let delta: Delta?
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }
        struct ErrorPayload: Decodable {
            let message: String?
        }

        let choices: [Choice]?
        let error: ErrorPayload?
    }
}
