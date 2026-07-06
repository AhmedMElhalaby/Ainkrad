import SwiftUI

/// The Settings overlay — the third summonable panel (⌘, or the Launcher's
/// Settings entry), in the same HUD language as the Launcher and Workspace
/// Overview. A left grouped sidebar (AINKRAD / BUILT-IN APPS) selects a
/// section shown in the detail pane on the right. See Settings Overlay Panel
/// — Direction.md.
struct SettingsOverlayView: View {
    @Environment(AppEnvironment.self) private var environment
    let onDismiss: () -> Void

    @State private var selection: SettingsSection

    /// `focusedAppID` opens the overlay directly on that app's settings —
    /// e.g. summoning Settings while a Terminal is focused lands on Terminal.
    init(focusedAppID: String? = nil, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        _selection = State(initialValue: focusedAppID.map { .app($0) } ?? .appearance)
    }

    /// A value snapshot of a registered app for the sidebar — iterating
    /// `BuiltInApp.Type` metatypes in a SwiftUI container crashes the Xcode 27
    /// beta SILGen, so rows carry plain values and the metatype is looked back
    /// up by id when its settings view is needed.
    private struct AppEntry: Identifiable {
        let id: String
        let displayName: String
        let icon: String
    }

    private enum SettingsSection: Hashable {
        case appearance
        case appIcon
        case shortcuts
        case app(String)
    }

    /// Only enabled apps get a settings section — a disabled app is hidden here
    /// just as it is in the Launcher (`LauncherStore` filters `enabledApps`).
    private var appEntries: [AppEntry] {
        environment.registry.enabledApps.map { AppEntry(id: $0.id, displayName: $0.displayName, icon: $0.icon) }
    }

    var body: some View {
        let tokens = environment.themeManager.tokens

        GeometryReader { geo in
            ZStack {
                Color.black.opacity(OverlayChrome.backdropOpacity)
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }

                panel(tokens: tokens)
                    .frame(
                        width: min(max(820, geo.size.width * 0.78), 1040),
                        height: min(max(560, geo.size.height * 0.82), 720)
                    )
                    .offset(y: -30)
            }
        }
    }

    private func panel(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(tokens: tokens)

            LinearGradient(
                colors: [.clear, tokens.accentPrimary.opacity(0.5), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)

            HStack(spacing: 0) {
                sidebar(tokens: tokens)

                LinearGradient(
                    colors: [.clear, tokens.accentPrimary.opacity(0.35), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 1)

                detail(tokens: tokens)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .hudPanelChrome(tokens: tokens)
        .onKeyPress(.escape) { onDismiss(); return .handled }
    }

    private func header(tokens: DesignTokens) -> some View {
        HStack(spacing: 12) {
            ChevronMark()
                .fill(tokens.accentSecondary)
                .frame(width: 16, height: 14)
                .shadow(color: tokens.accentSecondary.opacity(0.9), radius: 6)
            Text("SETTINGS")
                .font(AinkradFont.display(13, weight: .semibold))
                .kerning(4)
                .foregroundStyle(tokens.foreground.opacity(0.9))
            Spacer()
            Text("esc")
                .font(AinkradFont.mono(9))
                .foregroundStyle(tokens.foreground.opacity(0.35))
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }

    // MARK: - Sidebar

    private func sidebar(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            groupLabel("AINKRAD", tokens: tokens)
            sidebarRow(.appearance, title: "Appearance", systemIcon: "paintbrush", tokens: tokens)
            sidebarRow(.appIcon, title: "App Icon", systemIcon: "app.badge", tokens: tokens)
            sidebarRow(.shortcuts, title: "Keyboard", systemIcon: "keyboard", tokens: tokens)

            groupLabel("BUILT-IN APPS", tokens: tokens)
                .padding(.top, 12)
            ForEach(appEntries) { app in
                sidebarRow(.app(app.id), title: app.displayName, appID: app.id, systemIcon: app.icon, tokens: tokens)
            }

            Spacer()
        }
        .padding(12)
        .frame(width: 208, alignment: .topLeading)
    }

    private func groupLabel(_ text: String, tokens: DesignTokens) -> some View {
        Text(text)
            .font(AinkradFont.mono(9, weight: .medium))
            .kerning(2.5)
            .foregroundStyle(tokens.foreground.opacity(0.4))
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
    }

    private func sidebarRow(
        _ section: SettingsSection,
        title: String,
        appID: String? = nil,
        systemIcon: String,
        tokens: DesignTokens
    ) -> some View {
        let isSelected = selection == section

        return Button {
            selection = section
        } label: {
            HStack(spacing: 10) {
                rowIcon(appID: appID, systemIcon: systemIcon, isSelected: isSelected, tokens: tokens)
                Text(title)
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(isSelected ? 0.95 : 0.7))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? tokens.accentPrimary.opacity(0.14) : .clear)
            )
            .overlay(
                TargetingBrackets(length: 7)
                    .stroke(isSelected ? tokens.accentSecondary.opacity(0.9) : .clear, lineWidth: 1.3)
                    .padding(1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    /// App rows use the neon tile artwork (Launcher-matching); fixed sections
    /// use a tinted SF Symbol.
    @ViewBuilder
    private func rowIcon(appID: String?, systemIcon: String, isSelected: Bool, tokens: DesignTokens) -> some View {
        let assetName = appID.map { "AppTile-\($0)-\(environment.themeManager.currentTheme.rawValue)" }

        if let assetName, NSImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: systemIcon)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? tokens.accentSecondary : tokens.foreground.opacity(0.55))
                .frame(width: 22, height: 22)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private func detail(tokens: DesignTokens) -> some View {
        switch selection {
        case .appearance:
            AppearanceSettingsView()
        case .appIcon:
            AppIconSettingsView()
        case .shortcuts:
            ShortcutsSettingsView()
        case .app(let id):
            // Look up among enabled apps only: a disabled app has no settings
            // section, and if the selected app is disabled while the overlay is
            // open its detail falls back to blank rather than lingering.
            if let app = environment.registry.enabledApps.first(where: { $0.id == id }) {
                app.makeSettingsView()
            } else {
                Color.clear
            }
        }
    }
}
