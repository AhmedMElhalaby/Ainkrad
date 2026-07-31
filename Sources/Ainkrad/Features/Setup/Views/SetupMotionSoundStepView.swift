import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Applies the Motion & Sound step's choices to the live stores.
///
/// `SkySettingsStore.setMotionSpeed` clamps to `speedRange` (0.5...1.5);
/// `GeneralSettingsStore.setSoundVolume` does not clamp, so the view must not
/// offer a value outside 0...1.
@MainActor
enum SetupMotionSound {
    static func apply(reduceMotion: Bool, skyMotion: Bool, skySpeed: Double,
                      soundEnabled: Bool, volume: Double,
                      general: GeneralSettingsStore, sky: SkySettingsStore) {
        general.setUiReduceMotion(reduceMotion)
        sky.setMotionEnabled(skyMotion)
        sky.setMotionSpeed(skySpeed)
        general.setSoundEnabled(soundEnabled)
        general.setSoundVolume(volume)
    }
}

/// The Motion & Sound step: reduce-motion, the living-sky animation, and
/// sound effects, each applying immediately to the live `GeneralSettingsStore`
/// / `SkySettingsStore` — the animated sky is rendering live behind the blur,
/// so these changes are visible the instant they're made. No Save button, no
/// draft state; styled to match `Features/Settings` so the wizard and
/// Settings do not diverge.
///
/// `SetupMotionSound.apply` exists for the applier test, not for this view:
/// each control fires its own store setter directly, the same
/// apply-immediately-and-independently model `SetupAppearanceStepView` uses.
///
/// Reduce-motion prominence: it gets its own section, first, above the sky
/// and sound sections — not folded into the sky's toggle list. It is the one
/// setting in this step whose default (motion on) is wrong for some people in
/// a way they feel immediately (vestibular discomfort from the parallax sky
/// and animated islands), and first-run is the only moment the app will ever
/// ask. A short line names *why* it exists rather than just what it does.
///
/// Sky effects: the wizard exposes only the master "Animate the sky" switch
/// and its speed, not the 14 individual `SkyEffect` toggles — those stay a
/// Settings → Living Sky concern. Surfacing all 14 here would turn a
/// first-run pass into a control panel; a curated subset would create a
/// second, incomplete copy of a list Settings already renders in full. The
/// master switch is the one sky decision that matters at first run (animated
/// vs. static); anyone who wants finer control already knows to look in
/// Settings, and this step's Continue never forecloses that.
struct SetupMotionSoundStepView: View {
    @Environment(AppEnvironment.self) private var environment

    let coordinator: SetupCoordinator

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    reduceMotionSection(tokens: tokens)
                    skySection(tokens: tokens)
                    soundSection(tokens: tokens)
                }
                .padding(20)
            }

            // Never blocking, for the same reason as Appearance: every control
            // has a real default already applied live.
            SetupStepFooter(coordinator: coordinator) { coordinator.advance() }
        }
    }

    // MARK: - Reduce motion (given prominence — see the type doc)

    private func reduceMotionSection(tokens: DesignTokens) -> some View {
        let store = environment.generalSettingsStore
        return VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "MOTION", tokens: tokens)
            toggleRow(
                tokens: tokens,
                title: "Reduce motion",
                subtitle: "Turns off animation across the app — parallax, transitions, and the "
                    + "living sky. This is the only time Ainkrad will ask; change it later in "
                    + "Settings → Appearance.",
                isOn: store.uiReduceMotion,
                action: { store.setUiReduceMotion($0) }
            )
        }
    }

    // MARK: - Living sky

    private func skySection(tokens: DesignTokens) -> some View {
        let store = environment.skySettingsStore
        return VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "LIVING SKY", tokens: tokens)
            toggleRow(
                tokens: tokens,
                title: "Animate the sky",
                subtitle: "Freezes every ambient effect in place when off — the scene stays, "
                    + "the motion stops. Fine-tune individual effects later in Settings.",
                isOn: store.motionEnabled,
                action: { store.setMotionEnabled($0) }
            )
            if store.motionEnabled {
                speedRow(tokens: tokens, store: store)
            }
        }
    }

    private func speedRow(tokens: DesignTokens, store: SkySettingsStore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Motion speed")
                .font(AinkradFont.display(13, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.9))
            HStack(spacing: 10) {
                Image(systemName: "tortoise.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
                AinkradSlider(
                    value: Binding(
                        get: { store.motionSpeed },
                        set: { store.setMotionSpeed($0) }
                    ),
                    in: SkySettingsStore.speedRange
                )
                Image(systemName: "hare.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
            }
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Sound

    private func soundSection(tokens: DesignTokens) -> some View {
        let store = environment.generalSettingsStore
        return VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "SOUND", tokens: tokens)
            toggleRow(
                tokens: tokens,
                title: "Sound effects",
                subtitle: "Plays a short chime on HUD open/close, install, and other key actions.",
                isOn: store.soundEnabled,
                action: { store.setSoundEnabled($0) }
            )
            if store.soundEnabled {
                volumeRow(tokens: tokens, store: store)
            }
        }
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
                // Bounded to 0...1 in the view: `setSoundVolume` does not clamp,
                // so `AinkradSlider`'s own `in:` range is what keeps this safe.
                AinkradSlider(
                    value: Binding(
                        get: { store.soundVolume },
                        set: { store.setSoundVolume($0) }
                    ),
                    in: 0...1
                )
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
            }
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Shared row

    private func toggleRow(tokens: DesignTokens, title: String, subtitle: String,
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
            AinkradToggle(isOn: Binding(get: { isOn }, set: action))
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
    }
}
