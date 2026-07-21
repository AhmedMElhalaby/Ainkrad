import Testing
import Foundation
@testable import Ainkrad

@Suite struct ClaudeProviderOAuthTests {
    private func body(_ req: URLRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: req.httpBody ?? Data())) as? [String: Any] ?? [:]
    }

    @Test func oauthSetsBearerBetasUAAndXApp() {
        let token = OAuthToken(accessToken: "AT", refreshToken: "RT",
                               expiresAt: Date(), scopes: ["user:inference"])
        let req = ClaudeProvider.makeRequest(
            messages: [], system: "SYS", tools: [],
            model: AgentModelConfig(model: "claude-sonnet-5", effort: "high"),
            credential: .oauth(token))
        #expect(req.value(forHTTPHeaderField: "authorization") == "Bearer AT")
        #expect(req.value(forHTTPHeaderField: "x-api-key") == nil)
        #expect(req.value(forHTTPHeaderField: "x-app") == "cli")
        #expect(req.value(forHTTPHeaderField: "user-agent") == "claude-code/2.1.74")
        let betas = req.value(forHTTPHeaderField: "anthropic-beta") ?? ""
        #expect(betas.contains("claude-code-20250219"))
        #expect(betas.contains("oauth-2025-04-20"))
    }

    @Test func oauthSendsClaudeCodeSystemAsFirstBlockOfAnArray() {
        let token = OAuthToken(accessToken: "AT", refreshToken: "RT", expiresAt: Date(), scopes: [])
        let req = ClaudeProvider.makeRequest(
            messages: [], system: "MY SYSTEM", tools: [],
            model: AgentModelConfig(model: "claude-sonnet-5", effort: "high"),
            credential: .oauth(token))
        // OAuth sends `system` as a block array; the FIRST block must be exactly the
        // Claude Code identity string (verbatim — not concatenated with the user prompt).
        let blocks = body(req)["system"] as? [[String: Any]] ?? []
        #expect(blocks.first?["type"] as? String == "text")
        #expect(blocks.first?["text"] as? String == "You are Claude Code, Anthropic's official CLI for Claude.")
        #expect(blocks.count == 2)
        #expect(blocks.last?["text"] as? String == "MY SYSTEM")
    }

    @Test func oauthRewritesSingleUnderscoreMcpToolNames() {
        let tools = [AgentToolSchema(name: "mcp_git_status", description: "d", parameters: .object([:]))]
        let token = OAuthToken(accessToken: "AT", refreshToken: "RT", expiresAt: Date(), scopes: [])
        let req = ClaudeProvider.makeRequest(
            messages: [], system: "S", tools: tools,
            model: AgentModelConfig(model: "claude-sonnet-5", effort: "high"),
            credential: .oauth(token))
        let names = ((body(req)["tools"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
        #expect(names == ["mcp__git_status"])
    }

    @Test func apiKeyDoesNotRewriteToolNamesOrPrependSystem() {
        let tools = [AgentToolSchema(name: "mcp_git_status", description: "d", parameters: .object([:]))]
        let req = ClaudeProvider.makeRequest(
            messages: [], system: "S", tools: tools,
            model: AgentModelConfig(model: "claude-sonnet-5", effort: "high"),
            credential: .apiKey("k"))
        let names = ((body(req)["tools"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
        #expect(names == ["mcp_git_status"])
        #expect((body(req)["system"] as? String) == "S")
    }
}
