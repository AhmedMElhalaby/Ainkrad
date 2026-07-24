import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The Assistant Settings "WEB" section: the `web_search` provider picker and
/// its API key. Mirrors `VoiceSettingsView`'s idiom (`SettingsSectionHeader` +
/// a `labeled` row wrapper); zero native controls — every control here is an
/// AinkradAppKit Cardinal HUD component. The key itself is never persisted in
/// `settings.document` — it's written straight to the Keychain via
/// `secrets.setSecret(_:for:)` keyed by `BraveSearchBackend.secretID`, the same
/// split `VoiceSettingsView` uses for provider opt-in credentials.
@MainActor
struct WebToolsSettingsView: View {
    let settings: WebSearchSettingsStore
    let secrets: SecretStore
    let tokens: DesignTokens
    @State private var apiKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "WEB", tokens: tokens, icon: "globe")

            labeled("SEARCH PROVIDER", tokens: tokens) {
                AinkradSelect(
                    items: ["brave"],
                    selection: Binding(
                        get: { settings.document.provider },
                        set: { settings.setProvider($0) }),
                    label: { $0 == "brave" ? "Brave Search" : $0 })
            }

            labeled("SEARCH API KEY", tokens: tokens) {
                NeonSecureField(text: $apiKey, placeholder: "Search API key", tokens: tokens)
                    .onSubmit {
                        secrets.setSecret(apiKey.isEmpty ? nil : apiKey, for: BraveSearchBackend.secretID)
                    }
            }
        }
        .onAppear { apiKey = secrets.secret(for: BraveSearchBackend.secretID) ?? "" }
    }

    // MARK: - Shared row label (mirrors `VoiceSettingsView.labeled`)

    private func labeled<Content: View>(_ title: String, tokens: DesignTokens,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(AinkradFont.display(10, weight: .medium)).kerning(0.6)
                .foregroundStyle(tokens.foreground.opacity(0.45))
            content()
        }
    }
}
