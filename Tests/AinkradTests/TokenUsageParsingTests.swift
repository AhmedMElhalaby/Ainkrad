import Foundation
import Testing
@testable import Ainkrad

@Suite("TokenUsage")
struct TokenUsageParsingTests {
    @Test func additionAndZero() {
        let a = TokenUsage(input: 10, output: 5, cacheRead: 1, cacheWrite: 0)
        let b = TokenUsage(input: 3, output: 2, cacheRead: 0, cacheWrite: 4)
        let s = a + b
        #expect(s == TokenUsage(input: 13, output: 7, cacheRead: 1, cacheWrite: 4))
        #expect(TokenUsage.zero == TokenUsage(input: 0, output: 0, cacheRead: 0, cacheWrite: 0))
    }

    @Test func claudeUsageParse() {
        // The provider exposes a static parser for the message_delta usage JSON.
        let json = JSONValue.parse(#"{"usage":{"output_tokens":42}}"#)!
        #expect(ClaudeProvider.usageOutput(from: json) == 42)
    }

    @Test func claudeMessageStartUsageParse() {
        let json = JSONValue.parse(#"{"type":"message_start","message":{"usage":{"input_tokens":100,"cache_read_input_tokens":10,"cache_creation_input_tokens":5}}}"#)!
        let u = ClaudeProvider.usageInput(from: json)
        #expect(u.input == 100)
        #expect(u.cacheRead == 10)
        #expect(u.cacheWrite == 5)
        #expect(u.output == 0)
    }

    @Test func openAIUsageParse() {
        let json = JSONValue.parse(#"{"usage":{"prompt_tokens":100,"completion_tokens":20}}"#)!
        let u = OpenAICompatibleProvider.usage(from: json)
        #expect(u?.input == 100)
        #expect(u?.output == 20)
    }

    @Test func openAIUsageParseCachedTokens() {
        let json = JSONValue.parse(#"{"usage":{"prompt_tokens":100,"completion_tokens":20,"prompt_tokens_details":{"cached_tokens":15}}}"#)!
        let u = OpenAICompatibleProvider.usage(from: json)
        #expect(u?.cacheRead == 15)
    }

    @Test func openAIUsageParseAbsent() {
        let json = JSONValue.parse(#"{"choices":[]}"#)!
        #expect(OpenAICompatibleProvider.usage(from: json) == nil)
    }

    @Test func geminiUsageParse() {
        let json = JSONValue.parse(#"{"usageMetadata":{"promptTokenCount":50,"candidatesTokenCount":30,"cachedContentTokenCount":5}}"#)!
        let u = GeminiProvider.usage(from: json)
        #expect(u?.input == 50)
        #expect(u?.output == 30)
        #expect(u?.cacheRead == 5)
    }
}
