import Foundation

/// A resolved credential handed to an `LLMProvider` at send time. A subscription
/// bearer token is NOT an API key — the provider branches on this to pick the auth
/// header and the request shaping the subscription backend requires.
enum ProviderCredential: Equatable, Sendable {
    case apiKey(String)
    case oauth(OAuthToken)
}

/// A subscription OAuth token. Values live in the Keychain; this struct is the
/// in-memory shape and the JSON blob written under `connection.<id>.oauth`.
struct OAuthToken: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var scopes: [String]

    /// True when the token is at or past `expiresAt - skew` relative to `now`.
    func isExpiring(now: Date = Date(), skew: TimeInterval = 120) -> Bool {
        now.addingTimeInterval(skew) >= expiresAt
    }
}
