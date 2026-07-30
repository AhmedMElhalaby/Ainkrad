import Foundation
import Testing
@testable import Ainkrad

@Suite("Setup providers step")
@MainActor
struct SetupProvidersStepTests {
    private static func oauthToken(_ access: String) -> OAuthToken {
        OAuthToken(accessToken: access, refreshToken: "refresh-secret-value",
                   expiresAt: Date().addingTimeInterval(3600), scopes: ["user:inference"])
    }

    @Test func averifiedConnectionIsSavedAndMadeActive() async {
        let t = TestHome.make("prov")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        let outcome = await SetupProviders.connect(
            preset: ProviderPreset.preset(id: "openai"),
            token: "sk-test",
            baseURL: "https://example.invalid/v1",
            connections: env.connectionStore,
            agentConfig: env.agentConfigStore,
            verify: { _, _, _ in ConnectionTestResult(ok: true, message: "Connected · 12 models") })

        #expect(outcome == .connected(message: "Connected · 12 models"))
        #expect(env.connectionStore.connections.count == 1)
        #expect(env.agentConfigStore.activeConnectionID == env.connectionStore.connections.first?.id)
    }

    /// A failed probe must leave NO connection behind — otherwise the user lands
    /// in the workspace with a broken provider that looks configured.
    @Test func afailedVerificationSavesNothing() async {
        let t = TestHome.make("prov2")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        let outcome = await SetupProviders.connect(
            preset: ProviderPreset.preset(id: "openai"),
            token: "bad",
            baseURL: "https://example.invalid/v1",
            connections: env.connectionStore,
            agentConfig: env.agentConfigStore,
            verify: { _, _, _ in ConnectionTestResult(ok: false, message: "HTTP 401") })

        #expect(outcome == .failed(message: "HTTP 401"))
        #expect(env.connectionStore.connections.isEmpty)
        #expect(env.agentConfigStore.activeConnectionID == nil)
    }

    @Test func theErrorMessageNeverContainsTheToken() async {
        let t = TestHome.make("prov3")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        let secret = "sk-super-secret-value"

        let outcome = await SetupProviders.connect(
            preset: ProviderPreset.preset(id: "openai"), token: secret,
            baseURL: "https://example.invalid/v1",
            connections: env.connectionStore, agentConfig: env.agentConfigStore,
            verify: { _, _, _ in ConnectionTestResult(ok: false, message: "HTTP 401") })

        if case .failed(let message) = outcome {
            #expect(!message.contains(secret))
        } else {
            Issue.record("expected .failed")
        }
    }

    /// Ollama has `requiresKey: false`. A keyless preset must reach the probe
    /// with an empty credential and connect — not be blocked by a key field it
    /// can never satisfy.
    @Test func akeylessPresetConnectsWithoutAToken() async {
        let t = TestHome.make("prov4")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        let ollama = ProviderPreset.preset(id: "ollama")
        #expect(ollama.requiresKey == false)

        var probed = false
        let outcome = await SetupProviders.connect(
            preset: ollama, token: "", baseURL: ollama.defaultBaseURL,
            connections: env.connectionStore, agentConfig: env.agentConfigStore,
            verify: { _, _, _ in probed = true; return ConnectionTestResult(ok: true, message: "Connected · 3 models") })

        #expect(probed)
        #expect(outcome == .connected(message: "Connected · 3 models"))
        #expect(env.connectionStore.connections.count == 1)
        #expect(env.agentConfigStore.activeConnectionID == env.connectionStore.connections.first?.id)
    }

    /// The subscription route signs in against a connection that must exist
    /// first, so it can only verify AFTER creating one. If the probe fails, the
    /// rollback must leave the same clean slate as the API-key route.
    @Test func afailedSubscriptionVerificationRollsBackTheConnection() async {
        let t = TestHome.make("prov5")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        let outcome = await SetupProviders.finishSubscription(
            connection: env.connectionStore.addConnection(
                preset: ProviderPreset.preset(id: "claude"),
                displayName: "Claude", baseURL: "https://example.invalid/v1",
                token: "", authMode: .subscription),
            credential: .oauth(Self.oauthToken("oauth-secret-value")),
            connections: env.connectionStore,
            agentConfig: env.agentConfigStore,
            oauth: env.oauthStore,
            verify: { _, _, _ in ConnectionTestResult(ok: false, message: "HTTP 401") })

        #expect(outcome == .failed(message: "HTTP 401"))
        #expect(env.connectionStore.connections.isEmpty)
        #expect(env.agentConfigStore.activeConnectionID == nil)
    }

    @Test func averifiedSubscriptionConnectionIsMadeActive() async {
        let t = TestHome.make("prov6")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        let created = env.connectionStore.addConnection(
            preset: ProviderPreset.preset(id: "claude"),
            displayName: "Claude", baseURL: "https://example.invalid/v1",
            token: "", authMode: .subscription)

        let outcome = await SetupProviders.finishSubscription(
            connection: created, credential: .oauth(Self.oauthToken("oauth-secret-value")),
            connections: env.connectionStore, agentConfig: env.agentConfigStore,
            oauth: env.oauthStore,
            verify: { _, _, _ in ConnectionTestResult(ok: true, message: "Connected · 4 models") })

        #expect(outcome == .connected(message: "Connected · 4 models"))
        #expect(env.connectionStore.connections.count == 1)
        #expect(env.agentConfigStore.activeConnectionID == created.id)
    }
}
