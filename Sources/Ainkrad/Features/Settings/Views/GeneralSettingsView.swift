import SwiftUI

/// Settings → General: the full-screen status bar toggle (AIN-109) and the
/// sound effects toggle + volume slider (AIN-108). Bound to
/// `GeneralSettingsStore`, persisted immediately with no Save button — same
/// pattern as the other Settings sections.
struct GeneralSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let tokens = environment.themeManager.tokens
        let store = environment.generalSettingsStore

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSectionHeader(title: "GENERAL", tokens: tokens)

                row(tokens: tokens,
                    title: "Show status bar in full-screen",
                    subtitle: "Clock, network, and battery in the title strip while full-screen.",
                    isOn: store.showFullScreenStatusBar,
                    action: { store.setShowFullScreenStatusBar($0) })

                row(tokens: tokens,
                    title: "Sound effects",
                    subtitle: "Plays a short chime on HUD open/close, install, and other key actions.",
                    isOn: store.soundEnabled,
                    action: { store.setSoundEnabled($0) })

                if store.soundEnabled {
                    volumeRow(tokens: tokens, store: store)
                }
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
    }

    private func volumeRow(tokens: DesignTokens, store: GeneralSettingsStore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Volume")
                .font(AinkradFont.display(13, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.9))
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
                Slider(
                    value: Binding(
                        get: { store.soundVolume },
                        set: { store.setSoundVolume($0) }
                    ),
                    in: 0...1
                )
                .tint(tokens.accentPrimary)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
    }

    private func row(tokens: DesignTokens, title: String, subtitle: String,
                      isOn: Bool, action: @escaping (Bool) -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.9))
                Text(subtitle)
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
            }
            Spacer(minLength: 12)
            NeonToggle(isOn: Binding(get: { isOn }, set: action), tokens: tokens)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
    }
}
