import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Applies the Appearance step's choices to the live stores.
///
/// Order is load-bearing: `ThemeManager.setTheme` clears `accentColorHex`
/// (ThemeManager.swift:45), so the accent must be set afterwards or it is lost.
@MainActor
enum SetupAppearance {
    static func apply(theme: Theme, accentHex: String?,
                      family: UIFontFamily, scale: UIFontScale,
                      icon: AppIconChoice, iconAppearance: AppIconAppearance,
                      themeManager: ThemeManager, iconStore: AppIconStore) {
        themeManager.setTheme(theme)
        themeManager.setAccentColorHex(accentHex)
        themeManager.setFontFamily(family)
        themeManager.setFontScale(scale)
        iconStore.selectColor(icon)
        iconStore.selectAppearance(iconAppearance)
    }
}

/// The Appearance step: theme, accent, typography and app-icon controls,
/// each applying immediately to the live `ThemeManager` / `AppIconStore` —
/// the workspace is visible behind the blur, which is the entire reason
/// this step lives after bootstrap (Task 4 adopted the real vault). No Save
/// button, no draft state; styled to match `Features/Settings` so the
/// wizard and Settings do not diverge.
///
/// Controls that map onto a single store call (theme, font family/scale,
/// icon color/appearance) fire that setter directly. `SetupAppearance.apply`
/// is not used here: batching every control's current value through it on
/// every keystroke would fight the "apply immediately, independently" model
/// it exists for the *test* to pin the ordering trap on, not for the view to
/// route every change through.
struct SetupAppearanceStepView: View {
    @Environment(AppEnvironment.self) private var environment

    let coordinator: SetupCoordinator

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    themeSection(tokens: tokens)
                    typographySection(tokens: tokens)
                    appIconSection(tokens: tokens)
                }
                .padding(20)
            }

            HStack {
                Spacer(minLength: 0)
                AinkradButton(title: "Continue", style: .primary) {
                    coordinator.advance()
                }
            }
            .padding(20)
        }
    }

    // MARK: - Theme

    private func themeSection(tokens: DesignTokens) -> some View {
        let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 10)]
        return VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "THEME", tokens: tokens)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Theme.allCases, id: \.self) { theme in
                    themeCard(theme, tokens: tokens)
                }
            }
        }
    }

    private func themeCard(_ theme: Theme, tokens: DesignTokens) -> some View {
        let isSelected = environment.themeManager.currentTheme == theme
        let themeTokens = theme.tokens

        return Button {
            environment.themeManager.setTheme(theme)
        } label: {
            HStack(spacing: 11) {
                ChamferShape(cut: 7)
                    .fill(
                        LinearGradient(
                            colors: [themeTokens.accentPrimary, themeTokens.accentSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                    .overlay(
                        ChamferShape(cut: 7)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    )

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
                ChamferShape(cut: AinkradRadius.md)
                    .fill(isSelected ? tokens.accentPrimary.opacity(0.13) : tokens.surfaceElevated.opacity(0.5))
            )
            .overlay(
                ChamferShape(cut: AinkradRadius.md)
                    .strokeBorder(tokens.accentPrimary.opacity(isSelected ? 0.4 : 0.15), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Typography + accent

    private func typographySection(tokens: DesignTokens) -> some View {
        let manager = environment.themeManager

        return VStack(alignment: .leading, spacing: 16) {
            SettingsSectionHeader(title: "TYPOGRAPHY", tokens: tokens)

            labeled("FONT SIZE", tokens: tokens) {
                AinkradSegmentedPicker(
                    items: UIFontScale.allCases,
                    selection: Binding(get: { manager.uiFontScale }, set: { manager.setFontScale($0) }),
                    label: fontScaleTitle
                )
            }
            labeled("FONT FAMILY", tokens: tokens) {
                AinkradSegmentedPicker(
                    items: UIFontFamily.allCases,
                    selection: Binding(get: { manager.uiFontFamily }, set: { manager.setFontFamily($0) }),
                    label: fontFamilyTitle
                )
            }
            labeled("ACCENT COLOR", tokens: tokens) {
                accentColorRow(tokens: tokens, manager: manager)
            }
        }
    }

    /// Preset swatches (one per theme's accent) plus a color-well for
    /// anything else — the same pattern `AppearanceSettingsView` uses, so the
    /// wizard and Settings agree on how an accent is picked. A well over a
    /// palette-only picker is required here because the accent is a
    /// free-form 6-digit hex, not one of a fixed set — restricting the
    /// wizard to presets while Settings allows any color would be a
    /// regression the moment the user opens Settings afterward.
    private func accentColorRow(tokens: DesignTokens, manager: ThemeManager) -> some View {
        let presets = Theme.allCases.map(\.tokens.accentPrimary)

        return HStack(spacing: 10) {
            ForEach(Array(presets.enumerated()), id: \.offset) { _, color in
                accentSwatch(color, tokens: tokens, manager: manager)
            }
            AinkradColorPicker(
                selection: Binding(
                    get: { manager.accentColorHex.map { Color(hex: $0) } ?? tokens.accentPrimary },
                    set: { manager.setAccentColorHex($0.hexString) }
                )
            )
            .frame(width: 26, height: 26)
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

    // MARK: - App icon

    private func appIconSection(tokens: DesignTokens) -> some View {
        let store = environment.appIconStore
        return VStack(alignment: .leading, spacing: 16) {
            SettingsSectionHeader(title: "APP ICON", tokens: tokens)

            labeled("COLOR", tokens: tokens) {
                AinkradSegmentedPicker(
                    items: AppIconChoice.allCases,
                    selection: Binding(get: { store.choice }, set: { store.selectColor($0) }),
                    label: iconColorTitle
                )
            }
            labeled("APPEARANCE", tokens: tokens) {
                AinkradSegmentedPicker(
                    items: AppIconAppearance.allCases,
                    selection: Binding(get: { store.appearance }, set: { store.selectAppearance($0) }),
                    label: iconAppearanceTitle
                )
            }
        }
    }

    // MARK: - Helpers

    private func labeled<Content: View>(_ title: String, tokens: DesignTokens,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(AinkradFont.display(10, weight: .medium)).kerning(0.6)
                .foregroundStyle(tokens.foreground.opacity(0.45))
            content()
        }
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

    private func iconColorTitle(_ c: AppIconChoice) -> String {
        switch c { case .auto: return "Auto"; case .blue: return "Blue"; case .purple: return "Purple" }
    }

    private func iconAppearanceTitle(_ a: AppIconAppearance) -> String {
        switch a { case .system: return "System"; case .light: return "Light"; case .dark: return "Dark" }
    }
}
