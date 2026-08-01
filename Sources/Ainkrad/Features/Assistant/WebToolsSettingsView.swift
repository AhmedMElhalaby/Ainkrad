import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The Assistant Settings "WEB" section: the `web_search` provider picker and
/// its API key. Built from `AinkradSettingsPanel`, `AinkradCaptionedRow` for
/// single-field rows, and `AssistantSettingsLabeled` for the provider list;
/// zero native controls — every control here is an AinkradAppKit Cardinal HUD
/// component. The key itself is never persisted in
/// `settings.document` — it's written straight to the Keychain via
/// `secrets.setSecret(_:for:)` keyed by `BraveSearchBackend.secretID`, the same
/// split `VoiceSettingsView` uses for provider opt-in credentials.
@MainActor
struct WebToolsSettingsView: View {
    let settings: WebSearchSettingsStore
    let secrets: SecretStore
    let tokens: DesignTokens
    @State private var apiKey: String = ""
    @State private var searxngURL: String = ""

    /// Provider IDs, keyed by their display label. SearXNG and DuckDuckGo are
    /// keyless (no API key, no payment card); Brave needs a paid-tier key.
    private let providers = ["brave", "searxng", "duckduckgo"]

    private var providerOptions: [ProviderOption] {
        providers.map { id in
            let configured: Bool
            switch id {
            case "duckduckgo": configured = true
            case "searxng":    configured = !settings.document.searxngURL.isEmpty
            default:           configured = !(secrets.secret(for: BraveSearchBackend.secretID) ?? "").isEmpty
            }
            return ProviderOption(id: id, label: providerLabel(id), configured: configured, keyless: id != "brave")
        }
    }

    private func providerLabel(_ id: String) -> String {
        switch id {
        case "searxng": return "SearXNG (keyless)"
        case "duckduckgo": return "DuckDuckGo (keyless)"
        default: return "Brave Search"
        }
    }

    var body: some View {
        AinkradSettingsPanel(title: "Web tools",
                             hint: "The search provider the assistant queries.") {
            VStack(alignment: .leading, spacing: 12) {
                AssistantSettingsLabeled("Search provider", tokens: tokens) {
                    ProviderStatusList(
                        options: providerOptions,
                        selection: Binding(
                            get: { settings.document.provider },
                            set: { settings.setProvider($0) }),
                        tokens: tokens)
                }

                // Provider-specific configuration.
                switch settings.document.provider {
                case "brave":
                    AinkradCaptionedRow("API key") {
                        NeonSecureField(text: $apiKey, placeholder: "Search API key", tokens: tokens)
                            .onSubmit {
                                secrets.setSecret(apiKey.isEmpty ? nil : apiKey, for: BraveSearchBackend.secretID)
                            }
                    }
                case "searxng":
                    AinkradCaptionedRow("Instance URL") {
                        AinkradTextField(text: $searxngURL, placeholder: "https://searx.example.org")
                            .onSubmit { settings.setSearxngURL(searxngURL.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    }
                    hint("No key or card required. Point at a public instance or self-host one (JSON API must be enabled).")
                default:
                    hint("No key required. Results are scraped from DuckDuckGo's HTML — keyless and card-free, but may occasionally return nothing if their page markup changes.")
                }
            }
        }
        .onAppear {
            apiKey = secrets.secret(for: BraveSearchBackend.secretID) ?? ""
            searxngURL = settings.document.searxngURL
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(AinkradFont.display(10, weight: .regular))
            .foregroundStyle(tokens.foreground.opacity(0.4))
            .fixedSize(horizontal: false, vertical: true)
    }
}
