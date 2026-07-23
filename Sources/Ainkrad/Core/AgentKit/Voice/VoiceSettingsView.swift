import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The Assistant Settings "VOICE" section: backend (on-device/provider),
/// push-to-talk mode, auto-send, provider opt-in (connection + model +
/// visible upload notice), locale, and a read-only display of the current
/// push-to-talk hotkey chord. Mirrors `AssistantSettingsView`'s section idiom
/// (`SettingsSectionHeader` + a `labeled` row wrapper); zero native controls —
/// every control here is an AinkradAppKit Cardinal HUD component.
///
/// The hotkey itself is rebound in Settings → Keyboard
/// (`ShortcutsSettingsView`, which already renders every `ShortcutAction`
/// including `.pushToTalk`) — this view only reads the current chord via
/// `ShortcutStore.chord(for:)` for a read-only display; it does not build a
/// second recorder.
@MainActor
struct VoiceSettingsView: View {
    let settings: VoiceSettingsStore
    let connections: ConnectionStore
    let shortcuts: ShortcutStore
    let tokens: DesignTokens

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "VOICE", tokens: tokens, icon: "waveform")

            labeled("BACKEND", tokens: tokens) {
                AinkradSelect(
                    items: TranscriptionBackendKind.allCases,
                    selection: Binding(
                        get: { settings.document.backend },
                        set: { settings.setBackend($0) }),
                    label: { $0 == .onDevice ? "On-device (private)" : "Provider (Whisper)" })
            }

            labeled("PUSH-TO-TALK MODE", tokens: tokens) {
                AinkradSegmentedPicker(
                    items: PushToTalkMode.allCases,
                    selection: Binding(
                        get: { settings.document.mode },
                        set: { settings.setMode($0) }),
                    label: { $0 == .hold ? "Hold" : "Toggle" })
            }

            AinkradFormRow(title: "Auto-send after dictation") {
                AinkradToggle(isOn: Binding(
                    get: { settings.document.autoSend },
                    set: { settings.setAutoSend($0) }))
            }
            .padding(14)
            .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.45)))

            if settings.document.backend == .provider {
                providerSection(tokens: tokens)
            }

            labeled("LOCALE", tokens: tokens) {
                AinkradTextField(
                    text: Binding(
                        get: { settings.document.localeIdentifier },
                        set: { settings.setLocale($0) }),
                    placeholder: "en-US")
            }

            hotkeySection(tokens: tokens)
        }
    }

    // MARK: - Provider opt-in

    @ViewBuilder
    private func providerSection(tokens: DesignTokens) -> some View {
        AinkradFormRow(title: "Upload audio to provider (opt-in)") {
            AinkradToggle(isOn: Binding(
                get: { settings.document.providerOptIn },
                set: { settings.setProviderOptIn($0) }))
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.45)))

        if settings.document.providerOptIn {
            Text("Audio you dictate will be uploaded to the selected connection for transcription.")
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.accentTertiary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            if connections.connections.isEmpty {
                Text("Add a connection in the Connections section above to enable provider transcription.")
                    .font(AinkradFont.display(11)).foregroundStyle(tokens.foreground.opacity(0.45))
            } else {
                labeled("CONNECTION", tokens: tokens) {
                    AinkradSelect(
                        items: connections.connections.map(\.id),
                        selection: Binding(
                            get: { settings.document.providerConnectionID ?? connections.connections.first?.id ?? UUID() },
                            set: { settings.setProviderConnection($0) }),
                        label: { id in connections.connections.first { $0.id == id }?.displayName ?? "Connection" })
                }
                labeled("MODEL", tokens: tokens) {
                    AinkradTextField(
                        text: Binding(
                            get: { settings.document.providerModel },
                            set: { settings.setProviderModel($0) }),
                        placeholder: "whisper-1")
                }
            }
        }
    }

    // MARK: - Hotkey (read-only)

    private func hotkeySection(tokens: DesignTokens) -> some View {
        labeled("PUSH-TO-TALK HOTKEY", tokens: tokens) {
            HStack(spacing: 10) {
                Text(shortcuts.chord(for: .pushToTalk).displayString)
                    .font(AinkradFont.mono(12))
                    .foregroundStyle(tokens.foreground.opacity(0.85))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.6)))
                Text("Change in Settings \u{2192} Keyboard")
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
            }
        }
    }

    // MARK: - Shared row label (mirrors `AssistantSettingsView.labeled`)

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
