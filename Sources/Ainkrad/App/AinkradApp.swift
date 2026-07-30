import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Resolves the Home at launch.
///
/// INTERIM: `.unset` auto-adopts `~/Ainkrad` so this branch is shippable before
/// the setup wizard exists. The wizard replaces that with a real folder picker;
/// delete `defaultVaultLocation` and that branch when it lands. `.missing` and
/// `.foreign` deliberately throw — the recovery UI ships with the wizard, and
/// falling back to a fresh vault is the exact failure this design forbids.
enum LaunchHomeResolver {
    enum Failure: Error, Equatable {
        case vaultMissing(path: String)
        case notAnAinkradHome(path: String)
        /// A `Resolution` case added by a newer AinkradAppKit than this host knows.
        /// `Resolution` is resilient (library evolution), so this is reachable.
        /// Throwing is the only safe answer: an unknown outcome must never be
        /// treated as "unset" and adopted over.
        case unrecognizedResolution
    }

    static func defaultVaultLocation() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Ainkrad", isDirectory: true)
    }

    static func resolveOrAdopt(
        defaultVault: URL = LaunchHomeResolver.defaultVaultLocation(),
        pointerDirectory: URL = AinkradHome.defaultPointerDirectory(),
        cacheRoot: URL = AinkradHome.defaultCacheRoot(
            bundleID: Bundle.main.bundleIdentifier ?? "com.ainkrad.app")
    ) throws -> Home {
        switch AinkradHome.resolve(pointerDirectory: pointerDirectory, cacheRoot: cacheRoot) {
        case .ready(let home):
            return home

        case .missing(let path):
            throw Failure.vaultMissing(path: path)

        case .foreign(let url):
            throw Failure.notAnAinkradHome(path: url.path)

        case .unset:
            // INTERIM — replaced by the wizard's folder picker.
            try FileManager.default.createDirectory(at: defaultVault,
                                                    withIntermediateDirectories: true)
            let home = Home(vaultRoot: defaultVault, cacheRoot: cacheRoot)

            // Migrate BEFORE adopting. `adopt` is what writes the pointer, and a
            // pointer is the app's claim that this vault is authoritative. If the
            // copy fails part-way, no pointer exists, so the next launch is a clean
            // first run over the same untouched legacy tree — the guarantee
            // VaultMigration is built around. Adopting first would leave a pointer
            // to a half-populated vault that never gets migrated again.
            if let container = VaultMigration.legacyContainerURL(),
               VaultMigration.needsMigration(container: container) {
                try VaultMigration.migrate(fromContainer: container, into: home)
            }

            // `adopt` writes the marker and pointer; it returns an equivalent Home.
            return try AinkradHome.adopt(defaultVault,
                                         pointerDirectory: pointerDirectory,
                                         cacheRoot: cacheRoot)

        @unknown default:
            throw Failure.unrecognizedResolution
        }
    }
}

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
        let home: Home
        do {
            home = try LaunchHomeResolver.resolveOrAdopt()
        } catch {
            // No recovery UI until the setup wizard ships. Failing loudly is
            // correct: silently adopting a different vault is unrecoverable.
            fatalError("Ainkrad Home unavailable: \(error)")
        }
        let environment = AppEnvironment.bootstrap(home: home)
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
