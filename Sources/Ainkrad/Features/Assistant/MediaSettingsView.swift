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
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "MEDIA", tokens: tokens, icon: "photo")

            labeled("IMAGE PROVIDER", tokens: tokens) {
                AinkradSelect(
                    items: providers,
                    selection: Binding(
                        get: { settings.document.provider },
                        set: { settings.setProvider($0); reloadForProvider() }),
                    label: providerLabel)
            }

            // Provider-specific configuration.
            let provider = settings.document.provider
            if provider == "custom" {
                labeled("BASE URL", tokens: tokens) {
                    AinkradTextField(text: $customBaseURL, placeholder: "https://api.provider.com/v1")
                        .onSubmit { settings.setCustomBaseURL(customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) }
                }
            }
            if let secretID = secretID(for: provider) {
                labeled("API KEY", tokens: tokens) {
                    NeonSecureField(text: $apiKey, placeholder: "API key", tokens: tokens)
                        .onSubmit { secrets.setSecret(apiKey.isEmpty ? nil : apiKey, for: secretID) }
                }
                if let hintText = modelHint(for: provider) {
                    labeled("MODEL", tokens: tokens) {
                        AinkradTextField(text: $model, placeholder: hintText)
                            .onSubmit { settings.setModel(model.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    }
                }
                if provider == "openai" || provider == "custom" {
                    labeled("SIZE", tokens: tokens) {
                        AinkradTextField(text: $imageSize, placeholder: "1024x1024")
                            .onSubmit { settings.setImageSize(imageSize.isEmpty ? "1024x1024" : imageSize) }
                    }
                }
                hint("Keys are Keychain-only. Leave MODEL blank for the provider default; set it to any supported model — that's also how you reach more models/providers.")
            } else if provider == "localsd" {
                labeled("LOCAL SERVER URL", tokens: tokens) {
                    AinkradTextField(text: $localSDURL, placeholder: "http://127.0.0.1:7860")
                        .onSubmit { settings.setLocalSDURL(localSDURL.trimmingCharacters(in: .whitespacesAndNewlines)) }
                }
                hint("Point at a local Automatic1111 / ComfyUI Stable Diffusion server. No key or card required.")
            } else {
                hint("No key required. Pollinations generates images with zero setup — keyless and card-free.")
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
