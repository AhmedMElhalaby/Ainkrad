import SwiftUI

/// The General tab: global preferences. For M1 this is the Appearance
/// section only — a two-option theme picker bound to `ThemeManager`.
/// Selecting a theme applies tokens and swaps the Dock icon immediately,
/// with no Save button. See Theme System.md and ADR-0006. Styled to the
/// app's HUD language: a kerned section header and theme cards that preview
/// each theme's accents inside targeting brackets.
struct GeneralSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    private static let themeDisplayNames: [Theme: String] = [
        .neonBlue: "Neon Blue",
        .cyberPurple: "Cyber Purple",
    ]

    var body: some View {
        let tokens = environment.themeManager.tokens

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionHeader(title: "APPEARANCE", tokens: tokens)

                HStack(spacing: 10) {
                    ForEach(Theme.allCases, id: \.self) { theme in
                        themeCard(theme, tokens: tokens)
                    }
                }
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
    }

    private func themeCard(_ theme: Theme, tokens: DesignTokens) -> some View {
        let isSelected = environment.themeManager.currentTheme == theme
        let themeTokens = theme.tokens

        return Button {
            environment.themeManager.setTheme(theme)
        } label: {
            HStack(spacing: 11) {
                // Live preview of this theme's accent ramp.
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(
                            colors: [themeTokens.accentPrimary, themeTokens.accentSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: themeTokens.accentPrimary.opacity(isSelected ? 0.6 : 0), radius: 8)

                Text(Self.themeDisplayNames[theme] ?? theme.rawValue)
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(isSelected ? 0.95 : 0.7))

                Spacer(minLength: 4)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? tokens.accentSecondary : tokens.foreground.opacity(0.25))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? tokens.accentPrimary.opacity(0.13) : tokens.surfaceElevated.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(tokens.accentPrimary.opacity(isSelected ? 0.4 : 0.15), lineWidth: 1)
            )
            .overlay(
                TargetingBrackets(length: 9)
                    .stroke(isSelected ? tokens.accentSecondary.opacity(0.9) : .clear, lineWidth: 1.4)
                    .padding(1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.14), value: isSelected)
    }
}

/// A section label in the HUD language: a small accent tick and an
/// uppercase, letter-spaced title. Shared across the Settings tabs.
struct SettingsSectionHeader: View {
    let title: String
    let tokens: DesignTokens

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1)
                .fill(tokens.accentSecondary)
                .frame(width: 3, height: 12)
                .shadow(color: tokens.accentSecondary.opacity(0.8), radius: 4)
            Text(title)
                .font(AinkradFont.display(11, weight: .semibold))
                .kerning(3)
                .foregroundStyle(tokens.foreground.opacity(0.55))
        }
    }
}
