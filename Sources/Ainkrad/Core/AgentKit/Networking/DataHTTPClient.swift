// Sources/Ainkrad/Core/AgentKit/Networking/DataHTTPClient.swift
import Foundation

/// A plain (non-streaming) request used for model discovery and connection
/// health checks. Separate from `StreamingHTTPClient` (which is POST/SSE only).
protocol DataHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionDataHTTPClient: DataHTTPClient {
    var session: URLSession = .shared
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
