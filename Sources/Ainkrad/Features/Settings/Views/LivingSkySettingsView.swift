import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Settings → Living Sky: the master animate switch, a speed control, and a
/// switch per ambient-sky effect. Bound to `SkySettingsStore`, persisted
/// immediately with no Save button — same pattern as the other Settings
/// sections. The island artwork itself is never animated; these control
/// only the sky around it.
struct LivingSkySettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    // The speed presets now live on `SkySettingsStore` (`speedPresets`),
    // because the first-run Motion & Sound step renders the same control and
    // the two must not drift apart.

    var body: some View {
        let tokens = environment.themeManager.tokens
        let store = environment.skySettingsStore

        return VStack(alignment: .leading, spacing: 16) {
            AinkradSettingsPanel(title: "Living sky",
                                 hint: "The animated backdrop behind the workspace.") {
                VStack(alignment: .leading, spacing: 16) {
                    toggleRow(
                        tokens: tokens,
                        title: "Animate the sky",
                        subtitle: "Freezes every ambient effect in place when off — the scene stays, the motion stops.",
                        isOn: store.motionEnabled,
                        action: { store.setMotionEnabled($0) }
                    )

                    if store.motionEnabled {
                        speedRow(tokens: tokens, store: store)
                    }
                }
            }

            AinkradSettingsPanel(title: "Effects",
                                 hint: "Switch each layer of the living sky individually. The island artwork itself is never animated.") {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(SkyEffect.allCases) { effect in
                        toggleRow(
                            tokens: tokens,
                            title: effect.displayName,
                            subtitle: effect.effectDescription,
                            isOn: store.isEnabled(effect),
                            action: { store.setEnabled($0, for: effect) }
                        )
                    }
                }
            }
        }
    }

    private func speedRow(tokens: DesignTokens, store: SkySettingsStore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Motion speed")
                .font(AinkradFont.display(13, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.9))
            AinkradSegmentedPicker(
                items: SkySettingsStore.speedPresets.map(\.value),
                selection: Binding(
                    get: { SkySettingsStore.nearestPreset(to: store.motionSpeed) },
                    set: { store.setMotionSpeed($0) }
                ),
                label: { SkySettingsStore.presetTitle($0) }
            )
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
    }

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
