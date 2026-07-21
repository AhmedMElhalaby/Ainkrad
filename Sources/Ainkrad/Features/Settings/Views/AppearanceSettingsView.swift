import SwiftUI
import AinkradAppKit

/// The Ainkrad → Appearance section: a theme picker bound to `ThemeManager`.
/// Selecting a theme applies tokens immediately, with no Save button. The
/// Dock icon is a separate, independent manual preference — see the App Icon
/// section (`AppIconSettingsView`) — and is not affected by theme changes.
/// See Theme System.md and ADR-0006. Theme cards preview each theme's accent
/// ramp inside targeting brackets.
struct AppearanceSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion

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

                motionSection(tokens: tokens)
                    .padding(.top, 8)

                overlaysSection(tokens: tokens)
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

    // MARK: - Motion (Ainkrad-controlled, independent of the macOS system flag)

    private func motionSection(tokens: DesignTokens) -> some View {
        let store = environment.generalSettingsStore
        return VStack(alignment: .leading, spacing: 16) {
            SettingsSectionHeader(title: "MOTION", tokens: tokens)

            labeled("REDUCE MOTION", tokens: tokens) {
                segmented([true, false], selected: store.uiReduceMotion, tokens: tokens,
                          title: { $0 ? "On" : "Off" }, action: { store.setUiReduceMotion($0) })
            }
            Text("Turns off transitions, parallax, blinking cursors, and other animation across Ainkrad. Independent of the macOS system Reduce Motion setting.")
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.foreground.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Overlays (background opacity + blur)

    private func overlaysSection(tokens: DesignTokens) -> some View {
        let store = environment.generalSettingsStore
        return VStack(alignment: .leading, spacing: 16) {
            SettingsSectionHeader(title: "OVERLAYS", tokens: tokens)

            labeled("BACKGROUND OPACITY", tokens: tokens) {
                HStack(spacing: 12) {
                    AinkradSlider(
                        value: Binding(
                            get: { store.overlayBackgroundOpacity },
                            set: { store.setOverlayBackgroundOpacity($0) }
                        ),
                        in: 0.3...1.0
                    )
                    Text("\(Int(store.overlayBackgroundOpacity * 100))%")
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.foreground.opacity(0.55))
                        .frame(width: 42, alignment: .trailing)
                }
            }
            labeled("BACKGROUND BLUR", tokens: tokens) {
                segmented([true, false], selected: store.overlayBlurEnabled, tokens: tokens,
                          title: { $0 ? "On" : "Off" }, action: { store.setOverlayBlurEnabled($0) })
            }
            Text("Lower opacity (and blur) let the workspace show through the Launcher, Settings, App Store, and other overlays.")
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.foreground.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
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
        // Delegates to the kit segmented control; the imperative `action`
        // write-back rides in the binding's setter. `AinkradSegmentedPicker`
        // self-gates its selection motion, so the former host `.animation`
        // (folded from W7) lives inside the kit now.
        AinkradSegmentedPicker(
            items: items,
            selection: Binding(get: { selected }, set: { action($0) }),
            label: title
        )
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

    /// A row of preset accent swatches (one per theme's accent), an
    /// `AinkradColorPicker` HUD well for anything else, and a "Theme default"
    /// toggle that
    /// clears the override so the theme's own accent shows again.
    private func accentColorRow(tokens: DesignTokens, manager: ThemeManager) -> some View {
        let presets = Theme.allCases.map(\.tokens.accentPrimary)

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
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
                ChamferShape(cut: AinkradRadius.md)
                    .fill(isSelected ? tokens.accentPrimary.opacity(0.13) : tokens.surfaceElevated.opacity(0.5))
            )
            .overlay(
                ChamferShape(cut: AinkradRadius.md)
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isSelected)
    }
}

/// A section label in the HUD language: a small accent tick and an uppercase,
/// letter-spaced title. Shared across the Settings sections. Thin adapter that
/// delegates to the kit's `AinkradSectionHeader` — which renders its own accent
/// tick + uppercased tracked title from the injected theme/typography — so the
/// `(title:tokens:)` call sites (this file, SettingsOverlayView,
/// AssistantSettingsView) cascade unchanged. `tokens` is now unused: the kit
/// reads its palette from the environment.
struct SettingsSectionHeader: View {
    let title: String
    let tokens: DesignTokens
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.accentSecondary.opacity(0.85))
            }
            AinkradSectionHeader(title: title)
        }
    }
}
