import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The Assistant Settings "MEDIA" section: the image-generation provider picker
/// and its API key. Mirrors `WebToolsSettingsView`'s idiom (`SettingsSectionHeader`
/// + a `labeled` row wrapper); zero native controls — every control here is an
/// AinkradAppKit Cardinal HUD component. The key itself is never persisted in
/// `settings.document` — it's written straight to the Keychain via
/// `secrets.setSecret(_:for:)` keyed by `OpenAIImageBackend.secretID`.
@MainActor
struct MediaSettingsView: View {
    let settings: MediaSettingsStore
    let secrets: SecretStore
    let tokens: DesignTokens
    @State private var apiKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "MEDIA", tokens: tokens, icon: "photo")

            labeled("IMAGE PROVIDER", tokens: tokens) {
                AinkradSelect(
                    items: ["openai"],
                    selection: Binding(
                        get: { settings.document.provider },
                        set: { settings.setProvider($0) }),
                    label: { $0 == "openai" ? "OpenAI Images" : $0 })
            }

            labeled("MEDIA API KEY", tokens: tokens) {
                NeonSecureField(text: $apiKey, placeholder: "Media API key", tokens: tokens)
                    .onSubmit {
                        secrets.setSecret(apiKey.isEmpty ? nil : apiKey, for: OpenAIImageBackend.secretID)
                    }
            }
        }
        .onAppear { apiKey = secrets.secret(for: OpenAIImageBackend.secretID) ?? "" }
    }

    // MARK: - Shared row label (mirrors `WebToolsSettingsView.labeled`)

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
