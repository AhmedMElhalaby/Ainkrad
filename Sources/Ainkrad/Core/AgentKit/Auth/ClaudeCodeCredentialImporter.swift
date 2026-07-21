import Foundation

enum ImportError: Error, Equatable { case fileAbsent, missingInferenceScope, malformed }

/// Reads the Claude Code CLI's own OAuth login from ~/.claude/.credentials.json.
/// File-based only: the Claude Code Keychain item is ACL-scoped to that binary and
/// is not readable here. The app is non-sandboxed, so the file read is permitted.
struct ClaudeCodeCredentialImporter {
    private let path: URL

    init(path: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")) {
        self.path = path
    }

    var isAvailable: Bool { FileManager.default.fileExists(atPath: path.path) }

    func load() throws -> OAuthToken {
        guard isAvailable else { throw ImportError.fileAbsent }
        let data = try Data(contentsOf: path)
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> OAuthToken {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let access = oauth["accessToken"] as? String,
              let refresh = oauth["refreshToken"] as? String else {
            throw ImportError.malformed
        }
        let scopes = (oauth["scopes"] as? [String]) ?? []
        guard scopes.contains("user:inference") else { throw ImportError.missingInferenceScope }
        // Claude Code stores expiresAt in milliseconds.
        let expiresMS = (oauth["expiresAt"] as? Double) ?? 0
        return OAuthToken(accessToken: access, refreshToken: refresh,
                          expiresAt: Date(timeIntervalSince1970: expiresMS / 1000),
                          scopes: scopes)
    }
}
