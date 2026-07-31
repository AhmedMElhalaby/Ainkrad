import Foundation
import Testing
@testable import Ainkrad
import AinkradHostRuntime

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
            verify: { _, _, _ in ConnectionTestResult(ok: false, message: "HTTP 401", failure: .unauthorized(status: 401)) })

        #expect(outcome == .failed(message: "HTTP 401", failure: .unauthorized(status: 401)))
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
            verify: { _, _, _ in ConnectionTestResult(ok: false, message: "HTTP 401", failure: .unauthorized(status: 401)) })

        if case .failed(let message, _) = outcome {
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

        let doomed = env.connectionStore.addConnection(
            preset: ProviderPreset.preset(id: "claude"),
            displayName: "Claude", baseURL: "https://example.invalid/v1",
            token: "", authMode: .subscription)
        // Store the credential first, so signOut clearing the Keychain item and
        // the account entry is asserted for real rather than vacuously.
        env.oauthStore.store(Self.oauthToken("oauth-secret-value"), for: doomed.id, source: .freshLogin)
        #expect(env.oauthStore.account(for: doomed.id) != nil)

        let outcome = await SetupProviders.finishSubscription(
            connection: doomed,
            credential: .oauth(Self.oauthToken("oauth-secret-value")),
            connections: env.connectionStore,
            agentConfig: env.agentConfigStore,
            oauth: env.oauthStore,
            verify: { _, _, _ in ConnectionTestResult(ok: false, message: "HTTP 401", failure: .unauthorized(status: 401)) })

        #expect(outcome == .failed(message: "HTTP 401", failure: .unauthorized(status: 401)))
        #expect(env.connectionStore.connections.isEmpty)
        #expect(env.agentConfigStore.activeConnectionID == nil)
        #expect(env.oauthStore.account(for: doomed.id) == nil)
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

    // MARK: - Subscription flow lifecycle (finding 1)

    /// A mistyped code is the exact case the paste fallback exists for. After a
    /// failed paste the flow must still be usable: the connection stays pending
    /// so the SECOND paste is a real retry, not a silently dead button.
    @Test func afailedPasteLeavesTheRouteRetryable() {
        let t = TestHome.make("prov7")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        let flow = SetupSubscriptionFlow()

        let first = flow.connection(connections: env.connectionStore)
        flow.needsPaste()
        #expect(flow.awaitingPaste)

        // A paste that the controller rejected (bad code).
        flow.attemptFailed(duringPaste: true, connections: env.connectionStore,
                           agentConfig: env.agentConfigStore, oauth: env.oauthStore)

        // The paste field is still shown AND still has something to paste against.
        #expect(flow.awaitingPaste)
        #expect(flow.pending?.id == first.id)
        // A second attempt reuses the same connection — no orphan, no dead button.
        #expect(flow.connection(connections: env.connectionStore).id == first.id)
        #expect(env.connectionStore.connections.count == 1)
    }

    /// The invariant that makes the above safe: if the paste field is on screen,
    /// a connection to paste against exists. A non-paste failure tears BOTH down
    /// together, returning the user to the sign-in button rather than to a paste
    /// field that can never succeed.
    @Test func anonPasteFailureTearsDownTheWholeFlow() {
        let t = TestHome.make("prov8")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        let flow = SetupSubscriptionFlow()

        let created = flow.connection(connections: env.connectionStore)
        env.oauthStore.store(Self.oauthToken("oauth-secret-value"), for: created.id, source: .freshLogin)
        flow.needsPaste()

        flow.attemptFailed(duringPaste: false, connections: env.connectionStore,
                           agentConfig: env.agentConfigStore, oauth: env.oauthStore)

        #expect(!flow.awaitingPaste)
        #expect(flow.pending == nil)
        #expect(env.connectionStore.connections.isEmpty)
        #expect(env.oauthStore.account(for: created.id) == nil)
        #expect(env.agentConfigStore.activeConnectionID == nil)
    }

    // MARK: - Abandoned attempts (finding 2)

    /// Quitting during the 300-second loopback wait leaves an unverified keyless
    /// connection on disk. Next entry to the step must clear it.
    @Test func anabandonedSubscriptionIsCleanedUpOnNextEntry() {
        let t = TestHome.make("prov9")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        _ = SetupSubscriptionFlow().connection(connections: env.connectionStore)
        #expect(env.connectionStore.connections.count == 1)

        let removed = SetupProviders.cleanUpAbandonedSubscriptions(
            connections: env.connectionStore, agentConfig: env.agentConfigStore,
            oauth: env.oauthStore)

        #expect(removed == 1)
        #expect(env.connectionStore.connections.isEmpty)
    }

    /// The cleanup predicate is narrow on purpose: a signed-in or active
    /// connection has passed a probe and must never be swept away.
    @Test func acleanupSparesSignedInAndActiveConnections() {
        let t = TestHome.make("prov10")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        let claude = ProviderPreset.preset(id: "claude")

        let signedIn = env.connectionStore.addConnection(
            preset: claude, displayName: "Claude", baseURL: claude.defaultBaseURL,
            token: "", authMode: .subscription)
        env.oauthStore.store(Self.oauthToken("oauth-secret-value"), for: signedIn.id, source: .freshLogin)

        let apiKey = env.connectionStore.addConnection(
            preset: ProviderPreset.preset(id: "openai"), displayName: "OpenAI",
            baseURL: "https://example.invalid/v1", token: "sk-test", authMode: .apiKey)
        env.agentConfigStore.setActiveConnectionID(apiKey.id)

        let removed = SetupProviders.cleanUpAbandonedSubscriptions(
            connections: env.connectionStore, agentConfig: env.agentConfigStore,
            oauth: env.oauthStore)

        #expect(removed == 0)
        #expect(env.connectionStore.connections.count == 2)
        #expect(env.agentConfigStore.activeConnectionID == apiKey.id)
    }
}
