import SwiftUI

/// The Ainkrad → Appearance section: a theme picker bound to `ThemeManager`.
/// Selecting a theme applies tokens immediately, with no Save button. The
/// Dock icon is a separate, independent manual preference — see the App Icon
/// section (`AppIconSettingsView`) — and is not affected by theme changes.
/// See Theme System.md and ADR-0006. Theme cards preview each theme's accent
/// ramp inside targeting brackets.
struct AppearanceSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 10)]

    var body: some View {
        let tokens = environment.themeManager.tokens

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionHeader(title: "APPEARANCE", tokens: tokens)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Theme.allCases, id: \.self) { theme in
                        themeCard(theme, tokens: tokens)
                    }
                }

                typographySection(tokens: tokens)
                    .padding(.top, 8)
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Typography (AIN-143: font size/family + custom accent color)

    private func typographySection(tokens: DesignTokens) -> some View {
        let manager = environment.themeManager

        return VStack(alignment: .leading, spacing: 16) {
            SettingsSectionHeader(title: "TYPOGRAPHY", tokens: tokens)

            labeled("FONT SIZE", tokens: tokens) {
                segmented(UIFontScale.allCases, selected: manager.uiFontScale, tokens: tokens,
                          title: fontScaleTitle, action: { manager.setFontScale($0) })
            }
            labeled("FONT FAMILY", tokens: tokens) {
                segmented(UIFontFamily.allCases, selected: manager.uiFontFamily, tokens: tokens,
                          title: fontFamilyTitle, action: { manager.setFontFamily($0) })
            }
            labeled("ACCENT COLOR", tokens: tokens) {
                accentColorRow(tokens: tokens, manager: manager)
            }
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

    private func segmented<T: Hashable>(_ items: [T], selected: T, tokens: DesignTokens,
                                        title: @escaping (T) -> String, action: @escaping (T) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                let isSel = item == selected
                Button { action(item) } label: {
                    Text(title(item))
                        .font(AinkradFont.display(12, weight: isSel ? .medium : .regular))
                        .foregroundStyle(isSel ? tokens.background : tokens.foreground.opacity(0.75))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 8).fill(isSel ? tokens.accentPrimary.opacity(0.9) : tokens.surfaceElevated.opacity(0.5)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tokens.accentPrimary.opacity(isSel ? 0 : 0.15), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.14), value: selected)
    }

    private func fontScaleTitle(_ scale: UIFontScale) -> String {
        switch scale { case .small: return "Small"; case .medium: return "Medium"; case .large: return "Large" }
    }

    private func fontFamilyTitle(_ family: UIFontFamily) -> String {
        switch family {
        case .exo2: return "Exo 2"
        case .jetBrainsMono: return "JetBrains Mono"
        case .system: return "System"
        }
    }

    /// A row of preset accent swatches (one per theme's accent), a native
    /// `ColorPicker` for anything else, and a "Theme default" toggle that
    /// clears the override so the theme's own accent shows again.
    private func accentColorRow(tokens: DesignTokens, manager: ThemeManager) -> some View {
        let presets = Theme.allCases.map(\.tokens.accentPrimary)

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                ForEach(Array(presets.enumerated()), id: \.offset) { _, color in
                    accentSwatch(color, tokens: tokens, manager: manager)
                }
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { manager.accentColorHex.map { Color(hex: $0) } ?? tokens.accentPrimary },
                        set: { manager.setAccentColorHex($0.hexString) }
                    )
                )
                .labelsHidden()
                .frame(width: 26, height: 26)
            }

            Button {
                manager.setAccentColorHex(nil)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: manager.accentColorHex == nil ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11))
                    Text("Theme default")
                        .font(AinkradFont.display(11))
                }
                .foregroundStyle(manager.accentColorHex == nil ? tokens.accentSecondary : tokens.foreground.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    private func accentSwatch(_ color: Color, tokens: DesignTokens, manager: ThemeManager) -> some View {
        let isSelected = manager.accentColorHex != nil && manager.accentColorHex == color.hexString
        return Button {
            manager.setAccentColorHex(color.hexString)
        } label: {
            Circle()
                .fill(color)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle().strokeBorder(
                        isSelected ? tokens.foreground.opacity(0.9) : .white.opacity(0.18),
                        lineWidth: isSelected ? 2 : 1
                    )
                )
        }
        .buttonStyle(.plain)
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

                Text(theme.displayName)
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

/// A section label in the HUD language: a small accent tick and an uppercase,
/// letter-spaced title. Shared across the Settings sections.
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
