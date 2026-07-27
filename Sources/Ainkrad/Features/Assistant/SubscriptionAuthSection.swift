import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Subscription (Claude OAuth) auth controls for a single Claude connection —
/// an auth-method switch (API key vs. subscription), "Sign in with Claude"
/// (loopback OAuth, falling back to a paste field when the loopback port
/// can't bind), an "import from Claude Code" row, and the connected-state
/// row + sign-out. Cardinal-HUD styled to match the sibling connection row in
/// `AssistantSettingsView+Sections.connectionRow` (same chamfer-surface
/// chrome, no native Picker/SecureField/.sheet).
struct SubscriptionAuthSection: View {
    let connection: Connection
    let connectionStore: ConnectionStore
    let oauthStore: OAuthCredentialStore
    let tokens: DesignTokens

    @StateObject private var controller: ClaudeOAuthLoginController
    @State private var pasteText = ""
    @State private var isSigningIn = false

    init(connection: Connection, connectionStore: ConnectionStore,
         oauthStore: OAuthCredentialStore, tokens: DesignTokens) {
        self.connection = connection
        self.connectionStore = connectionStore
        self.oauthStore = oauthStore
        self.tokens = tokens
        _controller = StateObject(wrappedValue: ClaudeOAuthLoginController(
            store: oauthStore,
            flow: ClaudeOAuthFlow(clientVersion: ClaudeProvider.claudeCodeVersion)))
    }

    private var account: OAuthAccount? { oauthStore.account(for: connection.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AinkradSegmentedPicker(
                items: [AuthMode.apiKey, .subscription],
                selection: Binding(
                    get: { connection.authMode },
                    set: { connectionStore.setAuthMode($0, for: connection) }
                ),
                label: { $0 == .apiKey ? "API key" : "Claude subscription" }
            )

            if connection.authMode == .subscription {
                if let account {
                    connectedRow(account, tokens: tokens)
                } else {
                    signInRow(tokens: tokens)
                    if controller.usePasteFallback {
                        pasteRow(tokens: tokens)
                    }
                    if controller.canImportFromClaudeCode {
                        importRow(tokens: tokens)
                    }
                    if let message = controller.errorMessage {
                        Text(message)
                            .font(AinkradFont.display(11))
                            .foregroundStyle(tokens.accentTertiary)
                    }
                }
            }
        }
        .padding(12)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.45)))
    }

    private func signInRow(tokens: DesignTokens) -> some View {
        AinkradButton(title: "Sign in with Claude", style: .primary, icon: "person.badge.key", isLoading: isSigningIn) {
            isSigningIn = true
            Task {
                defer { isSigningIn = false }
                await controller.beginLogin(for: connection)
            }
        }
    }

    private func pasteRow(tokens: DesignTokens) -> some View {
        HStack(spacing: 10) {
            NeonSecureField(text: $pasteText, placeholder: "Paste the redirect URL or code", tokens: tokens)
            Button {
                let raw = pasteText
                pasteText = ""
                Task { await controller.pasteCode(raw, for: connection) }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(tokens.accentSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func importRow(tokens: DesignTokens) -> some View {
        Button { controller.importFromClaudeCode(for: connection) } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.foreground.opacity(0.6))
                Text("Use your existing Claude Code login")
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.85))
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.35)))
        }
        .buttonStyle(.plain)
    }

    private func connectedRow(_ account: OAuthAccount, tokens: DesignTokens) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 13))
                .foregroundStyle(tokens.accentSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connected via Claude subscription")
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.85))
                Text(account.source == .claudeCodeImport ? "Imported from Claude Code" : "Signed in")
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
            }
            Spacer(minLength: 8)
            Button { oauthStore.signOut(connection.id) } label: {
                Text("Sign out")
                    .font(AinkradFont.display(11, weight: .medium))
                    .foregroundStyle(tokens.accentTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.35)))
    }
}
