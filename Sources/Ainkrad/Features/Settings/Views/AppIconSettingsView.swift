import SwiftUI
import AinkradAppKit

/// Settings → App Icon: manual picker for the running app's Dock icon.
/// COLOR (Auto/Blue/Purple; Auto follows the theme) and APPEARANCE
/// (System/Light/Dark; Light/Dark pin one variant), with a live preview.
struct AppIconSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let tokens = environment.themeManager.tokens
        let store = environment.appIconStore
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSectionHeader(title: "APP ICON", tokens: tokens)

                Text("Choose the Dock icon. Auto follows your theme; System follows the Dock's light/dark.")
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))

                preview(store: store, tokens: tokens)

                labeled("COLOR", tokens: tokens) {
                    AinkradSegmentedPicker(
                        items: AppIconChoice.allCases,
                        selection: Binding(get: { store.choice }, set: { store.selectColor($0) }),
                        label: colorTitle
                    )
                }
                labeled("APPEARANCE", tokens: tokens) {
                    AinkradSegmentedPicker(
                        items: AppIconAppearance.allCases,
                        selection: Binding(get: { store.appearance }, set: { store.selectAppearance($0) }),
                        label: appearanceTitle
                    )
                }
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
    }

    // The resolved icon for the current selection (preview uses the current
    // system appearance for `.system`).
    private func preview(store: AppIconStore, tokens: DesignTokens) -> some View {
        let systemDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let name = AppIconResolver.resourceName(for: store.choice, theme: environment.themeManager.currentTheme,
                                                appearance: store.appearance, systemDark: systemDark)
        return HStack {
            Spacer()
            Group {
                if let url = Bundle.main.url(forResource: name, withExtension: "icns"),
                   let img = NSImage(contentsOf: url) {
                    Image(nsImage: img).resizable().scaledToFit()
                } else {
                    ChamferShape(cut: 20).fill(tokens.surfaceElevated)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(ChamferShape(cut: 22))
            Spacer()
        }
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

    private func colorTitle(_ c: AppIconChoice) -> String {
        switch c { case .auto: return "Auto"; case .blue: return "Blue"; case .purple: return "Purple" }
    }
    private func appearanceTitle(_ a: AppIconAppearance) -> String {
        switch a { case .system: return "System"; case .light: return "Light"; case .dark: return "Dark" }
    }
}
