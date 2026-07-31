import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The Providers step — the one step the user cannot pass without a working AI
/// connection. Continue is enabled only after a probe returned ok.
///
/// Three routes, all of which reach the same probe:
/// 1. Import an existing Claude Code login (shown only when the importer says a
///    login exists; the check is prompt-free).
/// 2. Sign in with Claude (loopback OAuth, paste fallback when the port can't
///    bind).
/// 3. Paste an API key for any `ProviderPreset`.
///
/// The token is never rendered back (`NeonSecureField` only), never logged, and
/// never interpolated into a message — every message shown here is either a
/// literal or `ConnectionTestResult.message`, which is documented to redact the
/// key.
struct SetupProvidersStepView: View {
    @Environment(AppEnvironment.self) private var environment

    let coordinator: SetupCoordinator

    @State private var preset = ProviderPreset.preset(id: "openai")
    @State private var token = ""
    @State private var baseURL = ProviderPreset.preset(id: "openai").defaultBaseURL
    @State private var isBusy = false
    @State private var outcome: SetupProviders.Outcome?
    @State private var pasteText = ""
    @State private var oauthController: ClaudeOAuthLoginController?
    @State private var flow = SetupSubscriptionFlow()
    @State private var flowRevision = 0     // redraw trigger; the flow is not @Observable
    @State private var routeError: String?
    /// The OAuth route's classification of `routeError`, kept beside it so the
    /// escape decision is made from a value and not from the string.
    @State private var routeFailure: ConnectionFailure?
    /// Set when the user takes the escape. Satisfies the step's requirement
    /// without a probe — and only ever alongside
    /// `coordinator.setDeferred(.providers, true)`, so "walked past" and "still
    /// owed" are one act.
    @State private var isDeferred = false
    /// Latched the moment ANY attempt in this session produced a failure the
    /// user cannot fix.
    ///
    /// It is never recomputed from the most recent attempt, because that made
    /// the escape erasable: an OAuth 429 offered "Set this up later", and then a
    /// mistyped API key returning 401 took it away again. The user earned a way
    /// out; a subsequent mistake must not confiscate it.
    @State private var escapeEarned = false

    /// View-level convenience only (Continue's enablement, clearing the token
    /// field). Decisions made inside async work read the returned
    /// `SetupProviders.Outcome` directly — see `settleSubscription`.
    private var isConnected: Bool { outcome?.isConnected ?? false }

    /// True when the marker already records this step as deferred — i.e. the gate
    /// was re-raised on it by a previous session.
    ///
    /// This is what makes the escape SURVIVE the relaunch it causes. Without it
    /// the trap simply moved one launch later: defer on a 429, relaunch after
    /// the provider recovered, have no key to hand, type a wrong one, get a 401
    /// — and be blocked with no escape, with `.providers` as `steps[0]` so Back
    /// is absent and the overlay non-dismissible. A step the user has ALREADY
    /// been permitted to defer stays deferrable.
    ///
    /// Note it does not *satisfy* the step: they are still asked, and asked
    /// first. It only guarantees the way out is still there.
    private var alreadyOwed: Bool { coordinator.deferredSteps.contains(.providers) }

    /// The rule and its copy live in `SetupValidation`, not here.
    private var unmet: [SetupValidation.Requirement] {
        SetupValidation.unmet(for: .providers,
                              values: ["isConnected": isConnected ? "true" : "false",
                                       "isDeferred": isDeferred ? "true" : "false"])
    }

    /// Whether "Set this up later" is on screen.
    ///
    /// Read ONLY from `ConnectionFailure.allowsDeferral`, reached either through
    /// the probe's `SetupProviders.Outcome` or through the OAuth controller's
    /// `errorFailure` — never by inspecting the message that happens to be
    /// displayed next to it.
    ///
    /// Two sources, both latched rather than momentary: something that happened
    /// in THIS session (`escapeEarned`), or a deferral already on record
    /// (`alreadyOwed`). A connection removes the offer because it makes it moot.
    private var canDefer: Bool {
        if isDeferred || isConnected { return false }
        return escapeEarned || alreadyOwed
    }

