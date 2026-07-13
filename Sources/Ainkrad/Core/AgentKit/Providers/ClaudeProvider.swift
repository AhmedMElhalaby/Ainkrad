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
        tools: [AgentToolSchema],
        model: AgentModelConfig,
        apiKey: String
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = Self.makeRequest(messages: messages, system: system, tools: tools, model: model, apiKey: apiKey)
                    let bytes = try await http.post(request)

                    var stopReason: String?
                    var toolBlocks: [Int: (id: String, name: String, buffer: String)] = [:]

                    for try await payload in SSEParser.events(from: bytes) {
                        guard let data = payload.data(using: .utf8) else { continue }
                        guard let envelope = try? JSONDecoder().decode(SSEEnvelope.self, from: data) else { continue }

                        switch envelope.type {
                        case "content_block_start":
                            if envelope.contentBlock?.type == "tool_use",
                               let index = envelope.index,
                               let id = envelope.contentBlock?.id,
                               let name = envelope.contentBlock?.name {
                                toolBlocks[index] = (id, name, "")
                                continuation.yield(.toolUseStart(id: id, name: name))
                            }
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
                                case "input_json_delta":
                                    if let index = envelope.index, let partial = delta.partialJSON,
                                       var entry = toolBlocks[index] {
                                        entry.buffer += partial
                                        toolBlocks[index] = entry
                                        continuation.yield(.toolInputDelta(id: entry.id, partialJSON: partial))
                                    }
                                default:
                                    break
                                }
                            }
                        case "content_block_stop":
                            if let index = envelope.index, let entry = toolBlocks[index] {
                                let input = JSONValue.parse(entry.buffer) ?? .object([:])
                                continuation.yield(.toolUseComplete(id: entry.id, name: entry.name, input: input))
                                toolBlocks[index] = nil
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
        tools: [AgentToolSchema],
        model: AgentModelConfig,
        apiKey: String
    ) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var body: [String: Any] = [
            "model": model.model,
            "max_tokens": 64000,
            "stream": true,
            "system": system,
            "messages": messages.map(wireMessage),
            "thinking": ["type": "adaptive", "display": "summarized"],
            "output_config": ["effort": model.effort],
        ]
        if !tools.isEmpty {
            body["tools"] = tools.map {
                ["name": $0.name, "description": $0.description,
                 "input_schema": $0.parameters.toFoundationObject()]
            }
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func wireMessage(_ message: AgentMessage) -> [String: Any] {
        let blocks: [[String: Any]] = message.content.map { block in
            switch block {
            case .text(let t):
                return ["type": "text", "text": t]
            case .toolUse(let id, let name, let input):
                return ["type": "tool_use", "id": id, "name": name, "input": input.toFoundationObject()]
            case .toolResult(let toolUseID, let content, let isError):
                return ["type": "tool_result", "tool_use_id": toolUseID, "content": content, "is_error": isError]
            }
        }
        return ["role": message.role.rawValue, "content": blocks]
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
        struct ContentBlock: Decodable {
            let type: String?
            let id: String?
            let name: String?
        }
        struct Delta: Decodable {
            let type: String?
            let thinking: String?
            let text: String?
            let partialJSON: String?
            let stopReason: String?

            enum CodingKeys: String, CodingKey {
                case type, thinking, text
                case partialJSON = "partial_json"
                case stopReason = "stop_reason"
            }
        }
        struct ErrorPayload: Decodable {
            let message: String?
        }

        let type: String
        let index: Int?
        let contentBlock: ContentBlock?
        let delta: Delta?
        let error: ErrorPayload?

        enum CodingKeys: String, CodingKey {
            case type, index, delta, error
            case contentBlock = "content_block"
        }
    }
}
