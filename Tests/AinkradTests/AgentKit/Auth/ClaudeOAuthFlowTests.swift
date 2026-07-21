import Testing
import Foundation
@testable import Ainkrad

private final class StubTransport: OAuthTokenTransport, @unchecked Sendable {
    var responses: [(Data, Int)] = []
    private(set) var requests: [URLRequest] = []
    func post(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (data, status) = responses.removeFirst()
        let resp = HTTPURLResponse(url: request.url!, statusCode: status,
                                   httpVersion: nil, headerFields: nil)!
        return (data, resp)
    }
}

@Suite struct ClaudeOAuthFlowTests {
    @Test func pkceChallengeIsS256OfVerifier() {
        let pkce = PKCE.generate()
        #expect(!pkce.verifier.isEmpty)
        #expect(!pkce.challenge.contains("="))   // base64url, no padding
        #expect(!pkce.challenge.contains("+"))
        #expect(!pkce.challenge.contains("/"))
    }

    @Test func authorizeURLCarriesRequiredParams() {
        let url = ClaudeOAuthFlow.authorizeURL(state: "STATE", challenge: "CHAL")
        let s = url.absoluteString
        #expect(url.host == "claude.ai")
        #expect(s.contains("code=true"))
        #expect(s.contains("client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e"))
        #expect(s.contains("code_challenge=CHAL"))
        #expect(s.contains("code_challenge_method=S256"))
        #expect(s.contains("state=STATE"))
        #expect(s.contains("redirect_uri=http%3A%2F%2Flocalhost%3A53692%2Fcallback"))
    }

    @Test(.timeLimit(.minutes(1))) func exchangeParsesTokenAndSendsClaudeCodeUA() async throws {
        let body = """
        {"access_token":"AT","refresh_token":"RT","expires_in":3600}
        """.data(using: .utf8)!
        let stub = StubTransport(); stub.responses = [(body, 200)]
        let flow = ClaudeOAuthFlow(transport: stub, clientVersion: "2.1.74")
        let token = try await flow.exchange(code: "C", verifier: "V", state: "S")
        #expect(token.accessToken == "AT")
        #expect(token.refreshToken == "RT")
        let ua = stub.requests[0].value(forHTTPHeaderField: "user-agent")
        #expect(ua == "claude-code/2.1.74")
        #expect(stub.requests[0].value(forHTTPHeaderField: "content-type") == "application/json")
    }

    @Test(.timeLimit(.minutes(1))) func exchangeFallsBackToSecondEndpointOn4xx() async throws {
        let ok = """
        {"access_token":"AT","refresh_token":"RT","expires_in":10}
        """.data(using: .utf8)!
        let stub = StubTransport()
        stub.responses = [(Data("nope".utf8), 404), (ok, 200)]
        let flow = ClaudeOAuthFlow(transport: stub, clientVersion: "2.1.74")
        let token = try await flow.exchange(code: "C", verifier: "V", state: "S")
        #expect(token.accessToken == "AT")
        #expect(stub.requests[0].url?.host == "platform.claude.com")
        #expect(stub.requests[1].url?.host == "console.anthropic.com")
    }

    @Test(.timeLimit(.minutes(1))) func refreshKeepsOldRefreshTokenWhenResponseOmitsIt() async throws {
        let body = """
        {"access_token":"AT2","expires_in":3600}
        """.data(using: .utf8)!
        let stub = StubTransport(); stub.responses = [(body, 200)]
        let flow = ClaudeOAuthFlow(transport: stub, clientVersion: "2.1.74")
        let token = try await flow.refresh(refreshToken: "OLD")
        #expect(token.accessToken == "AT2")
        #expect(token.refreshToken == "OLD")   // rotated token absent → keep old
    }
}
