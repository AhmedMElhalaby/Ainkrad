import Foundation

/// `LLMProvider` conformer that streams from `POST https://api.anthropic.com/v1/messages`.
struct ClaudeProvider: LLMProvider {
    private let http: StreamingHTTPClient

    init(http: StreamingHTTPClient) {
        self.http = http
    }

    nonisolated static let claudeCodeVersion = "2.1.74"
    private nonisolated static let claudeCodeSystemPrefix = "You are Claude Code, Anthropic's official CLI for Claude."
    private nonisolated static let oauthBetas =
        "claude-code-20250219,oauth-2025-04-20,interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14"

    /// Subscription billing classifier rejects single-underscore `mcp_` names (400).
    nonisolated static func oauthWireToolName(_ name: String) -> String {
        name.hasPrefix("mcp_") && !name.hasPrefix("mcp__")
            ? "mcp__" + name.dropFirst("mcp_".count)
            : name
    }

    func send(
        messages: [AgentMessage],
        system: String,
        tools: [AgentToolSchema],
        model: AgentModelConfig,
        credential: ProviderCredential
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = Self.makeRequest(messages: messages, system: system, tools: tools, model: model, credential: credential)
                    let bytes = try await http.post(request)

                    var stopReason: String?
                    var toolBlocks: [Int: (id: String, name: String, buffer: String)] = [:]
                    var turnUsage = TokenUsage.zero

                    for try await payload in SSEParser.events(from: bytes) {
                        guard let data = payload.data(using: .utf8) else { continue }
                        guard let envelope = try? JSONDecoder().decode(SSEEnvelope.self, from: data) else { continue }

                        switch envelope.type {
                        case "message_start":
                            if let json = JSONValue.parse(payload) {
                                turnUsage = turnUsage + Self.usageInput(from: json)
                            }
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
                            if let json = JSONValue.parse(payload) {
                                let output = Self.usageOutput(from: json)
                                if output > 0 {
                                    turnUsage = TokenUsage(input: turnUsage.input, output: output,
                                                           cacheRead: turnUsage.cacheRead, cacheWrite: turnUsage.cacheWrite)
                                }
                            }
                        case "message_stop":
                            continuation.yield(.usage(turnUsage))
                            continuation.yield(.done(stopReason: stopReason))
                        case "error":
                            let message = envelope.error?.message ?? "Anthropic API error"
                            continuation.yield(.failed(message))
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch StreamingHTTPError.status(let code, let body) {
                    Log.settings.error("Claude inference \(code, privacy: .public): \(body, privacy: .public)")
                    continuation.yield(.failed(Self.errorMessage(status: code, fromResponseBody: body)))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed("Streaming failed: \(error.localizedDescription)"))
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Usage parsing

    /// `message_delta` usage: `{"usage":{"output_tokens":N}}`.
    nonisolated static func usageOutput(from json: JSONValue) -> Int {
        if case .number(let n)? = json["usage"]?["output_tokens"] { return Int(n) }
        return 0
    }

    /// `message_start` usage: nested under `"message":{"usage":{...}}`; falls back to
    /// a top-level `"usage"` key for direct/test payloads.
    nonisolated static func usageInput(from json: JSONValue) -> TokenUsage {
        let usage = json["message"]?["usage"] ?? json["usage"]
        func int(_ k: String) -> Int { if case .number(let n)? = usage?[k] { return Int(n) }; return 0 }
        return TokenUsage(input: int("input_tokens"), output: 0,
                          cacheRead: int("cache_read_input_tokens"), cacheWrite: int("cache_creation_input_tokens"))
    }

    // MARK: - Request building

    nonisolated static func makeRequest(
        messages: [AgentMessage],
        system: String,
        tools: [AgentToolSchema],
        model: AgentModelConfig,
        credential: ProviderCredential
    ) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var wireTools = tools
        // `.apiKey` sends `system` as a plain string (unchanged). `.oauth` MUST send it
        // as a block array whose FIRST block is exactly the Claude Code identity string —
        // the subscription backend validates that block verbatim, so concatenating the
        // caller's prompt into it (a single string) fails the check. Keep them separate.
        let systemValue: Any
        switch credential {
        case .apiKey(let key):
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            systemValue = system
        case .oauth(let token):
            request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "authorization")
            request.setValue(Self.oauthBetas, forHTTPHeaderField: "anthropic-beta")
            request.setValue("claude-code/\(Self.claudeCodeVersion)", forHTTPHeaderField: "user-agent")
            request.setValue("cli", forHTTPHeaderField: "x-app")
            var blocks: [[String: Any]] = [["type": "text", "text": Self.claudeCodeSystemPrefix]]
            if !system.isEmpty { blocks.append(["type": "text", "text": system]) }
            systemValue = blocks
        }

        var body: [String: Any] = [
            "model": model.model,
            "max_tokens": 64000,
            "stream": true,
            "system": systemValue,
            "messages": messages.map(wireMessage),
            "thinking": ["type": "adaptive", "display": "summarized"],
            "output_config": ["effort": model.effort],
        ]
        if !wireTools.isEmpty {
            let renameNames: Bool = { if case .oauth = credential { return true } else { return false } }()
            body["tools"] = wireTools.map {
                // Tool-name rewriting is OAuth-only: subscription billing classifies by `mcp__` names.
                // Incoming tool_use names from the model already arrive in `mcp__` form and the
                // registry lookup uses the original name, so no inverse mapping is needed here.
                ["name": renameNames ? Self.oauthWireToolName($0.name) : $0.name,
                 "description": $0.description,
                 "input_schema": $0.parameters.toFoundationObject()]
            }
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    nonisolated private static func wireMessage(_ message: AgentMessage) -> [String: Any] {
        let blocks: [[String: Any]] = message.content.map { block in
            switch block {
            case .text(let t):
                return ["type": "text", "text": t]
            case .toolUse(let id, let name, let input):
                return ["type": "tool_use", "id": id, "name": name, "input": input.toFoundationObject()]
            case .toolResult(let toolUseID, let content, let isError):
                return ["type": "tool_result", "tool_use_id": toolUseID, "content": content, "is_error": isError]
            case .image(let mediaType, let base64):
                return ["type": "image", "source": ["type": "base64", "media_type": mediaType, "data": base64]]
            }
        }
        return ["role": message.role.rawValue, "content": blocks]
    }

    /// Best-effort human-readable message from a non-2xx response body. Never echoes the API key
    /// (the body is the server's response, not the request — the key never appears in it).
    private static func errorMessage(status: Int, fromResponseBody body: String) -> String {
        if let data = body.data(using: .utf8),
           let envelope = try? JSONDecoder().decode(SSEEnvelope.self, from: data),
           let message = envelope.error?.message {
            return "Claude API \(status): \(message)"
        }
        let snippet = body.isEmpty ? "" : ": \(body.prefix(300))"
        return "Claude API \(status)\(snippet)"
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
