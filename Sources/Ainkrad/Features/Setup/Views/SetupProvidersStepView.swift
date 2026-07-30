import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Connects and verifies a provider. Verification is injected so the step can be
/// tested without network access; production passes `ModelCatalogService.test`.
///
/// The rule this enum exists to enforce: **verify BEFORE saving**. A saved but
/// broken connection looks configured, passes the gate, and then fails later
/// somewhere else with no obvious cause.
@MainActor
enum SetupProviders {
    enum Outcome: Equatable {
        case connected(message: String)
        case failed(message: String)
    }

    typealias Verifier = (ProviderKind, String, ProviderCredential) async -> ConnectionTestResult

    /// API-key route. Nothing is written until the probe says ok — so a failure
    /// leaves no connection, no Keychain item, and no active-connection id.
    ///
    /// A keyless preset (`ollama`) passes `token: ""` and is probed with
    /// `.apiKey("")`, exactly as `AssistantSettingsView+Connections.testConnection`
    /// does for a connection with no stored secret.
    static func connect(preset: ProviderPreset,
                        token: String,
                        baseURL: String,
                        connections: ConnectionStore,
                        agentConfig: AgentConfigStore,
                        verify: Verifier) async -> Outcome {
        let result = await verify(preset.kind, baseURL, .apiKey(token))
        guard result.ok else { return .failed(message: result.message) }

        let connection = connections.addConnection(
            preset: preset,
            displayName: preset.displayName,
            baseURL: baseURL,
            token: token,
            authMode: .apiKey)
        agentConfig.setActiveConnectionID(connection.id)
        return .connected(message: result.message)
    }

    /// Subscription route (OAuth sign-in and Claude Code import both land here).
    ///
    /// Unlike the API-key route this one cannot verify first: both
    /// `ClaudeOAuthLoginController` and `OAuthCredentialStore` key their token by
    /// `connection.id`, so a connection must exist before a credential can be
    /// obtained at all. The invariant is preserved by rolling back instead — a
    /// failed probe signs the credential out (clearing its Keychain item) and
    /// removes the connection, leaving the same clean slate as a failed
    /// API-key attempt. The credential is never trusted just because it came
    /// from a trusted source; it is probed like any other.
    static func finishSubscription(connection: Connection,
                                   credential: ProviderCredential,
                                   connections: ConnectionStore,
                                   agentConfig: AgentConfigStore,
                                   oauth: OAuthCredentialStore,
                                   verify: Verifier) async -> Outcome {
        let result = await verify(connection.kind, connection.baseURL, credential)
        guard result.ok else {
            oauth.signOut(connection.id)
            connections.removeConnection(connection)
            if agentConfig.activeConnectionID == connection.id {
                agentConfig.setActiveConnectionID(nil)
            }
            return .failed(message: result.message)
        }
        agentConfig.setActiveConnectionID(connection.id)
        return .connected(message: result.message)
    }
}

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
    @State private var pendingSubscription: Connection?
    @State private var usePasteFallback = false
    @State private var routeError: String?

    private var isConnected: Bool {
        if case .connected = outcome { return true }
        return false
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
                }
                .padding(20)
            }

            HStack {
                Spacer(minLength: 0)
                AinkradButton(title: "Continue", style: .primary) {
                    coordinator.advance()
                }
                .disabled(!isConnected)
            }
            .padding(20)
        }
        .onAppear {
            if oauthController == nil {
                oauthController = ClaudeOAuthLoginController(
                    store: environment.oauthStore,
                    flow: ClaudeOAuthFlow(clientVersion: ClaudeProvider.claudeCodeVersion))
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

            if usePasteFallback {
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

    @ViewBuilder
    private func status(tokens: DesignTokens) -> some View {
        switch outcome {
        case .connected(let message):
            statusRow(tokens: tokens, icon: "checkmark.seal.fill",
                      text: message, color: tokens.accentSecondary)
        case .failed(let message):
            statusRow(tokens: tokens, icon: "exclamationmark.triangle.fill",
                      text: message, color: tokens.accentTertiary)
        case nil:
            if let routeError {
                statusRow(tokens: tokens, icon: "exclamationmark.triangle.fill",
                          text: routeError, color: tokens.accentTertiary)
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
        let service = environment.modelCatalogService
        outcome = await SetupProviders.connect(
            preset: preset, token: token, baseURL: baseURL,
            connections: environment.connectionStore,
            agentConfig: environment.agentConfigStore,
            verify: { kind, url, credential in
                await service.test(kind: kind, baseURL: url, credential: credential)
            })
        if isConnected { token = "" }
    }

    private func runImport() async {
        guard let controller = oauthController, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        let connection = subscriptionConnection()
        controller.importFromClaudeCode(for: connection)
        await settleSubscription(connection, controller: controller)
    }

    private func runSignIn() async {
        guard let controller = oauthController, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        let connection = subscriptionConnection()
        await controller.beginLogin(for: connection)
        // `beginLogin` never throws and returns nothing: a loopback bind failure
        // sets `usePasteFallback`, in which case the flow is not finished yet and
        // the connection stays pending for `runPaste`.
        if controller.usePasteFallback {
            usePasteFallback = true
            routeError = nil
            return
        }
        await settleSubscription(connection, controller: controller)
    }

    private func runPaste(_ raw: String) async {
        guard let controller = oauthController,
              let connection = pendingSubscription, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        await controller.pasteCode(raw, for: connection)
        await settleSubscription(connection, controller: controller)
    }

    /// Reuses the pending subscription connection across a paste round-trip so a
    /// retry doesn't strand an orphan record.
    private func subscriptionConnection() -> Connection {
        if let pendingSubscription { return pendingSubscription }
        let claude = ProviderPreset.preset(id: "claude")
        let created = environment.connectionStore.addConnection(
            preset: claude, displayName: claude.displayName,
            baseURL: claude.defaultBaseURL, token: "", authMode: .subscription)
        pendingSubscription = created
        return created
    }

    /// Resolves a subscription credential exactly the way
    /// `AssistantSettingsView+Connections.testConnection` does, probes it, and
    /// commits or rolls back.
    private func settleSubscription(_ connection: Connection,
                                    controller: ClaudeOAuthLoginController) async {
        if let message = controller.errorMessage {
            routeError = message
            rollback(connection)
            return
        }
        let service = environment.modelCatalogService
        let oauthStore = environment.oauthStore
        let credential = (try? await oauthStore.liveCredential(for: connection)) ?? .apiKey("")

        outcome = await SetupProviders.finishSubscription(
            connection: connection, credential: credential,
            connections: environment.connectionStore,
            agentConfig: environment.agentConfigStore,
            oauth: oauthStore,
            verify: { kind, url, cred in
                await service.test(kind: kind, baseURL: url, credential: cred)
            })
        routeError = nil
        usePasteFallback = false
        // `finishSubscription` already removed the connection on failure.
        pendingSubscription = isConnected ? connection : nil
    }

    private func rollback(_ connection: Connection) {
        environment.oauthStore.signOut(connection.id)
        environment.connectionStore.removeConnection(connection)
        if environment.agentConfigStore.activeConnectionID == connection.id {
            environment.agentConfigStore.setActiveConnectionID(nil)
        }
        pendingSubscription = nil
    }
}
