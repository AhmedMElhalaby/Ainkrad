import SwiftUI
import AppKit

/// The Built-in Apps tab: every registered app (`registry.allApps`, so
/// disabled apps stay visible) with an enable/disable toggle, and a
/// drill-in to the app's own settings view via its factory. Layout chrome
/// only — per-app settings content belongs to the owning app's module.
/// See Navigation & Settings Architecture.md. Rows use the neon tile
/// language of the Launcher rather than a stock List.
struct BuiltInAppsSettingsView: View {
    /// Plain value snapshot of a registered app's display fields. Iterating
    /// SwiftUI Lists over `BuiltInApp.Type` metatypes directly crashes the
    /// Swift 6 (Xcode 27 beta) SILGen — rows carry values, and the metatype
    /// is looked back up by id only where a factory call is needed.
    private struct AppRow: Identifiable {
        let id: String
        let displayName: String
        let icon: String
    }

    @Environment(AppEnvironment.self) private var environment
    @State private var selectedAppID: String?

    private var appRows: [AppRow] {
        environment.registry.allApps.map { AppRow(id: $0.id, displayName: $0.displayName, icon: $0.icon) }
    }

    var body: some View {
        let tokens = environment.themeManager.tokens

        if let selectedAppID, let app = environment.registry.allApps.first(where: { $0.id == selectedAppID }) {
            detail(app: app, tokens: tokens)
        } else {
            appList(tokens: tokens)
        }
    }

    private func detail(app: BuiltInApp.Type, tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                selectedAppID = nil
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Built-in Apps")
                        .font(AinkradFont.display(12, weight: .medium))
                }
                .foregroundStyle(tokens.accentSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(14)

            LinearGradient(
                colors: [.clear, tokens.accentPrimary.opacity(0.35), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)

            app.makeSettingsView()
        }
    }

    private func appList(tokens: DesignTokens) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionHeader(title: "BUILT-IN APPS", tokens: tokens)

                VStack(spacing: 8) {
                    ForEach(appRows) { app in
                        row(app, tokens: tokens)
                    }
                }
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
    }

    private func row(_ app: AppRow, tokens: DesignTokens) -> some View {
        HStack(spacing: 12) {
            appTile(app, tokens: tokens)

            Text(app.displayName)
                .font(AinkradFont.display(13, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.9))

            Spacer()

            NeonToggle(
                isOn: Binding(
                    get: { environment.registry.isEnabled(app.id) },
                    set: { environment.registry.setEnabled($0, for: app.id) }
                ),
                tokens: tokens
            )

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tokens.foreground.opacity(0.35))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(tokens.surfaceElevated.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedAppID = app.id }
    }

    /// The app's neon tile artwork, matching the Launcher rows; falls back
    /// to the themed SF Symbol mini-tile.
    @ViewBuilder
    private func appTile(_ app: AppRow, tokens: DesignTokens) -> some View {
        let assetName = "AppTile-\(app.id)-\(environment.themeManager.currentTheme.rawValue)"

        if NSImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(tokens.surface)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: app.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(tokens.accentSecondary)
                )
        }
    }
}

/// A neon capsule toggle in place of the stock macOS switch: the track
/// lights with the accent when on, the knob carries a soft glow.
struct NeonToggle: View {
    @Binding var isOn: Bool
    let tokens: DesignTokens

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? tokens.accentPrimary.opacity(0.9) : tokens.surface)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isOn ? tokens.accentSecondary.opacity(0.65) : tokens.foreground.opacity(0.18),
                                lineWidth: 1
                            )
                    )

                Circle()
                    .fill(.white)
                    .padding(3)
                    .shadow(color: isOn ? tokens.accentSecondary.opacity(0.7) : .black.opacity(0.4), radius: 3)
            }
            .frame(width: 40, height: 22)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.16), value: isOn)
    }
}
