import Foundation

protocol HTTPClient {
    func get(_ url: URL) async throws -> Data
}

enum HTTPError: Error, Equatable { case status(Int) }

/// Production HTTP client. Sends a User-Agent (GitHub's API returns 403 without
/// one) and treats non-2xx as an error.
struct URLSessionHTTPClient: HTTPClient {
    var session: URLSession = .shared
    func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Ainkrad", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // App Store fetches (catalog, downloads) must reflect the latest
        // published state, not a stale URLCache entry — a "refresh" that returns
        // a cached catalog would hide a just-shipped plugin update. Bypass the
        // local HTTP cache so refresh always hits the network. (The CDN in front
        // of the catalog still has its own propagation delay, out of our hands.)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw HTTPError.status(http.statusCode)
        }
        return data
    }
}
