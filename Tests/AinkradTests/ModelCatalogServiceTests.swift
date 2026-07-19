// Tests/AinkradTests/ModelCatalogServiceTests.swift
import Testing
import Foundation
@testable import Ainkrad

@MainActor
@Suite("ModelCatalogService")
struct ModelCatalogServiceTests {
    struct StubDataHTTPClient: DataHTTPClient {
        let status: Int
        let body: String
        let captured: (@Sendable (URLRequest) -> Void)?
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            captured?(request)
            let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), resp)
        }
    }

    @Test("parses OpenAI-compatible /models list")
    func openAIList() async throws {
        let stub = StubDataHTTPClient(status: 200,
            body: "{\"data\":[{\"id\":\"gpt-5\"},{\"id\":\"gpt-5-mini\"}]}", captured: nil)
        let svc = ModelCatalogService(http: stub)
        let models = await svc.models(kind: .openAICompatible, baseURL: "https://api.openai.com/v1", apiKey: "k", curatedFallback: ["fallback"])
        #expect(models == ["gpt-5", "gpt-5-mini"])
    }

    @Test("parses Gemini models list and strips the models/ prefix")
    func geminiList() async throws {
        let stub = StubDataHTTPClient(status: 200,
            body: "{\"models\":[{\"name\":\"models/gemini-2.5-pro\"}]}", captured: nil)
        let svc = ModelCatalogService(http: stub)
        let models = await svc.models(kind: .gemini, baseURL: "https://x/v1beta", apiKey: "k", curatedFallback: [])
        #expect(models == ["gemini-2.5-pro"])
    }

    @Test("falls back to curated list on failure")
    func fallback() async throws {
        let stub = StubDataHTTPClient(status: 500, body: "boom", captured: nil)
        let svc = ModelCatalogService(http: stub)
        let models = await svc.models(kind: .openAICompatible, baseURL: "https://x/v1", apiKey: "k", curatedFallback: ["a", "b"])
        #expect(models == ["a", "b"])
    }

    @Test("modelsResult signals isLive == false on a 500 fallback")
    func modelsResultFallbackIsNotLive() async throws {
        let stub = StubDataHTTPClient(status: 500, body: "boom", captured: nil)
        let svc = ModelCatalogService(http: stub)
        let result = await svc.modelsResult(kind: .openAICompatible, baseURL: "https://x/v1", apiKey: "k", curatedFallback: ["a", "b"])
        #expect(result.models == ["a", "b"])
        #expect(result.isLive == false)
    }

    @Test("a well-formed but EMPTY list is authoritative (live, no curated fallback)")
    func modelsResultEmptyListIsAuthoritative() async throws {
        // e.g. an Ollama with nothing pulled: `{"data":[]}` means the provider
        // genuinely has zero models — show that, NOT the hardcoded curated list.
        let stub = StubDataHTTPClient(status: 200, body: "{\"data\":[]}", captured: nil)
        let svc = ModelCatalogService(http: stub)
        let result = await svc.modelsResult(kind: .openAICompatible, baseURL: "https://x/v1", apiKey: "k", curatedFallback: ["llama3.2", "qwen2.5-coder"])
        #expect(result.models == [])       // NOT the curated fallback
        #expect(result.isLive == true)     // authoritative
    }

    @Test("an UNPARSEABLE 200 body falls back to curated (isLive == false)")
    func modelsResultUnparseableFallsBackToCurated() async throws {
        // A 2xx whose body we can't decode at all — we don't know the real set,
        // so the curated fallback is the honest choice (distinct from empty).
        let stub = StubDataHTTPClient(status: 200, body: "not json at all", captured: nil)
        let svc = ModelCatalogService(http: stub)
        let result = await svc.modelsResult(kind: .openAICompatible, baseURL: "https://x/v1", apiKey: "k", curatedFallback: ["a", "b"])
        #expect(result.models == ["a", "b"])
        #expect(result.isLive == false)
    }

    @Test("modelsResult signals isLive == true on a successful fetch")
    func modelsResultLiveFetchIsLive() async throws {
        let stub = StubDataHTTPClient(status: 200,
            body: "{\"data\":[{\"id\":\"gpt-5\"},{\"id\":\"gpt-5-mini\"}]}", captured: nil)
        let svc = ModelCatalogService(http: stub)
        let result = await svc.modelsResult(kind: .openAICompatible, baseURL: "https://api.openai.com/v1", apiKey: "k", curatedFallback: ["fallback"])
        #expect(result.models == ["gpt-5", "gpt-5-mini"])
        #expect(result.isLive == true)
    }

    @Test("test() returns ok on 200")
    func testOK() async throws {
        let stub = StubDataHTTPClient(status: 200, body: "{\"data\":[{\"id\":\"m\"}]}", captured: nil)
        let svc = ModelCatalogService(http: stub)
        #expect(await svc.test(kind: .openAICompatible, baseURL: "https://x/v1", apiKey: "k").ok == true)
    }

    @Test("test() failure never leaks the key")
    func testFailRedaction() async throws {
        let stub = StubDataHTTPClient(status: 401, body: "{\"error\":{\"message\":\"unauthorized\"}}", captured: nil)
        let svc = ModelCatalogService(http: stub)
        let result = await svc.test(kind: .openAICompatible, baseURL: "https://x/v1", apiKey: "sk-secret")
        #expect(result.ok == false)
        #expect(!result.message.contains("sk-secret"))
    }
}
