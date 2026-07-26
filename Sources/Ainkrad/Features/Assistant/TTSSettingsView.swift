import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The Assistant Settings "TEXT TO SPEECH" section: the `speak` tool's TTS
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "TEXT TO SPEECH", tokens: tokens, icon: "waveform")

            labeled("VOICE PROVIDER", tokens: tokens) {
                AinkradSelect(
                    items: providers,
                    selection: Binding(
                        get: { settings.document.provider },
                        set: { settings.setProvider($0); reload() }),
                    label: providerLabel)
            }

            let provider = settings.document.provider
            if let secretID = secretID(for: provider) {
                if provider == "custom" {
                    labeled("BASE URL", tokens: tokens) {
                        AinkradTextField(text: $customBaseURL, placeholder: "https://api.provider.com/v1")
                            .onSubmit { settings.setCustomBaseURL(customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    }
                }
                labeled("API KEY", tokens: tokens) {
                    NeonSecureField(text: $apiKey, placeholder: "API key", tokens: tokens)
                        .onSubmit { secrets.setSecret(apiKey.isEmpty ? nil : apiKey, for: secretID) }
                }
                if provider == "openai" {
                    labeled("VOICE", tokens: tokens) {
                        AinkradTextField(text: $voice, placeholder: "alloy")
                            .onSubmit { settings.setOpenAIVoice(voice.isEmpty ? "alloy" : voice) }
                    }
                } else if provider == "elevenlabs" {
                    labeled("VOICE ID", tokens: tokens) {
                        AinkradTextField(text: $voice, placeholder: "21m00Tcm4TlvDq8ikWAM (Rachel)")
                            .onSubmit { settings.setElevenLabsVoiceID(voice.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    }
                } else if provider == "custom" {
                    labeled("MODEL", tokens: tokens) {
                        AinkradTextField(text: $customModel, placeholder: "tts-1")
                            .onSubmit { settings.setCustomModel(customModel.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    }
                    labeled("VOICE", tokens: tokens) {
                        AinkradTextField(text: $voice, placeholder: "alloy")
                            .onSubmit { settings.setCustomVoice(voice.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    }
                }
                hint("Cloud voices sound more natural but require a key. On-device speech is free and offline.")
            } else {
                hint("On-device speech synthesis — no key required, works offline.")
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
