import Foundation

/// A POST that yields the response body as a byte stream (for SSE).
protocol StreamingHTTPClient: Sendable {
    func post(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error>
}

enum StreamingHTTPError: Error, Equatable { case status(Int, body: String) }

struct URLSessionStreamingHTTPClient: StreamingHTTPClient {
    var session: URLSession = .shared

    func post(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> {
        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var body = ""
            for try await line in bytes.lines { body += line + "\n" }
            throw StreamingHTTPError.status(http.statusCode, body: body)
        }
        return AsyncThrowingStream { cont in
            let task = Task {
                do {
                    for try await line in bytes.lines { cont.yield(Data((line + "\n").utf8)) }
                    cont.finish()
                } catch { cont.finish(throwing: error) }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}
