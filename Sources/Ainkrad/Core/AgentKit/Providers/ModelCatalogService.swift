// Sources/Ainkrad/Core/AgentKit/Providers/ModelCatalogService.swift
import Foundation

struct ConnectionTestResult: Equatable, Sendable {
    let ok: Bool
    let message: String   // user-facing; NEVER contains the API key
}

/// Fetches a provider's available model ids (live, with a curated fallback),
/// and doubles as a connection health check. All failures are reported with
/// the API key redacted.
@MainActor
final class ModelCatalogService {
    private let http: DataHTTPClient

    init(http: DataHTTPClient) {
        self.http = http
    }

    func models(kind: ProviderKind, baseURL: String, apiKey: String, curatedFallback: [String]) async -> [String] {
        await modelsResult(kind: kind, baseURL: baseURL, apiKey: apiKey, curatedFallback: curatedFallback).models
    }

    /// Same as `models(...)`, but also signals whether the returned list was
    /// genuinely fetched live (`isLive == true`) or is the curated fallback
    /// returned due to an invalid request, non-2xx response, transport error,
    /// or empty parse (`isLive == false`). Callers should only treat the list
    /// as authoritative (e.g. for reconciling a selected model) when `isLive`.
    func modelsResult(kind: ProviderKind, baseURL: String, apiKey: String, curatedFallback: [String]) async -> (models: [String], isLive: Bool) {
        guard let request = Self.listRequest(kind: kind, baseURL: baseURL, apiKey: apiKey) else {
            return (curatedFallback, false)
        }
        do {
            let (data, response) = try await http.data(for: request)
            guard (200...299).contains(response.statusCode) else { return (curatedFallback, false) }
            let parsed = Self.parseModels(kind: kind, data: data)
            return parsed.isEmpty ? (curatedFallback, false) : (parsed, true)
        } catch {
            return (curatedFallback, false)
        }
    }

    func test(kind: ProviderKind, baseURL: String, apiKey: String) async -> ConnectionTestResult {
        guard let request = Self.listRequest(kind: kind, baseURL: baseURL, apiKey: apiKey) else {
            return ConnectionTestResult(ok: false, message: "Invalid base URL")
        }
        do {
            let (data, response) = try await http.data(for: request)
            if (200...299).contains(response.statusCode) {
                let count = Self.parseModels(kind: kind, data: data).count
                return ConnectionTestResult(ok: true, message: count > 0 ? "Connected · \(count) models" : "Connected")
            }
            // Body is the server's response — never contains the request key —
            // but be defensive and only surface a parsed message field.
            let message = Self.errorMessage(data: data) ?? "HTTP \(response.statusCode)"
            return ConnectionTestResult(ok: false, message: message)
        } catch {
            return ConnectionTestResult(ok: false, message: "Could not reach endpoint")
        }
    }

    // MARK: - Request/parse per kind

    private static func trim(_ baseURL: String) -> String {
        baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
    }

    private static func listRequest(kind: ProviderKind, baseURL: String, apiKey: String) -> URLRequest? {
        let base = trim(baseURL)
        switch kind {
        case .openAICompatible:
            guard let url = URL(string: base + "/models") else { return nil }
            var r = URLRequest(url: url)
            if !apiKey.isEmpty { r.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization") }
            return r
        case .claude:
            guard let url = URL(string: base + "/models") else { return nil }
            var r = URLRequest(url: url)
            r.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            return r
        case .gemini:
            guard let url = URL(string: base + "/models") else { return nil }
            var r = URLRequest(url: url)
            r.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            return r
        }
    }

    private static func parseModels(kind: ProviderKind, data: Data) -> [String] {
        switch kind {
        case .openAICompatible, .claude:
            struct List: Decodable { struct Item: Decodable { let id: String }; let data: [Item]? }
            return (try? JSONDecoder().decode(List.self, from: data))?.data?.map(\.id) ?? []
        case .gemini:
            struct List: Decodable { struct Item: Decodable { let name: String }; let models: [Item]? }
            return (try? JSONDecoder().decode(List.self, from: data))?.models?.map {
                $0.name.hasPrefix("models/") ? String($0.name.dropFirst("models/".count)) : $0.name
            } ?? []
        }
    }

    private static func errorMessage(data: Data) -> String? {
        struct Envelope: Decodable { struct E: Decodable { let message: String? }; let error: E? }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.error?.message
    }
}