    /// Latches the escape from a probe verdict. The single place either route's
    /// classification turns into the offer.
    private func noteFailure(_ failure: ConnectionFailure?) {
        if failure?.allowsDeferral == true { escapeEarned = true }
    }

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro(tokens: tokens)
                    claudeRoutes(tokens: tokens)
                    apiKeyRoute(tokens: tokens)
                    status(tokens: tokens)
                    deferAffordance(tokens: tokens)
                }
                .padding(20)
            }

            // Back matters most on THIS step: it is mandatory and the
            // requirement is a live probe the user may simply not be able to
            // pass. Without Back, a failing connection is a dead end. It is
            // therefore not gated on `isConnected` — only Continue is.
            SetupStepFooter(coordinator: coordinator,
                            isPrimaryDisabled: !unmet.isEmpty) {
                coordinator.advance()
            }
        }
        .onAppear {
            if oauthController == nil {
                oauthController = ClaudeOAuthLoginController(
                    store: environment.oauthStore,
                    flow: ClaudeOAuthFlow(clientVersion: ClaudeProvider.claudeCodeVersion))
                // Clear anything an abandoned attempt (quit during the loopback
                // wait, wizard left with a paste outstanding) left on disk.
                SetupProviders.cleanUpAbandonedSubscriptions(
                    connections: environment.connectionStore,
                    agentConfig: environment.agentConfigStore,
                    oauth: environment.oauthStore)
                adoptExistingConnection()
            }
        }
    }

    // MARK: - Sections

    private func intro(tokens: DesignTokens) -> some View {
        Text("Ainkrad needs one working AI connection before it can do anything. "
             + "Connect a provider below — the connection is tested before it's saved, "
             + "so nothing broken gets stored.")
            .font(AinkradFont.display(12))
            .foregroundStyle(tokens.foreground.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func claudeRoutes(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "CLAUDE SUBSCRIPTION", tokens: tokens)

            if oauthController?.canImportFromClaudeCode == true {
                routeButton(tokens: tokens, icon: "arrow.down.doc",
                            title: "Use your existing Claude Code login") {
                    Task { await runImport() }
                }
            }

            AinkradButton(title: "Sign in with Claude", style: .primary,
                          icon: "person.badge.key", isLoading: isBusy) {
                Task { await runSignIn() }
            }
            .disabled(isBusy)

            if flow.awaitingPaste {
                if let url = oauthController?.authorizeURL {
                    // The loopback couldn't bind, so this URL is the only way
                    // back to the consent screen if the tab was closed or
                    // NSWorkspace.open failed.
                    Link(destination: url) {
                        Text("Open the Claude sign-in page again")
                            .font(AinkradFont.display(11, weight: .medium))
                            .foregroundStyle(tokens.accentSecondary)
                    }
                }
                HStack(spacing: 10) {
                    NeonSecureField(text: $pasteText,
                                    placeholder: "Paste the redirect URL or code",
                                    tokens: tokens)
                    Button {
                        let raw = pasteText
                        pasteText = ""
                        Task { await runPaste(raw) }
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(tokens.accentSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.5)))
    }

    private func apiKeyRoute(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "API KEY", tokens: tokens)

            AinkradSegmentedPicker(
                items: ProviderPreset.all.map(\.id),
                selection: Binding(
                    get: { preset.id },
                    set: { id in
                        let p = ProviderPreset.preset(id: id)
                        preset = p
                        baseURL = p.defaultBaseURL
                        token = ""
                        outcome = nil
                    }
                ),
                label: { ProviderPreset.preset(id: $0).displayName }
            )
            .fixedSize()

            if preset.allowsBaseURLEdit {
                NeonSecureField(text: $baseURL, placeholder: "Base URL", tokens: tokens)
            }

            HStack(spacing: 10) {
                if preset.requiresKey {
                    NeonSecureField(text: $token, placeholder: "API key", tokens: tokens)
                } else {
                    Text("No API key required")
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.foreground.opacity(0.45))
                }
                AinkradButton(title: "Connect", style: .secondary, isLoading: isBusy) {
                    Task { await runAPIKey() }
                }
                .disabled(isBusy || !canConnect)
            }
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.5)))
    }

    /// A keyless preset (ollama) needs only a base URL; everything else needs a key.
    private var canConnect: Bool {
        let hasKey = !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasURL = !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasURL && (!preset.requiresKey || hasKey)
    }

    /// The escape hatch, shown ONLY for a failure the user cannot fix.
    ///
    /// The step stays required by default; this is not a general "skip". It
    /// appears when — and only when — the classification carried out of the
    /// probe (or out of the OAuth token exchange) says the failure was
    /// transient: rate limiting, a provider 5xx, an unreachable endpoint. A 401
    /// or a malformed base URL is the user's to fix and gets no button, because
    /// fixing it is the entire point of this step.
    ///
    /// Deferring writes nothing: verify-before-save means the failed attempt
    /// already left no connection, and this path adds none. The user lands in
    /// the workspace with AI off, a persistent banner, and the step still owed.
    @ViewBuilder
    private func deferAffordance(tokens: DesignTokens) -> some View {
        if isDeferred {
            statusRow(tokens: tokens, icon: "clock.badge.exclamationmark",
                      text: "Set up later. Ainkrad's AI features stay off until you connect a "
                          + "provider — you'll be reminded in the workspace.",
                      color: tokens.accentTertiary)
                .accessibilityIdentifier("setup.providers.deferred")
        } else if canDefer {
            VStack(alignment: .leading, spacing: 6) {
                Text("That failure is on the provider's side, not yours.")
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.55))
                AinkradButton(title: "Set this up later", style: .secondary) {
                    // One act: walked past AND recorded as still owed.
                    isDeferred = true
                    coordinator.setDeferred(.providers, true)
                }
                .accessibilityIdentifier("setup.providers.defer")
            }
        }
    }

    @ViewBuilder
    private func status(tokens: DesignTokens) -> some View {
        switch outcome {
        case .connected(let message):
            statusRow(tokens: tokens, icon: "checkmark.seal.fill",
                      text: message, color: tokens.accentSecondary)
        case .failed(let message, _):
            statusRow(tokens: tokens, icon: "exclamationmark.triangle.fill",
                      text: message, color: tokens.accentTertiary)
        case nil:
            if let routeError {
                statusRow(tokens: tokens, icon: "exclamationmark.triangle.fill",
                          text: routeError, color: tokens.accentTertiary)
            } else if let message = unmet.first?.message {
                // Nothing attempted yet: Continue is off and, without this,
                // nothing on screen says why. The copy comes from
                // `SetupValidation` like every other requirement message — this
                // step's requirement being a probe rather than a field changes
                // nothing about where the rule lives.
                SetupRequirementNote(message: message, tokens: tokens)
                    .accessibilityIdentifier("setup.providers.isConnected.requirement")
            }
        }
    }

    private func routeButton(tokens: DesignTokens, icon: String, title: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.foreground.opacity(0.6))
                Text(title)
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.85))
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private func statusRow(tokens: DesignTokens, icon: String,
                           text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(color)
            Text(text)
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Routes

    private func runAPIKey() async {
        guard canConnect, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        routeError = nil
        routeFailure = nil
        let service = environment.modelCatalogService
        // Same read-back rule as `settleSubscription`: decide from the returned
        // value, not from the `@State` just assigned. Harmless here (a stale
        // read only leaves the field populated) but the two routes should not
        // disagree about how they read their own result.
        let result = await SetupProviders.connect(
            preset: preset, token: token, baseURL: baseURL,
            connections: environment.connectionStore,
            agentConfig: environment.agentConfigStore,
            verify: { kind, url, credential in
                await service.test(kind: kind, baseURL: url, credential: credential)
            })
        outcome = result
        if case .failed(_, let failure) = result { noteFailure(failure) }
        if result.isConnected {
            token = ""
            clearDeferral()
        }
    }

    private func runImport() async {
        guard let controller = oauthController, !isBusy else { return }
        isBusy = true
        defer { isBusy = false; flowRevision += 1 }
        let connection = flow.connection(connections: environment.connectionStore)
        controller.importFromClaudeCode(for: connection)
        await settleSubscription(connection, controller: controller, duringPaste: false)
    }

    private func runSignIn() async {
        guard let controller = oauthController, !isBusy else { return }
        isBusy = true
        defer { isBusy = false; flowRevision += 1 }
        let connection = flow.connection(connections: environment.connectionStore)
        await controller.beginLogin(for: connection)
        // `beginLogin` never throws and returns nothing: a loopback bind failure
        // sets `usePasteFallback`, in which case the flow is not finished yet and
        // the connection stays pending for `runPaste`.
        if controller.usePasteFallback {
            flow.needsPaste()
            // Surface (rather than discard) whatever the controller last said, so
            // "nothing happened" is never indistinguishable from a real error.
            routeError = controller.errorMessage
            routeFailure = controller.errorFailure
            noteFailure(controller.errorFailure)
            return
        }
        await settleSubscription(connection, controller: controller, duringPaste: false)
    }

    private func runPaste(_ raw: String) async {
        guard let controller = oauthController, !isBusy else { return }
        // The flow guarantees a pending connection whenever the paste field is
        // shown. If that ever fails to hold, say so rather than doing nothing.
        guard let connection = flow.pending else {
            routeError = "That sign-in attempt has expired. Start it again with Sign in with Claude."
            // A stale flow is not a provider failure: nothing about it says the
            // step should be postponable, so no escape is offered for it.
            routeFailure = nil
            flow.settled(connected: false)
            flowRevision += 1
            return
        }
        isBusy = true
        defer { isBusy = false; flowRevision += 1 }
        await controller.pasteCode(raw, for: connection)
        await settleSubscription(connection, controller: controller, duringPaste: true)
    }

    /// Resolves a subscription credential exactly the way
    /// `AssistantSettingsView+Connections.testConnection` does, probes it, and
    /// commits or rolls back.
    private func settleSubscription(_ connection: Connection,
                                    controller: ClaudeOAuthLoginController,
                                    duringPaste: Bool) async {
        if let message = controller.errorMessage {
            routeError = message
            // The OAuth subsystem's own verdict, already expressed as a
            // `ConnectionFailure` by `ClaudeOAuthLoginController.classify`, so
            // this route reaches the same decision as the API-key route without
            // either of them reading the other's copy.
            routeFailure = controller.errorFailure
            noteFailure(controller.errorFailure)
            // A failed paste keeps the route retryable — a mistyped code is the
            // exact case the fallback exists for. Any other failure tears the
            // flow down so the user is returned to the sign-in button.
            flow.attemptFailed(duringPaste: duringPaste,
                               connections: environment.connectionStore,
                               agentConfig: environment.agentConfigStore,
                               oauth: environment.oauthStore)
            return
        }
        let service = environment.modelCatalogService
        let oauthStore = environment.oauthStore
        let credential = (try? await oauthStore.liveCredential(for: connection)) ?? .apiKey("")

        // Bound to a local first. `flow.settled` must be told what
        // `finishSubscription` ACTUALLY returned, not what `@State outcome`
        // reads back as — the write below is not contractually visible to a
        // read outside `body`, and a stale `true` would keep `flow.pending`
        // holding a connection the failed probe had already removed from the
        // store, handing OAuth a dead connection id on the next attempt.
        let settled = await SetupProviders.finishSubscription(
            connection: connection, credential: credential,
            connections: environment.connectionStore,
            agentConfig: environment.agentConfigStore,
            oauth: oauthStore,
            verify: { kind, url, cred in
                await service.test(kind: kind, baseURL: url, credential: cred)
            })
        outcome = settled
        routeError = nil
        routeFailure = nil
        if case .failed(_, let failure) = settled { noteFailure(failure) }
        if settled.isConnected { clearDeferral() }
        flow.settled(connected: settled.isConnected)
    }

    /// A working connection cancels any earlier deferral — including one made in
    /// a previous session, which is exactly the case when the user came back
    /// here through the workspace banner. Without this the marker would keep
    /// owing the step and the gate would greet them again forever.
    private func clearDeferral() {
        isDeferred = false
        coordinator.setDeferred(.providers, false)
    }

    /// Recognises a connection this user already has.
    ///
    /// `isConnected` used to derive solely from this session's probe, so a user
    /// who deferred and then connected a provider through Settings was still
    /// gated on the next launch — and while the gate is up Settings is
    /// unreachable, so there was no way to point at what they already had. The
    /// active connection was verified when it was created (nothing else can
    /// become active), so it is honoured rather than re-probed: a re-probe would
    /// put a live network call in the way of a user whose setup is already
    /// correct, and a transient failure in it would gate them all over again.
    ///
    /// Runs after `cleanUpAbandonedSubscriptions`, so a half-finished attempt
    /// swept away by that call can never be adopted here.
    private func adoptExistingConnection() {
        guard outcome == nil,
              let id = environment.agentConfigStore.activeConnectionID,
              let existing = environment.connectionStore.connections.first(where: { $0.id == id })
        else { return }
        outcome = .connected(message: "Already connected · \(existing.displayName)")
        clearDeferral()
    }
}
