import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

// Named `AinkradHostApp` (not `AinkradApp`) so the identifier doesn't collide
// with `AinkradAppKit.AinkradApp` — the SDK protocol plugin bundles conform
// to (`PluginLoader.swift`). A same-module type always shadows an imported
// one of the same name, so the SDK protocol would otherwise be unreachable.
@main
struct AinkradHostApp: App {
    // Otherwise-pure-SwiftUI app; this adaptor exists solely so ⌘Q / the app
    // menu's Quit / the Dock's Quit route through `AinkradAppDelegate` →
    // `QuitCoordinator` for the in-app confirmation, instead of terminating
    // immediately.
    @NSApplicationDelegateAdaptor(AinkradAppDelegate.self) private var appDelegate
    @State private var environment: AppEnvironment

    init() {
        FontRegistrar.registerBundledFonts()
        // INTERIM (Task 8 replaces this): `bootstrap` now requires a `Home`, so
        // launch has to name one here. This keeps the pre-refactor production
        // location — the Application Support container — as BOTH roots, so this
        // task changes no shipped on-disk behaviour beyond the subdirectory
        // renames. It is not a fallback: there is no other branch, and Task 8
        // swaps it for real pointer resolution (which terminates rather than
        // defaulting when the configured vault is missing or foreign).
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let container = support
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.ainkrad.app", isDirectory: true)
        let environment = AppEnvironment.bootstrap(home: Home(vaultRoot: container, cacheRoot: container))
        _environment = State(initialValue: environment)
        appDelegate.quitCoordinator = environment.quitCoordinator
        appDelegate.menuBarController = environment.menuBarController
        appDelegate.assistantSessionStore = environment.assistantSessionStore
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                // Bridges the host's theme/typography into the SDK's env
                // keys so `AinkradAppKit` components (Gallery, and any
                // plugin that opts in) render theme-correctly. Reading
                // `themeManager.currentTheme`/`uiFontFamily`/`uiFontScale`
                // here — all `@Observable` — keeps this live on theme change.
                .environment(\.ainkradTheme, HostThemeTokens(from: environment.themeManager.currentTheme))
                .environment(\.ainkradStatusColors, AinkradStatusColors(
                    success: environment.themeManager.tokens.success,
                    warning: environment.themeManager.tokens.warning,
                    danger: environment.themeManager.tokens.danger
                ))
                .environment(\.ainkradTypography, AinkradTypography(
                    fontFamilyName: environment.themeManager.uiFontFamily.fontName,
                    scale: environment.themeManager.uiFontScale.multiplier
                ))
                // AINKRAD-controlled motion, independent of the macOS Reduce
                // Motion accessibility toggle — see GlobalSettings.uiReduceMotion.
                // Default false = motion on.
                .environment(\.ainkradReduceMotion, environment.generalSettingsStore.uiReduceMotion)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // Menu items for discoverability/mouse use. The actual
            // keyboard delivery goes through KeyboardShortcutMonitor's
            // local event monitor, which is reliable regardless of how
            // the app was launched — see its doc comment.
            CommandGroup(after: .newItem) {
                Button("Open Launcher") {
                    environment.isLauncherPresented = true
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("New Workspace") {
                    environment.workspaceManager.createWorkspace()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Workspaces…") {
                    environment.isLauncherPresented = false
                    environment.isWorkspaceOverviewPresented.toggle()
                }
                .keyboardShortcut(.tab, modifiers: .option)
            }
        }
    }
}
