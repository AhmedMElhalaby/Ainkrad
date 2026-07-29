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
    @State private var pendingDeepLink: SettingsPath?

    @State private var query = ""
    @State private var hasNavigatedWithQuery = false
    @FocusState private var searchFocused: Bool

    private var catalog: SettingsCatalog { HostSettingsCatalog.build(environment: environment) }

    private var searchMode: SettingsSearchMode {
        SettingsSearchMode(query: query, hasNavigated: hasNavigatedWithQuery)
    }
    private var index: SettingsCatalogIndex { SettingsCatalogIndex(catalog: catalog) }

    /// The page actually on screen. Resolves through `pendingDeepLink` (a
    /// field or group path) via `catalog.page(containing:)` so a deep-link's
    /// containing page renders on the very first frame — `navigator.selection`
    /// only catches up once `.task` runs, which is too late to avoid a flash
    /// of the empty state if relied on directly.
    private var displayedPage: SettingsPage? {
        catalog.page(containing: pendingDeepLink ?? navigator.selection)
    }

    /// The field to highlight/scroll to. Mirrors `SettingsNavigator.navigate`'s
    /// own rule (nil when the resolved path IS the page, i.e. there's nothing
    /// more specific to point at) so the pending and post-`.task` states agree.
    private var displayedHighlight: SettingsPath? {
        if let pendingDeepLink {
            return (displayedPage?.path == pendingDeepLink) ? nil : pendingDeepLink
        }
        return navigator.highlightedPath
    }

    /// `focusedAppID` opens the overlay directly on that app's settings —
    /// e.g. summoning Settings while a Terminal is focused lands on Terminal.
    /// Otherwise it lands on General — the natural top of the reordered sidebar.
    init(focusedAppID: String? = nil, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        let initial = focusedAppID.map { SettingsPath(["app", $0]) } ?? SettingsPath(["workspace", "general"])
        _navigator = State(initialValue: SettingsNavigator(initial: initial))
    }

    /// Lands the overlay directly on a specific field — used by ⌘, from a
    /// focused app, error toasts, and the assistant. Old paths still resolve
    /// via `SettingsPathAliases` so links survive the IA restructure.
    init(deepLink: SettingsPath, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        let resolved = SettingsPathAliases.resolve(deepLink)
        _navigator = State(initialValue: SettingsNavigator(initial: resolved))
        _pendingDeepLink = State(initialValue: resolved)
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
        .onKeyPress(.init("f"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            searchFocused = true
            return .handled
        }
        .onKeyPress(.escape) {
            // Agree with `SettingsSearchMode`'s own notion of "empty" — a
            // whitespace-only query is `.browsing`, so it must dismiss on
            // the first press rather than silently eating the whitespace.
            if searchMode != .browsing { query = ""; return .handled }
            onDismiss(); return .handled
        }
        .task {
            if let path = pendingDeepLink {
                navigator.navigate(to: path, in: catalog)
                pendingDeepLink = nil
            }
        }
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
        VStack(alignment: .leading, spacing: 0) {
            SettingsSearchField(query: $query, isFocused: $searchFocused)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .onChange(of: query) { _, _ in hasNavigatedWithQuery = false }

            sidebarList(tokens: tokens)
        }
        .frame(width: SettingsMetrics.sidebarWidth, alignment: .topLeading)
    }

    private func sidebarList(tokens: DesignTokens) -> some View {
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
        let isSelected = displayedPage?.path == page.path
        return Button {
            navigator.selection = page.path
            navigator.clearHighlight()
            pendingDeepLink = nil
            // A sidebar tap is an unambiguous "take me to this page"
            // instruction — it must always show that page, in BOTH the
            // palette and filtering modes, not just leave the palette
            // sitting inertly on screen. Routed through the real
            // SettingsSearchMode.afterSidebarTap transition so production
            // and the sidebar-tap tests exercise the same code path.
            hasNavigatedWithQuery = searchMode.afterSidebarTap().query != nil
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
            .settingsRowHover(isActive: isSelected)
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
        switch searchMode {
        case .palette(let q):
            SettingsPaletteView(results: index.search(q, currentPage: navigator.selection), query: q) { path in
                navigator.navigate(to: path, in: catalog)
                hasNavigatedWithQuery = true
            }
        case .filtering(let q):
            if let page = displayedPage {
                VStack(alignment: .leading, spacing: 0) {
                    filterBanner(query: q, tokens: tokens)
                    SettingsPageView(page: page,
                                     matchedPaths: index.matchedPaths(q, on: page),
                                     highlightedPath: displayedHighlight)
                }
            } else {
                AinkradEmptyState(icon: "gearshape", title: "Nothing here",
                                  message: "That settings page is no longer available.")
            }
        case .browsing:
            if let page = displayedPage {
                SettingsPageView(page: page, highlightedPath: displayedHighlight)
            } else {
                AinkradEmptyState(icon: "gearshape", title: "Nothing here",
                                  message: "That settings page is no longer available.")
            }
        }
    }

    /// Makes the filter escapable — a filter you cannot see or exit is the
    /// disorienting part of System Settings' version, which we're
    /// deliberately not copying.
    private func filterBanner(query: String, tokens: DesignTokens) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 10))
                .foregroundStyle(tokens.accentSecondary.opacity(0.85))
            Text("Filtering by \u{201C}\(query)\u{201D} — non-matching settings are dimmed")
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.foreground.opacity(0.6))
            Spacer(minLength: 8)
            Button("Clear") { self.query = "" }
                .buttonStyle(.plain)
                .font(AinkradFont.display(11, weight: .medium))
                .foregroundStyle(tokens.accentSecondary)
        }
        .padding(.horizontal, 18)
        .frame(height: 34)
    }

}
