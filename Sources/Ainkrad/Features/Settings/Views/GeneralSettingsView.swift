import SwiftUI
import AinkradAppKit

/// Settings → General: the full-screen status bar toggle (AIN-109). Sound
/// effects now live in their own `SoundSettingsView` section. Bound to
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

                launcherLayoutRow(tokens: tokens, store: store)
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
    }

    private func launcherLayoutRow(tokens: DesignTokens, store: GeneralSettingsStore) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Launcher layout")
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.9))
                Text("Show apps in the ⌘K launcher as a list or a grid of icons.")
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
            }
            Spacer(minLength: 12)
            AinkradSegmentedPicker(
                items: LauncherViewMode.allCases,
                selection: Binding(get: { store.launcherViewMode }, set: { store.setLauncherViewMode($0) }),
                label: { $0.label }
            )
            .fixedSize()
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
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
            AinkradToggle(isOn: Binding(get: { isOn }, set: action))
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
    }
}
