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
/// Two selection domains coexist while Tasks 8–9 finish folding the rest of
/// the sidebar into the catalog: catalog pages (WORKSPACE today) are owned by
/// `navigator.selection`, and the still-hardcoded rows (Memory, MCP, LSP,
/// Skills, every app) are owned by `legacySelection`. Exactly one of the two
/// is "live" at a time: selecting a legacy row *sets* `legacySelection`,
/// which takes priority over the catalog selection for both the sidebar
/// highlight and the detail pane; selecting a catalog row clears
/// `legacySelection` back to nil so the catalog selection takes over. This
/// keeps highlighting unambiguous without needing a third "which domain is
/// active" flag.
struct SettingsOverlayView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    let onDismiss: () -> Void

    @State private var navigator = SettingsNavigator(initial: SettingsPath(["workspace", "general"]))
    @State private var legacySelection: SettingsSection?

    private var catalog: SettingsCatalog { HostSettingsCatalog.build(environment: environment) }

    /// `focusedAppID` opens the overlay directly on that app's settings —
    /// e.g. summoning Settings while a Terminal is focused lands on Terminal.
    /// Otherwise it lands on General — the natural top of the reordered sidebar.
    init(focusedAppID: String? = nil, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        _legacySelection = State(initialValue: focusedAppID.map { .app($0) })
    }

    /// A value snapshot of a registered app for the sidebar — iterating
    /// `BuiltInApp.Type` metatypes in a SwiftUI container crashes the Xcode 27
    /// beta SILGen, so rows carry plain values and the metatype is looked back
    /// up by id when its settings view is needed.
    private struct AppEntry: Identifiable {
        let id: String
        let displayName: String
        let icon: String
        let isBuiltIn: Bool
    }

    /// The sections not yet folded into the catalog. General, Sound, Appearance,
    /// Living Sky, App Icon, and Keyboard moved into the WORKSPACE catalog
    /// pages in this task; Memory/MCP/LSP/Skills/apps fold in in Tasks 8–9.
    private enum SettingsSection: Hashable {
        case memory
        case mcp
        case lsp
        case skills
        case app(String)
    }

    /// Only enabled apps get a settings section — a disabled app is hidden here
    /// just as it is in the Launcher (`LauncherStore` filters `enabledApps`).
    private var appEntries: [AppEntry] {
        environment.registry.enabledApps.map {
            AppEntry(id: $0.id, displayName: $0.displayName, icon: $0.icon, isBuiltIn: $0.source == .builtIn)
        }
    }

    /// Apps compiled into the host (Terminal, Git Mage, …).
    private var builtInAppEntries: [AppEntry] { appEntries.filter(\.isBuiltIn) }

    /// Apps installed from the App Store as dynamic plugin bundles.
    private var installedAppEntries: [AppEntry] { appEntries.filter { !$0.isBuiltIn } }

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

                groupLabel("AINKRAD", tokens: tokens)
                    .padding(.top, 12)
                sidebarRow(.memory, title: "Memory", systemIcon: "brain", tokens: tokens)
                sidebarRow(.mcp, title: "MCP Servers", systemIcon: "point.3.connected.trianglepath.dotted", tokens: tokens)
                sidebarRow(.lsp, title: "Language Servers", systemIcon: "chevron.left.forwardslash.chevron.right", tokens: tokens)
                sidebarRow(.skills, title: "Skills", systemIcon: "sparkles",
                           badgeCount: environment.skillRegistry.proposals().count, tokens: tokens)

                if !builtInAppEntries.isEmpty {
                    groupLabel("BUILT-IN APPS", tokens: tokens)
                        .padding(.top, 12)
                    ForEach(builtInAppEntries) { app in
                        sidebarRow(.app(app.id), title: app.displayName, appID: app.id, systemIcon: app.icon, tokens: tokens)
                    }
                }

                if !installedAppEntries.isEmpty {
                    groupLabel("INSTALLED", tokens: tokens)
                        .padding(.top, 12)
                    ForEach(installedAppEntries) { app in
                        sidebarRow(.app(app.id), title: app.displayName, appID: app.id, systemIcon: app.icon, tokens: tokens)
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

    /// A catalog-driven WORKSPACE (and, in later tasks, other group) row.
    /// Selecting it hands live selection back to the navigator by clearing
    /// `legacySelection`.
    private func sidebarRow(page: SettingsPage, tokens: DesignTokens) -> some View {
        let isSelected = legacySelection == nil && navigator.selection == page.path
        return Button {
            legacySelection = nil
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

    private func sidebarRow(
        _ section: SettingsSection,
        title: String,
        appID: String? = nil,
        systemIcon: String,
        badgeCount: Int = 0,
        tokens: DesignTokens
    ) -> some View {
        let isSelected = legacySelection == section

        return Button {
            legacySelection = section
        } label: {
            HStack(spacing: 10) {
                rowIcon(appID: appID, systemIcon: systemIcon, isSelected: isSelected, tokens: tokens)
                Text(title)
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(isSelected ? 0.95 : 0.7))
                Spacer(minLength: 0)
                if badgeCount > 0 {
                    AinkradBadge(text: "\(badgeCount)", tint: tokens.accentSecondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .background(
                ChamferShape(cut: AinkradRadius.md)
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isSelected)
    }

    /// App rows use the neon tile artwork (Launcher-matching); fixed sections
    /// use a tinted SF Symbol.
    @ViewBuilder
    private func rowIcon(appID: String?, systemIcon: String, isSelected: Bool, tokens: DesignTokens) -> some View {
        appTile(appID: appID, systemIcon: systemIcon, size: 22, isSelected: isSelected, tokens: tokens)
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
        if let legacySelection {
            legacyDetail(legacySelection, tokens: tokens)
        } else if let page = catalog.page(at: navigator.selection) {
            SettingsPageView(page: page, highlightedPath: navigator.highlightedPath)
        } else {
            AinkradEmptyState(icon: "gearshape", title: "Nothing here",
                              message: "That settings page is no longer available.")
        }
    }

    @ViewBuilder
    private func legacyDetail(_ selection: SettingsSection, tokens: DesignTokens) -> some View {
        switch selection {
        case .memory:
            if let memoryService = environment.memoryService {
                MemoryUIView(service: memoryService)
            } else {
                AinkradEmptyState(
                    icon: "brain",
                    title: "Memory unavailable",
                    message: "The assistant's memory index couldn't be opened this launch, so it's running memory-less for now. Restart Ainkrad to try again."
                )
            }
        case .mcp:
            MCPManagerView(configStore: environment.mcpServerRegistry.configStore, registry: environment.mcpServerRegistry)
        case .lsp:
            LSPConfigView(registry: environment.lspServerRegistry)
        case .skills:
            SkillsManagerView(
                registry: environment.skillRegistry,
                commands: environment.skillCommandStore,
                resyncCommands: { environment.resyncSkillCommands() }
            )
        case .app(let id):
            // Look up among enabled apps only: a disabled app has no settings
            // section, and if the selected app is disabled while the overlay is
            // open its detail falls back to blank rather than lingering.
            if let app = environment.registry.enabledApps.first(where: { $0.id == id }),
               let entry = appEntries.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 0) {
                    appSettingsHeader(entry, tokens: tokens)
                    app.makeSettingsView()
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    appAppearanceSection(appID: id, tokens: tokens)
                        .padding(18)
                    Spacer(minLength: 0)
                }
            } else {
                Color.clear
            }
        }
    }

    /// The host-provided appearance controls appended below every OTHER app's
    /// own settings: a blur toggle (the host renders the blurred backdrop behind
    /// a translucent pane). The Assistant owns its own appearance (opacity, blur,
    /// and font) in its in-app Appearance tab, so the host block is suppressed
    /// for it; plugins own their transparency, so they get only blur here.
    @ViewBuilder
    private func appAppearanceSection(appID: String, tokens: DesignTokens) -> some View {
        let appearance = environment.appAppearanceStore

        if appID == AssistantApp.id {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader(title: "APPEARANCE", tokens: tokens)

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Blur")
                            .font(AinkradFont.display(13, weight: .medium))
                            .foregroundStyle(tokens.foreground.opacity(0.9))
                        Text("Blur the workspace revealed behind this app when it's translucent.")
                            .font(AinkradFont.display(11))
                            .foregroundStyle(tokens.foreground.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    AinkradToggle(
                        isOn: Binding(
                            get: { appearance.blurEnabled(appID) },
                            set: { appearance.setBlurEnabled(appID, $0) }
                        )
                    )
                }
                .padding(14)
                .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.45)))
            }
        }
    }

    /// A uniform identity header above every app's own settings — its neon
    /// tile, name, and a Built-in / Installed badge — so first-party and
    /// store-installed apps frame consistently regardless of what each app's
    /// `makeSettingsView` renders below.
    private func appSettingsHeader(_ entry: AppEntry, tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                appTile(appID: entry.id, systemIcon: entry.icon, size: 34, isSelected: true, tokens: tokens)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.displayName)
                        .font(AinkradFont.display(15, weight: .semibold))
                        .foregroundStyle(tokens.foreground.opacity(0.95))
                    sourceBadge(isBuiltIn: entry.isBuiltIn, tokens: tokens)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)

            LinearGradient(
                colors: [.clear, tokens.accentPrimary.opacity(0.28), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
        }
    }

    private func sourceBadge(isBuiltIn: Bool, tokens: DesignTokens) -> some View {
        Text(isBuiltIn ? "BUILT-IN" : "INSTALLED")
            .font(AinkradFont.mono(8, weight: .medium))
            .kerning(1.5)
            .foregroundStyle(isBuiltIn ? tokens.accentSecondary.opacity(0.9) : tokens.accentPrimary.opacity(0.95))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill((isBuiltIn ? tokens.accentSecondary : tokens.accentPrimary).opacity(0.12))
            )
            .overlay(
                Capsule().strokeBorder((isBuiltIn ? tokens.accentSecondary : tokens.accentPrimary).opacity(0.35), lineWidth: 1)
            )
    }
}
