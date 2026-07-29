import SwiftUI
import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime

/// The Settings overlay — the third summonable panel (⌘, or the Launcher's
/// Settings entry), in the same HUD language as the Launcher and Workspace
/// Overview. A left grouped sidebar (AINKRAD / BUILT-IN APPS) selects a
/// section shown in the detail pane on the right. See Settings Overlay Panel
/// — Direction.md.
///
/// Every section — WORKSPACE, INTELLIGENCE, BUILT-IN APPS, INSTALLED — is
/// catalog-driven; the sidebar and detail pane both read from
/// `HostSettingsCatalog.build(environment:)` via `navigator.selection`.
struct SettingsOverlayView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    let onDismiss: () -> Void

    @State private var navigator: SettingsNavigator

    private var catalog: SettingsCatalog { HostSettingsCatalog.build(environment: environment) }

    /// `focusedAppID` opens the overlay directly on that app's settings —
    /// e.g. summoning Settings while a Terminal is focused lands on Terminal.
    /// Otherwise it lands on General — the natural top of the reordered sidebar.
    init(focusedAppID: String? = nil, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        let initial = focusedAppID.map { SettingsPath(["app", $0]) } ?? SettingsPath(["workspace", "general"])
        _navigator = State(initialValue: SettingsNavigator(initial: initial))
    }

    var body: some View {
        let tokens = environment.themeManager.tokens

        GeometryReader { geo in
            ZStack {
                Color.black.opacity(OverlayChrome.backdropOpacity)
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }

                let size = SettingsGeometry.panelSize(in: geo.size)
                panel(tokens: tokens)
                    .frame(width: size.width, height: size.height)
                    .offset(y: SettingsMetrics.panelYOffset)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsPageGroup.allCases, id: \.self) { group in
                    let pages = catalog.pages(in: group)
                    if !pages.isEmpty {
                        groupLabel(group.title, tokens: tokens)
                            .padding(.top, group == .workspace ? 0 : 12)
                        ForEach(pages) { page in
                            sidebarRow(page: page, tokens: tokens)
                        }
                    }
                }
            }
            .padding(12)
        }
        .scrollContentBackground(.hidden)
        .frame(width: SettingsMetrics.sidebarWidth, alignment: .topLeading)
    }

    /// A group header in the HUD language: a short accent tick beside an
    /// uppercase, letter-spaced label — echoing `SettingsSectionHeader`.
    private func groupLabel(_ text: String, tokens: DesignTokens) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1)
                .fill(tokens.accentSecondary.opacity(0.85))
                .frame(width: 2, height: 9)
                .shadow(color: tokens.accentSecondary.opacity(0.7), radius: 3)
            Text(text)
                .font(AinkradFont.mono(9, weight: .medium))
                .kerning(2.5)
                .foregroundStyle(tokens.foreground.opacity(0.4))
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }

    /// A catalog-driven sidebar row for any page in any group.
    private func sidebarRow(page: SettingsPage, tokens: DesignTokens) -> some View {
        let isSelected = navigator.selection == page.path
        return Button {
            navigator.selection = page.path
            navigator.clearHighlight()
        } label: {
            HStack(spacing: 10) {
                appTile(appID: page.appID, systemIcon: page.icon, size: 22,
                        isSelected: isSelected, tokens: tokens)
                Text(page.title)
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(isSelected ? 0.95 : 0.7))
                Spacer(minLength: 0)
                // Read here rather than at catalog-build time so the count
                // stays live while the overlay is open (Skills proposals).
                if let badgeCount = page.badge?(), badgeCount > 0 {
                    AinkradBadge(text: "\(badgeCount)", tint: tokens.accentSecondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .background(ChamferShape(cut: AinkradRadius.md)
                .fill(isSelected ? tokens.accentPrimary.opacity(0.14) : .clear))
            .overlay(TargetingBrackets(length: 7)
                .stroke(isSelected ? tokens.accentSecondary.opacity(0.9) : .clear, lineWidth: 1.3)
                .padding(1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isSelected)
    }

    /// Shared tile renderer: the theme's neon artwork for a registered app, or
    /// a tinted SF Symbol fallback. Used by both sidebar rows and the app
    /// settings identity header.
    @ViewBuilder
    private func appTile(appID: String?, systemIcon: String, size: CGFloat, isSelected: Bool, tokens: DesignTokens) -> some View {
        if appID != nil {
            // A registered app: its live neon tile, following the active theme.
            NeonAppTile(symbol: systemIcon, tokens: tokens, size: size)
        } else {
            // A fixed settings section (General, Sound, …): a tinted SF Symbol.
            Image(systemName: systemIcon)
                .font(.system(size: size * 0.6))
                .foregroundStyle(isSelected ? tokens.accentSecondary : tokens.foreground.opacity(0.55))
                .frame(width: size, height: size)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private func detail(tokens: DesignTokens) -> some View {
        if let page = catalog.page(at: navigator.selection) {
            SettingsPageView(page: page, highlightedPath: navigator.highlightedPath)
        } else {
            AinkradEmptyState(icon: "gearshape", title: "Nothing here",
                              message: "That settings page is no longer available.")
        }
    }

}
