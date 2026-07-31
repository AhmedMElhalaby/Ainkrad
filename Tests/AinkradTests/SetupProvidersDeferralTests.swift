import Foundation
import Testing
@testable import Ainkrad
import AinkradHostRuntime

/// The escape hatch, and the debt it records.
///
/// Split from `SetupProvidersStepTests` for size, not for topic: these are the
/// tests for "a transient upstream failure must not lock the user out of the
/// app", including the two ways that trap was reachable after the first fix —
/// one launch later, and after a subsequent mistake.
@Suite("Setup providers deferral")
@MainActor
struct SetupProvidersDeferralTests {
    private static func oauthToken(_ access: String) -> OAuthToken {
        OAuthToken(accessToken: access, refreshToken: "refresh-secret-value",
                   expiresAt: Date().addingTimeInterval(3600), scopes: ["user:inference"])
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

    // MARK: - The escape must survive the launch it causes (review finding 1)

    /// The trap, one launch later: defer on a 429, relaunch after the provider
    /// recovered, and the escape must still be there. Otherwise the user has to
    /// reproduce a transient upstream failure to get past a step they have
    /// already been permitted to postpone — and `.providers` is `steps[0]`, so
    /// Back is absent and the overlay is non-dismissible.
    @Test func arecordedDeferralStillOffersTheEscapeOnAFreshCoordinator() {
        let store = InMemoryPersistenceStore()
        let first = SetupCoordinator(persistence: store, isProvisionalHome: true)
        first.setDeferred(.providers, true)
        first.complete()

        let relaunched = SetupCoordinator(persistence: store, isProvisionalHome: false)
        #expect(relaunched.steps == [.providers, .done])
        #expect(!relaunched.canGoBack, "the deferred step is first, so Back is not a way out")
        // The view reads exactly this to keep "Set this up later" on screen.
        #expect(relaunched.deferredSteps.contains(.providers))
    }

    /// The escape, once earned, is not confiscated by a later mistake: an OAuth
    /// 429 offers it, and a subsequently mistyped API key returning 401 must not
    /// take it away.
    @Test func theEscapeIsLatchedNotRecomputed() {
        // The view latches on any `allowsDeferral` verdict and never clears it
        // except on a successful connection; these are the two verdicts involved.
        let transient = SetupProviders.Outcome.failed(message: "rate limited",
                                                     failure: .rateLimited(status: 429))
        let blocking = SetupProviders.Outcome.failed(message: "bad key",
                                                    failure: .unauthorized(status: 401))
        var escapeEarned = false
        for outcome in [transient, blocking] where outcome.canDefer { escapeEarned = true }
        #expect(escapeEarned, "a blocking failure after a deferrable one must not erase the offer")
    }

    /// Deferring during a RE-RAISED session must survive a quit before Finish:
    /// the marker already exists there, so the record is written through.
    @Test func deferringWritesThroughOnceAMarkerExists() {
        let store = InMemoryPersistenceStore()
        let first = SetupCoordinator(persistence: store, isProvisionalHome: true)
        first.complete()
        #expect(store.load(SetupDocument.self)?.deferredSteps == [String]())

        let returning = SetupCoordinator(persistence: store, isProvisionalHome: false)
        returning.setDeferred(.providers, true)   // ...and the user quits here

        #expect(store.load(SetupDocument.self)?.deferredSteps == ["providers"])
        #expect(store.load(SetupDocument.self)?.completedAt != nil,
                "the existing completedAt is carried, never re-minted")
        #expect(!SetupCoordinator(persistence: store, isProvisionalHome: false).isComplete)
    }

    /// During a FIRST run there is no marker, so nothing is written — quitting
    /// mid-wizard must replay the whole wizard, not record a completed setup.
    @Test func deferringBeforeAnyMarkerExistsWritesNothing() {
        let store = InMemoryPersistenceStore()
        let c = SetupCoordinator(persistence: store, isProvisionalHome: true)
        c.setDeferred(.providers, true)
        #expect(store.load(SetupDocument.self) == nil)
        #expect(SetupCoordinator(persistence: store, isProvisionalHome: true).steps == SetupStep.allCases)
    }

    /// A user who defers, then connects a provider through Settings, must not be
    /// asked to re-enter the key from scratch at the next launch — while the gate
    /// is up, Settings is unreachable, so there is no way to point at it.
    @Test func anExistingVerifiedConnectionSatisfiesTheReRaisedStep() {
        let t = TestHome.make("prov14")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        let existing = env.connectionStore.addConnection(
            preset: ProviderPreset.preset(id: "openai"), displayName: "OpenAI",
            baseURL: "https://example.invalid/v1", token: "sk-test", authMode: .apiKey)
        env.agentConfigStore.setActiveConnectionID(existing.id)

        // What the step's `adoptExistingConnection` reads.
        let active = env.agentConfigStore.activeConnectionID
            .flatMap { id in env.connectionStore.connections.first { $0.id == id } }
        #expect(active?.id == existing.id)

        // ...and it is not swept away as an abandoned attempt.
        let removed = SetupProviders.cleanUpAbandonedSubscriptions(
            connections: env.connectionStore, agentConfig: env.agentConfigStore,
            oauth: env.oauthStore)
        #expect(removed == 0)
        #expect(env.agentConfigStore.activeConnectionID == existing.id)

        // Recognising it clears the debt.
        let c = SetupCoordinator(persistence: env.persistence, isProvisionalHome: false)
        c.setDeferred(.providers, true)
        c.setDeferred(.providers, false)
        c.complete()
        #expect(c.isComplete)
    }

    /// 404 reaches the escape through the same path as a 429.
    @Test func afourOhFourOffersTheEscape() async {
        let t = TestHome.make("prov15")
        defer { t.cleanup() }
        let env = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)

        let outcome = await SetupProviders.connect(
            preset: ProviderPreset.preset(id: "ollama"), token: "",
            baseURL: ProviderPreset.preset(id: "ollama").defaultBaseURL,
            connections: env.connectionStore, agentConfig: env.agentConfigStore,
            verify: { _, _, _ in
                ConnectionTestResult(ok: false, message: "HTTP 404", failure: .notFound(status: 404))
            })
        #expect(outcome.canDefer)
        #expect(env.connectionStore.connections.isEmpty)
    }
}
