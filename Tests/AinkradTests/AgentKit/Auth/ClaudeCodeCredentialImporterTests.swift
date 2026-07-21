import Testing
import Foundation
@testable import Ainkrad

@Suite struct ClaudeCodeCredentialImporterTests {
    private func payload(scopes: [String], expiresAt: Int) -> Data {
        let scopeJSON = scopes.map { "\"\($0)\"" }.joined(separator: ",")
        return """
        {"claudeAiOauth":{"accessToken":"AT","refreshToken":"RT",
         "expiresAt":\(expiresAt),"scopes":[\(scopeJSON)]}}
        """.data(using: .utf8)!
    }

    @Test func decodesValidCredentials() throws {
        let token = try ClaudeCodeCredentialImporter.decode(payload(scopes: ["user:inference"], expiresAt: 5000))
        #expect(token.accessToken == "AT")
        #expect(token.refreshToken == "RT")
        #expect(token.expiresAt == Date(timeIntervalSince1970: 5))   // ms → s
    }

    @Test func rejectsWhenInferenceScopeMissing() {
        #expect(throws: ImportError.missingInferenceScope) {
            _ = try ClaudeCodeCredentialImporter.decode(payload(scopes: ["user:profile"], expiresAt: 5000))
        }
    }

    @Test func rejectsMalformed() {
        #expect(throws: ImportError.malformed) {
            _ = try ClaudeCodeCredentialImporter.decode(Data("{}".utf8))
        }
    }
}
