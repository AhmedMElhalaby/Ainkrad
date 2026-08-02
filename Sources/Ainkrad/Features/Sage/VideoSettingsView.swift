import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The Sage Settings "VIDEO" section: the `video_generate` provider picker
/// and its API key. All video providers are key-based (no keyless video exists).
/// The key is Keychain-only via `secrets.setSecret(_:for:)`, keyed by the
/// selected backend's `secretID`. Owns its `VideoSettingsStore` via `@State`
/// (built from `persistence`) — the routing backend reads the persisted provider
/// live, so no `AppEnvironment` plumbing is needed. Zero native controls.
@MainActor
struct VideoSettingsView: View {
    let secrets: SecretStore
    let tokens: DesignTokens
    @State private var settings: VideoSettingsStore
    @State private var apiKey: String = ""
    @State private var model: String = ""
    @State private var customBaseURL: String = ""
    @State private var localURL: String = ""

    init(persistence: PersistenceStore, secrets: SecretStore, tokens: DesignTokens) {
        self.secrets = secrets
        self.tokens = tokens
        _settings = State(initialValue: VideoSettingsStore(persistence: persistence))
    }

    private let providers = ["replicate", "luma", "fal", "custom", "local"]

    private func providerLabel(_ id: String) -> String {
        switch id {
        case "luma":   return "Luma Dream Machine"
        case "fal":    return "fal.ai"
        case "custom": return "Custom (Replicate-compatible)"
        case "local":  return "Local server (keyless)"
        default:       return "Replicate"
        }
    }

    /// Keychain secret ID for a key-based provider; `nil` for the keyless local one.
    private func secretID(for provider: String) -> String? {
        switch provider {
        case "luma":   return LumaVideoBackend.secretID
        case "fal":    return FalVideoBackend.secretID
        case "custom": return CustomVideoBackend.secretID
        case "local":  return nil
        default:       return ReplicateVideoBackend.secretID
        }
    }

    private var providerOptions: [ProviderOption] {
        providers.map { id in
            let keyless = secretID(for: id) == nil
            let configured: Bool
            switch id {
            case "local":  configured = !settings.document.localURL.isEmpty
            case "custom":
                configured = !settings.document.customBaseURL.isEmpty
                    && !(secrets.secret(for: CustomVideoBackend.secretID) ?? "").isEmpty
            default:
                configured = !(secretID(for: id).flatMap { secrets.secret(for: $0) } ?? "").isEmpty
            }
            return ProviderOption(id: id, label: providerLabel(id), configured: configured, keyless: keyless)
        }
    }

    private func modelHint(for provider: String) -> String? {
        switch provider {
        case "luma":   return nil
        case "fal":    return "fal-ai/ltx-video"
        case "custom": return "optional model id"
        default:       return "lightricks/ltx-video"
        }
    }

    var body: some View {
        AinkradSettingsPanel(title: "Video",
                             hint: "Video generation and handling.") {
            VStack(alignment: .leading, spacing: 12) {
                SageSettingsLabeled("Video provider", tokens: tokens) {
                    ProviderStatusList(
                        options: providerOptions,
                        selection: Binding(
                            get: { settings.document.provider },
                            set: { settings.setProvider($0) }),
                        tokens: tokens,
                        onSelect: { _ in reloadKey() })
                }

                let provider = settings.document.provider
                if provider == "local" {
                    AinkradCaptionedRow("Server URL") {
                        AinkradTextField(text: $localURL, placeholder: "http://127.0.0.1:8000/generate")
                            .onSubmit { settings.setLocalURL(localURL.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    }
                    hint("Keyless: POST {\"prompt\"} → JSON with a video link (video_url / url / output). Point at a local ComfyUI wrapper or similar. No key or card.")
                } else if let secretID = secretID(for: provider) {
                    if provider == "custom" {
                        AinkradCaptionedRow("Base URL") {
                            AinkradTextField(text: $customBaseURL, placeholder: "https://api.provider.com/v1/predictions")
                                .onSubmit { settings.setCustomBaseURL(customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        }
                    }
                    AinkradCaptionedRow("API key") {
                        NeonSecureField(text: $apiKey, placeholder: "API key", tokens: tokens)
                            .onSubmit { secrets.setSecret(apiKey.isEmpty ? nil : apiKey, for: secretID) }
                    }
                    if let hintText = modelHint(for: provider) {
                        AinkradCaptionedRow("Model") {
                            AinkradTextField(text: $model, placeholder: hintText)
                                .onSubmit { settings.setModel(model.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        }
                    }
                    hint("Keys are Keychain-only. Set MODEL to any supported model id — that's how you reach more models (Pika, Kling, LTX, SVD, …). No keyless cloud video exists; use Local for a keyless self-hosted path.")
                }
            }
        }
        .onAppear { reloadKey() }
    }

    private func reloadKey() {
        apiKey = secretID(for: settings.document.provider).flatMap { secrets.secret(for: $0) } ?? ""
        model = settings.document.model
        customBaseURL = settings.document.customBaseURL
        localURL = settings.document.localURL
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(AinkradFont.display(10, weight: .regular))
            .foregroundStyle(tokens.foreground.opacity(0.4))
            .fixedSize(horizontal: false, vertical: true)
    }
}
