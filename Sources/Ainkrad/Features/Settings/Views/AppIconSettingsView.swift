import SwiftUI
import AppKit

/// The Ainkrad → App Icon section: choose the Dock icon independently of the
/// theme. `Auto` follows the active theme; `Blue`/`Purple` pin an explicit
/// icon a later theme change won't override (see `AppIconChoice`). Scoped to
/// the two shipped dark icons — the light-background variants remain future.
struct AppIconSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    private struct Option: Identifiable {
        let id: AppIconChoice
        let title: String
        let subtitle: String
    }

    private let options: [Option] = [
        Option(id: .auto, title: "Auto", subtitle: "Follows theme"),
        Option(id: .blue, title: "Neon Blue", subtitle: "Always blue"),
        Option(id: .purple, title: "Cyber Purple", subtitle: "Always purple"),
    ]

    var body: some View {
        let tokens = environment.themeManager.tokens

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionHeader(title: "APP ICON", tokens: tokens)

                HStack(spacing: 10) {
                    ForEach(options) { option in
                        card(option, tokens: tokens)
                    }
                }

                Text("The Dock and Finder icon. “Auto” tracks your theme; a fixed choice stays put when you switch themes.")
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
    }

    private func card(_ option: Option, tokens: DesignTokens) -> some View {
        let isSelected = environment.themeManager.appIcon == option.id

        return Button {
            environment.themeManager.setAppIcon(option.id)
        } label: {
            VStack(spacing: 8) {
                iconPreview(option.id, tokens: tokens)

                Text(option.title)
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(isSelected ? 0.95 : 0.7))
                Text(option.subtitle)
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(tokens.foreground.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
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

    /// Shows the concrete icon this option resolves to (Auto previews the
    /// current theme's icon), falling back to a tinted glyph if the asset is
    /// missing.
    @ViewBuilder
    private func iconPreview(_ choice: AppIconChoice, tokens: DesignTokens) -> some View {
        let resolved = choice.resolvedIcon(for: environment.themeManager.currentTheme)

        if let image = NSImage(named: resolved.assetName) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(resolved == .purple ? Color(hex: "7C1AED") : Color(hex: "2563EB"))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "app.dashed")
                        .foregroundStyle(.white.opacity(0.8))
                )
        }
    }
}
