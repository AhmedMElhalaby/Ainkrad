import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The Sage Settings "TEXT TO SPEECH" section: the `speak` tool's TTS
/// provider. `On-device` (default) is keyless/offline; OpenAI and ElevenLabs are
/// cloud voices (key-based). Keys are Keychain-only. Owns its store via `@State`
/// (the routing synth reads the persisted provider live). Zero native controls.
@MainActor
struct TTSSettingsView: View {
    let secrets: SecretStore
    let tokens: DesignTokens
    @State private var settings: SpeechSynthesisSettingsStore
    @State private var apiKey: String = ""
    @State private var voice: String = ""

    init(persistence: PersistenceStore, secrets: SecretStore, tokens: DesignTokens) {
        self.secrets = secrets
        self.tokens = tokens
        _settings = State(initialValue: SpeechSynthesisSettingsStore(persistence: persistence))
    }

    @State private var customBaseURL: String = ""
    @State private var customModel: String = ""

    private let providers = ["onDevice", "openai", "elevenlabs", "custom"]

    /// Named OpenAI-speech-compatible endpoints for the Custom provider.
    static let ttsPresets: [EndpointPreset] = [
        .init(label: "Groq", baseURL: "https://api.groq.com/openai/v1"),
        .init(label: "DeepInfra", baseURL: "https://api.deepinfra.com/v1/openai"),
        .init(label: "Lemonfox", baseURL: "https://api.lemonfox.ai/v1"),
    ]

    private func providerLabel(_ id: String) -> String {
        switch id {
        case "openai":     return "OpenAI (cloud)"
        case "elevenlabs": return "ElevenLabs (cloud)"
        case "custom":     return "Custom (OpenAI-compatible)"
        default:           return "On-device (keyless)"
        }
    }

    private func secretID(for provider: String) -> String? {
        switch provider {
        case "openai":     return OpenAITTSBackend.secretID
        case "elevenlabs": return ElevenLabsTTSBackend.secretID
        case "custom":     return OpenAITTSBackend.customSecretID
        default:           return nil
        }
    }

    private var providerOptions: [ProviderOption] {
        providers.map { id in
            let keyless = secretID(for: id) == nil
            let hasKey = !(secretID(for: id).flatMap { secrets.secret(for: $0) } ?? "").isEmpty
            let configured = id == "custom"
                ? (hasKey && !settings.document.customBaseURL.isEmpty)
                : (keyless || hasKey)
            return ProviderOption(id: id, label: providerLabel(id), configured: configured, keyless: keyless)
        }
    }

    var body: some View {
        AinkradSettingsPanel(title: "Text to speech",
                             hint: "How the assistant reads its replies aloud.") {
            VStack(alignment: .leading, spacing: 12) {
                SageSettingsLabeled("Voice provider", tokens: tokens) {
                    ProviderStatusList(
                        options: providerOptions,
                        selection: Binding(
                            get: { settings.document.provider },
                            set: { settings.setProvider($0) }),
                        tokens: tokens,
                        onSelect: { _ in reload() })
                }

                let provider = settings.document.provider
                if let secretID = secretID(for: provider) {
                    if provider == "custom" {
                        AinkradCaptionedRow("Base URL") {
                            AinkradTextField(text: $customBaseURL, placeholder: "https://api.provider.com/v1")
                                .onSubmit { settings.setCustomBaseURL(customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        }
                        ProviderPresetChips(presets: Self.ttsPresets, tokens: tokens) { preset in
                            customBaseURL = preset.baseURL
                            settings.setCustomBaseURL(preset.baseURL)
                        }
                    }
                    AinkradCaptionedRow("API key") {
                        NeonSecureField(text: $apiKey, placeholder: "API key", tokens: tokens)
                            .onSubmit { secrets.setSecret(apiKey.isEmpty ? nil : apiKey, for: secretID) }
                    }
                    if provider == "openai" {
                        AinkradCaptionedRow("Voice") {
                            AinkradTextField(text: $voice, placeholder: "alloy")
                                .onSubmit { settings.setOpenAIVoice(voice.isEmpty ? "alloy" : voice) }
                        }
                    } else if provider == "elevenlabs" {
                        AinkradCaptionedRow("Voice ID") {
                            AinkradTextField(text: $voice, placeholder: "21m00Tcm4TlvDq8ikWAM (Rachel)")
                                .onSubmit { settings.setElevenLabsVoiceID(voice.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        }
                    } else if provider == "custom" {
                        AinkradCaptionedRow("Model") {
                            AinkradTextField(text: $customModel, placeholder: "tts-1")
                                .onSubmit { settings.setCustomModel(customModel.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        }
                        AinkradCaptionedRow("Voice") {
                            AinkradTextField(text: $voice, placeholder: "alloy")
                                .onSubmit { settings.setCustomVoice(voice.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        }
                    }
                    hint("Cloud voices sound more natural but require a key. On-device speech is free and offline.")
                } else {
                    hint("On-device speech synthesis — no key required, works offline.")
                }
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        let p = settings.document.provider
        apiKey = secretID(for: p).flatMap { secrets.secret(for: $0) } ?? ""
        customBaseURL = settings.document.customBaseURL
        customModel = settings.document.customModel
        voice = p == "openai" ? settings.document.openAIVoice
              : p == "elevenlabs" ? settings.document.elevenLabsVoiceID
              : p == "custom" ? settings.document.customVoice : ""
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(AinkradFont.display(10, weight: .regular))
            .foregroundStyle(tokens.foreground.opacity(0.4))
            .fixedSize(horizontal: false, vertical: true)
    }
}
