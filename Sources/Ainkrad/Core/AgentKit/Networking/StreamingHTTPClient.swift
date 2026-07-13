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
        // Forward the response as RAW bytes, one Data per newline-terminated
        // line. We must NOT use `bytes.lines` here: `AsyncBytes.lines` drops
        // the empty lines that delimit SSE events (`\n\n`), so downstream the
        // boundaries would be lost and every `data:` line would accumulate
        // into a single undecodable blob. `SSEParser` owns all line/boundary
        // parsing — it needs the blank lines preserved, so we hand it the raw
        // byte stream verbatim (including the empty-line separators).
        return AsyncThrowingStream { cont in
            let task = Task {
                do {
                    var buffer = [UInt8]()
                    let newline = UInt8(ascii: "\n")
                    for try await byte in bytes {
                        buffer.append(byte)
                        if byte == newline {
                            cont.yield(Data(buffer))
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty { cont.yield(Data(buffer)) }
                    cont.finish()
                } catch { cont.finish(throwing: error) }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}
