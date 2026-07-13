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
        tools: [AgentToolSchema],
        model: AgentModelConfig,
        apiKey: String
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = Self.makeRequest(messages: messages, system: system, tools: tools, model: model, apiKey: apiKey)
                    let bytes = try await http.post(request)

                    var finishReason: String?
                    var calls: [Int: (id: String, name: String, args: String)] = [:]

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
                        for tc in choice.delta?.toolCalls ?? [] {
                            var entry = calls[tc.index] ?? (id: "", name: "", args: "")
                            if let id = tc.id { entry.id = id }
                            if let name = tc.function?.name { entry.name = name }
                            if entry.id.isEmpty == false, entry.name.isEmpty == false, calls[tc.index] == nil {
                                continuation.yield(.toolUseStart(id: entry.id, name: entry.name))
                            }
                            if let args = tc.function?.arguments, !args.isEmpty {
                                entry.args += args
                                continuation.yield(.toolInputDelta(id: entry.id, partialJSON: args))
                            }
                            calls[tc.index] = entry
                        }
                        if let reason = choice.finishReason {
                            finishReason = reason
                        }
                    }

                    if finishReason == "tool_calls" {
                        for index in calls.keys.sorted() {
                            let entry = calls[index]!
                            let input = JSONValue.parse(entry.args) ?? .object([:])
                            continuation.yield(.toolUseComplete(id: entry.id, name: entry.name, input: input))
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
        tools: [AgentToolSchema],
        model: AgentModelConfig,
        apiKey: String
    ) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var wireMessages: [[String: Any]] = [["role": "system", "content": system]]
        wireMessages.append(contentsOf: messages.flatMap(wireMessages(for:)))

        var body: [String: Any] = [
            "model": model.model,
            "stream": true,
            "messages": wireMessages,
        ]
        if !tools.isEmpty {
            body["tools"] = tools.map {
                ["type": "function",
                 "function": ["name": $0.name, "description": $0.description,
                              "parameters": $0.parameters.toFoundationObject()]]
            }
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// One `AgentMessage` can expand into multiple OpenAI wire messages: an
    /// assistant turn with tool calls, then one `role:"tool"` message per result.
    private static func wireMessages(for message: AgentMessage) -> [[String: Any]] {
        var texts: [String] = []
        var toolCalls: [[String: Any]] = []
        var toolResults: [[String: Any]] = []
        for block in message.content {
            switch block {
            case .text(let t): texts.append(t)
            case .toolUse(let id, let name, let input):
                let args = String(decoding: (try? JSONSerialization.data(withJSONObject: input.toFoundationObject())) ?? Data("{}".utf8), as: UTF8.self)
                toolCalls.append(["id": id, "type": "function",
                                  "function": ["name": name, "arguments": args]])
            case .toolResult(let toolUseID, let content, _):
                toolResults.append(["role": "tool", "tool_call_id": toolUseID, "content": content])
            }
        }
        var out: [[String: Any]] = []
        if message.role == .assistant, !toolCalls.isEmpty {
            out.append(["role": "assistant", "content": texts.joined(), "tool_calls": toolCalls])
        } else if !texts.isEmpty || toolResults.isEmpty {
            out.append(["role": message.role.rawValue, "content": texts.joined()])
        }
        out.append(contentsOf: toolResults)
        return out
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
                struct ToolCall: Decodable {
                    struct Function: Decodable { let name: String?; let arguments: String? }
                    let index: Int
                    let id: String?
                    let function: Function?
                }
                let content: String?
                let toolCalls: [ToolCall]?
                enum CodingKeys: String, CodingKey { case content; case toolCalls = "tool_calls" }
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
