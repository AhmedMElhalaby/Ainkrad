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

    // MARK: - Deferring a transient failure (task 8)

    /// The rule: whose fault is it? A rejected credential is the user's to fix,
    /// and fixing it is the point of the step — so no escape is offered.
    @Test func ablockingFailureOffersNoEscape() async {
        let t = TestHome.make("prov11")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        for failure: ConnectionFailure in [.unauthorized(status: 401),
                                           .unauthorized(status: 403),
                                           .rejected(status: 400),
                                           .invalidBaseURL] {
            let outcome = await SetupProviders.connect(
                preset: ProviderPreset.preset(id: "openai"), token: "bad",
                baseURL: "https://example.invalid/v1",
                connections: env.connectionStore, agentConfig: env.agentConfigStore,
                verify: { _, _, _ in ConnectionTestResult(ok: false, message: "nope", failure: failure) })
            #expect(outcome.canDefer == false, "\(failure) is the user's to fix and must block")
        }
        #expect(env.connectionStore.connections.isEmpty)
    }

    /// A 429, a 5xx or an unreachable endpoint is not the user's to fix. Blocking
    /// them locks the app over a transient upstream failure — this is the exact
    /// trap the escape exists for.
    @Test func atransientFailureOffersTheEscape() async {
        let t = TestHome.make("prov12")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        for failure: ConnectionFailure in [.rateLimited(status: 429),
                                           .serverError(status: 500),
                                           .serverError(status: 503),
                                           .unreachable] {
            let outcome = await SetupProviders.connect(
                preset: ProviderPreset.preset(id: "openai"), token: "sk-fine",
                baseURL: "https://example.invalid/v1",
                connections: env.connectionStore, agentConfig: env.agentConfigStore,
                verify: { _, _, _ in ConnectionTestResult(ok: false, message: "later", failure: failure) })
            #expect(outcome.canDefer, "\(failure) is not the user's to fix and must offer an escape")
        }
        // Verify-before-save still holds through every one of those attempts.
        #expect(env.connectionStore.connections.isEmpty)
        #expect(env.agentConfigStore.activeConnectionID == nil)
    }

    /// The escape is decided from the classification, never from the message —
    /// identical copy, opposite verdicts.
    @Test func theEscapeIsNotDecidedByTheDisplayMessage() {
        let sameCopy = "Rate limited. Please try again later."
        let blocked = SetupProviders.Outcome.failed(message: sameCopy,
                                                    failure: .unauthorized(status: 401))
        let escapable = SetupProviders.Outcome.failed(message: sameCopy,
                                                     failure: .rateLimited(status: 429))
        #expect(!blocked.canDefer)
        #expect(escapable.canDefer)
    }

    /// The one that matters: deferring must record the step as STILL OWED, so a
    /// later launch re-raises the gate on it rather than treating setup as done.
    @Test func adeferredProvidersStepIsRecordedAsStillOwed() {
        let store = InMemoryPersistenceStore()
        let c = SetupCoordinator(persistence: store, isProvisionalHome: true)
        c.setDeferred(.providers, true)
        c.complete()

        #expect(store.load(SetupDocument.self)?.completedAt != nil,
                "setup DID finish — the user must not be walked through the whole wizard again")
        #expect(store.load(SetupDocument.self)?.deferredSteps == ["providers"])
        #expect(!c.isComplete, "a deferred step means setup is not complete")

        // A later launch.
        let next = SetupCoordinator(persistence: store, isProvisionalHome: false)
        #expect(!next.isComplete)
        #expect(SetupGate.raisedAtLaunch(provisionalHome: false, setupIsComplete: next.isComplete))
        #expect(next.steps == [.providers, .done],
                "the gate must re-raise on the deferred step alone, not replay the wizard")
        #expect(next.step == .providers)
        #expect(next.deferredSteps == [.providers])
    }

    /// "Set this up later" must not leave a broken connection behind either —
    /// verify-before-save covers the failed probe, and the deferral path adds
    /// nothing of its own.
    @Test func adeferredSetupWritesNoConnection() async {
        let t = TestHome.make("prov13")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        let outcome = await SetupProviders.connect(
            preset: ProviderPreset.preset(id: "openai"), token: "sk-fine",
            baseURL: "https://example.invalid/v1",
            connections: env.connectionStore, agentConfig: env.agentConfigStore,
            verify: { _, _, _ in
                ConnectionTestResult(ok: false, message: "Rate limited",
                                     failure: .rateLimited(status: 429))
            })
        #expect(outcome.canDefer)

        let c = SetupCoordinator(persistence: env.persistence, isProvisionalHome: true)
        c.setDeferred(.providers, true)
        c.complete()

        #expect(env.connectionStore.connections.isEmpty)
        #expect(env.agentConfigStore.activeConnectionID == nil)
    }

    /// Coming back through the workspace banner and connecting must STOP the
    /// step being owed — otherwise the gate greets the user forever.
    @Test func connectingLaterClearsTheDebt() {
        let store = InMemoryPersistenceStore()
        let first = SetupCoordinator(persistence: store, isProvisionalHome: true)
        first.setDeferred(.providers, true)
        first.complete()

        let returning = SetupCoordinator(persistence: store, isProvisionalHome: false)
        #expect(returning.steps == [.providers, .done])
        returning.setDeferred(.providers, false)   // a probe succeeded
        returning.complete()

        #expect(store.load(SetupDocument.self)?.deferredSteps == [String]())
        #expect(returning.isComplete)
        #expect(SetupCoordinator(persistence: store, isProvisionalHome: false).isComplete)
    }

    /// The OAuth route reaches the SAME enum from a different subsystem, so one
    /// predicate drives the escape for both routes.
    @Test func theOAuthRouteReachesTheSameClassification() {
        #expect(ClaudeOAuthLoginController.classify(
            ClaudeOAuthError.tokenEndpoint(status: 429, body: "{}")) == .rateLimited(status: 429))
        #expect(ClaudeOAuthLoginController.classify(
            ClaudeOAuthError.tokenEndpoint(status: 503, body: "{}")) == .serverError(status: 503))
        #expect(ClaudeOAuthLoginController.classify(
            ClaudeOAuthError.tokenEndpoint(status: 401, body: "{}")) == .unauthorized(status: 401))
        #expect(ClaudeOAuthLoginController.classify(
            ClaudeOAuthError.allEndpointsFailed) == .unreachable)
        // A mistyped paste is the user's to redo here and now — not a reason to
        // offer postponing the step.
        #expect(ClaudeOAuthLoginController.classify(LoopbackError.malformedCallback) == nil)
    }

    /// The bug that started this: Anthropic's raw JSON body rendered verbatim.
    @Test func theOAuthFailureCopyIsHumanReadableAndCarriesNoRawBody() {
        let body = "{\"error\":{\"type\":\"rate_limit_error\",\"message\":\"Rate limited. Please try again later.\"}}"
        let message = ClaudeOAuthLoginController.message(
            for: ClaudeOAuthError.tokenEndpoint(status: 429, body: body))

        #expect(!message.contains("rate_limit_error"))
        #expect(!message.contains("{"))
        #expect(!message.contains("429"))
        #expect(message.contains("temporary"))
        #expect(message.contains("API key"), "it must point at a route that still works")

        // A 5xx says it is temporary too; a 401 does not, because it is not.
        #expect(ClaudeOAuthLoginController.message(
            for: ClaudeOAuthError.tokenEndpoint(status: 500, body: body)).contains("temporary"))
        #expect(!ClaudeOAuthLoginController.message(
            for: ClaudeOAuthError.tokenEndpoint(status: 401, body: body)).contains("temporary"))
    }
}
