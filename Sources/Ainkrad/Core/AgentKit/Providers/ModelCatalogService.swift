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

    func models(kind: ProviderKind, baseURL: String, credential: ProviderCredential, curatedFallback: [String]) async -> [String] {
        await modelsResult(kind: kind, baseURL: baseURL, credential: credential, curatedFallback: curatedFallback).models
    }

    /// Same as `models(...)`, but also signals whether the returned list was
    /// genuinely fetched live (`isLive == true`) or is the curated fallback
    /// returned due to an invalid request, non-2xx response, transport error,
    /// or empty parse (`isLive == false`). Callers should only treat the list
    /// as authoritative (e.g. for reconciling a selected model) when `isLive`.
    func modelsResult(kind: ProviderKind, baseURL: String, credential: ProviderCredential, curatedFallback: [String]) async -> (models: [String], isLive: Bool) {
        guard let request = Self.listRequest(kind: kind, baseURL: baseURL, credential: credential) else {
            return (curatedFallback, false)
        }
        do {
            let (data, response) = try await http.data(for: request)
            guard (200...299).contains(response.statusCode) else { return (curatedFallback, false) }
            // A well-formed response is authoritative even when it lists zero models
            // (the provider genuinely has none) — return it live so callers show the
            // real (possibly empty) set rather than the curated fallback. Only a
            // parse failure (nil) falls back to curated.
            guard let parsed = Self.parseModels(kind: kind, data: data) else { return (curatedFallback, false) }
            return (parsed, true)
        } catch {
            return (curatedFallback, false)
        }
    }

    func test(kind: ProviderKind, baseURL: String, credential: ProviderCredential) async -> ConnectionTestResult {
        guard let request = Self.listRequest(kind: kind, baseURL: baseURL, credential: credential) else {
            return ConnectionTestResult(ok: false, message: "Invalid base URL")
        }
        do {
            let (data, response) = try await http.data(for: request)
            if (200...299).contains(response.statusCode) {
                let count = (Self.parseModels(kind: kind, data: data) ?? []).count
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

    /// Builds the `/models` discovery request. Auth depends on BOTH the provider
    /// kind and the credential: a subscription (`.oauth`) connection is keyless, so
    /// it authenticates with `authorization: Bearer <token>` — the same header the
    /// live `/v1/messages` OAuth path uses — NOT an (empty) `x-api-key`, which would
    /// 401 and silently drop discovery back to the curated fallback.
    private static func listRequest(kind: ProviderKind, baseURL: String, credential: ProviderCredential) -> URLRequest? {
        let base = trim(baseURL)
        guard let url = URL(string: base + "/models") else { return nil }
        var r = URLRequest(url: url)
        switch kind {
        case .openAICompatible:
            switch credential {
            case .apiKey(let key): if !key.isEmpty { r.setValue("Bearer \(key)", forHTTPHeaderField: "authorization") }
            case .oauth(let token): r.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "authorization")
            }
        case .claude:
            r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            switch credential {
            case .apiKey(let key): r.setValue(key, forHTTPHeaderField: "x-api-key")
            case .oauth(let token): r.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "authorization")
            }
        case .gemini:
            switch credential {
            case .apiKey(let key): r.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            case .oauth(let token): r.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "authorization")
            }
        }
        return r
    }

    /// Returns `nil` when the body couldn't be parsed at all (unexpected shape),
    /// distinguished from a well-formed response that genuinely lists zero models
    /// (`[]`). Callers use that difference to decide between a curated fallback
    /// (parse failure — we don't know) and an authoritative empty list (the
    /// provider really has no models, e.g. an Ollama with nothing pulled).
    private static func parseModels(kind: ProviderKind, data: Data) -> [String]? {
        switch kind {
        case .openAICompatible, .claude:
            struct List: Decodable { struct Item: Decodable { let id: String }; let data: [Item]? }
            guard let list = try? JSONDecoder().decode(List.self, from: data) else { return nil }
            return list.data?.map(\.id) ?? []
        case .gemini:
            struct List: Decodable { struct Item: Decodable { let name: String }; let models: [Item]? }
            guard let list = try? JSONDecoder().decode(List.self, from: data) else { return nil }
            return list.models?.map {
                $0.name.hasPrefix("models/") ? String($0.name.dropFirst("models/".count)) : $0.name
            } ?? []
        }
    }

    private static func errorMessage(data: Data) -> String? {
        struct Envelope: Decodable { struct E: Decodable { let message: String? }; let error: E? }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.error?.message
    }
}
