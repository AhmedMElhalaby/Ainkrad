import SwiftUI

/// The General tab: global preferences. For M1 this is the Appearance
/// section only — a two-option theme picker bound to `ThemeManager`.
/// Selecting a theme applies tokens and swaps the Dock icon immediately,
/// with no Save button. See Theme System.md and ADR-0006.
struct GeneralSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    private static let themeDisplayNames: [Theme: String] = [
        .neonBlue: "Neon Blue",
        .cyberPurple: "Cyber Purple",
    ]

    var body: some View {
        let tokens = environment.themeManager.tokens

        Form {
            Section("Appearance") {
                Picker("Theme", selection: Binding(
                    get: { environment.themeManager.currentTheme },
                    set: { environment.themeManager.setTheme($0) }
                )) {
                    ForEach(Theme.allCases, id: \.self) { theme in
                        Text(Self.themeDisplayNames[theme] ?? theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .foregroundStyle(tokens.foreground)
    }
}
