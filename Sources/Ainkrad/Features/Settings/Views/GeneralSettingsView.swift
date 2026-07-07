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
                    title: "Animate home island",
                    subtitle: "Drifting clouds, bobbing islets, and the reactive glow on the home screen. Independent of macOS Reduce Motion.",
                    isOn: store.animateHomeIsland,
                    action: { store.setAnimateHomeIsland($0) })

                row(tokens: tokens,
                    title: "Sound effects",
                    subtitle: "Plays a short chime on HUD open/close, install, and other key actions.",
                    isOn: store.soundEnabled,
                    action: { store.setSoundEnabled($0) })

                if store.soundEnabled {
                    volumeRow(tokens: tokens, store: store)

                    SettingsSectionHeader(title: "SOUND EFFECTS", tokens: tokens)

                    Text("Enable each cue individually and choose which effect it plays. ▶ previews the selected effect.")
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.foreground.opacity(0.5))

                    ForEach(UISound.allCases) { event in
                        soundEventRow(tokens: tokens, store: store, event: event)
                    }
                }
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
    }

    /// One per-event row: name + when-it-fires, an effect chooser, a preview
    /// button, and the enable toggle. Disabled events keep their chooser
    /// visible (dimmed) so a user can re-pick before re-enabling.
    private func soundEventRow(tokens: DesignTokens, store: GeneralSettingsStore, event: UISound) -> some View {
        let isOn = store.isEventEnabled(event)
        let chosen = store.effect(for: event)

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.displayName)
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(isOn ? 0.9 : 0.45))
                Text(event.eventDescription)
                    .font(AinkradFont.display(10))
                    .foregroundStyle(tokens.foreground.opacity(isOn ? 0.45 : 0.3))
            }

            Spacer(minLength: 12)

            Menu {
                ForEach(UISound.allCases) { effect in
                    Button {
                        store.setEffect(effect, for: event)
                        environment.sounds.preview(effect)
                    } label: {
                        if effect == chosen {
                            Label(effectLabel(effect, for: event), systemImage: "checkmark")
                        } else {
                            Text(effectLabel(effect, for: event))
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(effectLabel(chosen, for: event))
                        .font(AinkradFont.display(11))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(tokens.foreground.opacity(isOn ? 0.75 : 0.4))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(tokens.surfaceElevated.opacity(0.9)))
                .overlay(Capsule().strokeBorder(tokens.accentPrimary.opacity(0.2), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button {
                environment.sounds.preview(chosen)
            } label: {
                Image(systemName: "play.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(tokens.accentSecondary.opacity(isOn ? 0.9 : 0.5))
            }
            .buttonStyle(.plain)
            .help("Preview")

            NeonToggle(isOn: Binding(get: { isOn }, set: { store.setEventEnabled($0, for: event) }), tokens: tokens)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
    }

    /// Chooser labels: the event's own sound reads as "Default (name)" so the
    /// out-of-the-box mapping is recognizable at a glance.
    private func effectLabel(_ effect: UISound, for event: UISound) -> String {
        effect == event ? "Default (\(effect.displayName))" : effect.displayName
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
