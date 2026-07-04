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
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw HTTPError.status(http.statusCode)
        }
        return data
    }
}
