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
    @State private var localSDURL: String = ""
    @State private var model: String = ""
    @State private var imageSize: String = ""
    @State private var customBaseURL: String = ""

    /// All image providers. `pollinations`/`localsd` are keyless (no key, no
    /// payment card); `custom` points at any OpenAI-images-compatible endpoint;
    /// the rest need an API key (most offer a card-free free tier).
    private let providers = ["openai", "pollinations", "localsd", "stability", "replicate", "google", "huggingface", "custom"]

    /// Named OpenAI-images-compatible endpoints for the Custom provider.
    static let imagePresets: [EndpointPreset] = [
        .init(label: "Together AI", baseURL: "https://api.together.xyz/v1"),
        .init(label: "Fireworks", baseURL: "https://api.fireworks.ai/inference/v1"),
        .init(label: "DeepInfra", baseURL: "https://api.deepinfra.com/v1/openai"),
    ]

    private func providerLabel(_ id: String) -> String {
        switch id {
        case "pollinations": return "Pollinations (keyless)"
        case "localsd":      return "Local Stable Diffusion (keyless)"
        case "stability":    return "Stability AI"
        case "replicate":    return "Replicate"
        case "google":       return "Google Imagen"
        case "huggingface":  return "Hugging Face"
        case "custom":       return "Custom (OpenAI-compatible)"
        default:             return "OpenAI Images"
        }
    }

    /// Keychain secret ID for a key-based provider; `nil` for keyless ones.
    private func secretID(for provider: String) -> String? {
        switch provider {
        case "openai":      return OpenAIImageBackend.secretID
        case "stability":   return StabilityImageBackend.secretID
        case "replicate":   return ReplicateImageBackend.secretID
        case "google":      return GoogleImagenBackend.secretID
        case "huggingface": return HuggingFaceImageBackend.secretID
        case "custom":      return CustomOpenAIImageBackend.secretID
        default:            return nil // keyless
        }
    }

    /// Provider rows with live configured status for the management list.
    private var providerOptions: [ProviderOption] {
        providers.map { id in
            let keyless = secretID(for: id) == nil
            let configured: Bool
            switch id {
            case "pollinations": configured = true
            case "localsd":      configured = !settings.document.localSDURL.isEmpty
            case "custom":
                configured = !settings.document.customBaseURL.isEmpty
                    && !(secrets.secret(for: CustomOpenAIImageBackend.secretID) ?? "").isEmpty
            default:
                configured = !(secretID(for: id).flatMap { secrets.secret(for: $0) } ?? "").isEmpty
            }
            return ProviderOption(id: id, label: providerLabel(id), configured: configured, keyless: keyless)
        }
    }

    /// Providers that accept a model / engine override (also the "more providers"
    /// lever for model-parameterized backends).
    private func modelHint(for provider: String) -> String? {
        switch provider {
        case "openai":      return "gpt-image-1"
        case "stability":   return "stable-diffusion-xl-1024-v1-0"
        case "replicate":   return "black-forest-labs/flux-schnell"
        case "google":      return "imagen-3.0-generate-002"
        case "huggingface": return "black-forest-labs/FLUX.1-schnell"
        case "custom":      return "provider's model id"
        default:            return nil
        }
    }

    var body: some View {
        AinkradSettingsPanel(title: "Media",
                             hint: "Image generation and handling.") {
            VStack(alignment: .leading, spacing: 12) {
                AinkradCaptionedRow("Image provider") {
                    ProviderStatusList(
                        options: providerOptions,
                        selection: Binding(
                            get: { settings.document.provider },
                            set: { settings.setProvider($0) }),
                        tokens: tokens,
                        onSelect: { _ in reloadForProvider() })
                }

                // Provider-specific configuration.
                let provider = settings.document.provider
                if provider == "custom" {
                    AinkradCaptionedRow("Base URL") {
                        AinkradTextField(text: $customBaseURL, placeholder: "https://api.provider.com/v1")
                            .onSubmit { settings.setCustomBaseURL(customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    }
                    ProviderPresetChips(presets: Self.imagePresets, tokens: tokens) { preset in
                        customBaseURL = preset.baseURL
                        settings.setCustomBaseURL(preset.baseURL)
                    }
                }
                if let secretID = secretID(for: provider) {
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
                    if provider == "openai" || provider == "custom" {
                        AinkradCaptionedRow("Size") {
                            AinkradTextField(text: $imageSize, placeholder: "1024x1024")
                                .onSubmit { settings.setImageSize(imageSize.isEmpty ? "1024x1024" : imageSize) }
                        }
                    }
                    hint("Keys are Keychain-only. Leave MODEL blank for the provider default; set it to any supported model — that's also how you reach more models/providers.")
                } else if provider == "localsd" {
                    AinkradCaptionedRow("Local server URL") {
                        AinkradTextField(text: $localSDURL, placeholder: "http://127.0.0.1:7860")
                            .onSubmit { settings.setLocalSDURL(localSDURL.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    }
                    hint("Point at a local Automatic1111 / ComfyUI Stable Diffusion server. No key or card required.")
                } else {
                    hint("No key required. Pollinations generates images with zero setup — keyless and card-free.")
                }
            }
        }
        .onAppear { reloadForProvider() }
    }

    /// Loads the API-key field from the currently-selected provider's Keychain
    /// entry (empty for keyless providers).
    private func reloadForProvider() {
        apiKey = secretID(for: settings.document.provider).flatMap { secrets.secret(for: $0) } ?? ""
        model = settings.document.model
        imageSize = settings.document.imageSize
        customBaseURL = settings.document.customBaseURL
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(AinkradFont.display(10, weight: .regular))
            .foregroundStyle(tokens.foreground.opacity(0.4))
            .fixedSize(horizontal: false, vertical: true)
    }
}
