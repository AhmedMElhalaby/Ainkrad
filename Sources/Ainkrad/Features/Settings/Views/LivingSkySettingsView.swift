import SwiftUI

/// Settings → Living Sky: the master animate switch, a speed control, and a
/// switch per ambient-sky effect. Bound to `SkySettingsStore`, persisted
/// immediately with no Save button — same pattern as the other Settings
/// sections. The island artwork itself is never animated; these control
/// only the sky around it.
struct LivingSkySettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    /// The speed presets exposed in the UI (the store accepts the full
    /// 0.5…1.5 band).
    private static let speedPresets: [(title: String, value: Double)] = [
        ("Calm", 0.6), ("Normal", 1.0), ("Lively", 1.5),
    ]

    var body: some View {
        let tokens = environment.themeManager.tokens
        let store = environment.skySettingsStore

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSectionHeader(title: "LIVING SKY", tokens: tokens)

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

                SettingsSectionHeader(title: "EFFECTS", tokens: tokens)

                Text("Switch each layer of the living sky individually. The island artwork itself is never animated.")
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))

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
            .padding(18)
        }
        .scrollContentBackground(.hidden)
    }

    private func speedRow(tokens: DesignTokens, store: SkySettingsStore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Motion speed")
                .font(AinkradFont.display(13, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.9))
            HStack(spacing: 6) {
                ForEach(Self.speedPresets, id: \.value) { preset in
                    let isSelected = abs(store.motionSpeed - preset.value) < 0.01
                    Button {
                        store.setMotionSpeed(preset.value)
                    } label: {
                        Text(preset.title)
                            .font(AinkradFont.display(12, weight: isSelected ? .medium : .regular))
                            .foregroundStyle(isSelected ? tokens.background : tokens.foreground.opacity(0.75))
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? tokens.accentPrimary.opacity(0.9) : tokens.surfaceElevated.opacity(0.5))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(tokens.accentPrimary.opacity(isSelected ? 0 : 0.15), lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
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
            NeonToggle(isOn: Binding(get: { isOn }, set: action), tokens: tokens)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
    }
}
