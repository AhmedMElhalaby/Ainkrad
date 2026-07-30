import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Resolves the Home at launch.
///
/// There is **no default Home location**. On first run the user picks the folder;
/// nothing is ever chosen on their behalf, because a location chosen for them is
/// how the app ends up planted in the middle of a directory that already belongs
/// to something else. `.missing` and `.foreign` throw — the recovery UI ships
/// with the setup wizard, and falling back to a fresh vault is the exact failure
/// this design forbids.
///
/// This is the setup wizard's folder-choice step arriving early; the wizard plan
/// builds on it rather than replacing it.
enum LaunchHomeResolver {
    enum Failure: Error, Equatable {
        case vaultMissing(path: String)
        case notAnAinkradHome(path: String)
        /// The user dismissed the folder chooser without picking. Not an error in
        /// the crash sense — the app simply has no Home and must not invent one.
        case setupCancelled
        /// A `Resolution` case added by a newer AinkradAppKit than this host knows.
        /// `Resolution` is resilient (library evolution), so this is reachable.
        /// Throwing is the only safe answer: an unknown outcome must never be
        /// treated as "unset" and adopted over.
        case unrecognizedResolution
    }

    /// Asks the user for a folder. Returns `nil` if they cancelled.
    ///
    /// Injected so the resolver is testable without a modal panel; production
    /// passes `presentFolderChooser`.
    typealias VaultChooser = () -> URL?

    static func resolveOrAdopt(
        chooseVault: VaultChooser = LaunchHomeResolver.presentFolderChooser,
        pointerDirectory: URL = AinkradHome.defaultPointerDirectory(),
        cacheRoot: URL = AinkradHome.defaultCacheRoot(
            bundleID: Bundle.main.bundleIdentifier ?? "com.ainkrad.app"),
        // Injected so a test never touches — let alone marks as migrated — the real
        // machine's legacy container. `nil` means "nothing to migrate".
        legacyContainer: URL? = VaultMigration.legacyContainerURL()
    ) throws -> Home {
        switch AinkradHome.resolve(pointerDirectory: pointerDirectory, cacheRoot: cacheRoot) {
        case .ready(let home):
            return home

        case .missing(let path):
            throw Failure.vaultMissing(path: path)

        case .foreign(let url):
            throw Failure.notAnAinkradHome(path: url.path)

        case .unset:
            guard let chosen = chooseVault() else { throw Failure.setupCancelled }
            let home = Home(vaultRoot: chosen, cacheRoot: cacheRoot)

            // Validate BEFORE migrating. `adopt` refuses a populated directory, and
            // discovering that only after copying gigabytes into it would leave the
            // user's chosen folder littered by a run that then failed.
            try AinkradHome.validate(chosen)

            // Write the marker before migrating, for two reasons. First, migration
            // populates the folder, so the `adopt` below would otherwise be refused
            // by its own emptiness rule. Second — and this is the one that matters —
            // if migration fails part-way, the folder is left non-empty; without a
            // marker the user could never choose it again, because every retry would
            // be refused as `.notEmpty`. The marker is identity only; the POINTER is
            // still what claims a vault as authoritative, and it is still written
            // last. `read ?? new` keeps reinstall-and-restore's homeID intact.
            try (HomeMarker.read(in: chosen) ?? HomeMarker()).write(to: chosen)

            // Migrate BEFORE adopting. `adopt` is what writes the pointer, and a
            // pointer is the app's claim that this vault is authoritative. If the
            // copy fails part-way, no pointer exists, so the next launch is a clean
            // first run over the same untouched legacy tree — the guarantee
            // VaultMigration is built around. Adopting first would leave a pointer
            // to a half-populated vault that never gets migrated again.
            if let container = legacyContainer,
               VaultMigration.needsMigration(container: container) {
                try VaultMigration.migrate(fromContainer: container, into: home)
            }

            // `adopt` writes the marker and pointer; it returns an equivalent Home.
            return try AinkradHome.adopt(chosen,
                                         pointerDirectory: pointerDirectory,
                                         cacheRoot: cacheRoot)

        @unknown default:
            throw Failure.unrecognizedResolution
        }
    }

    /// True when this process is hosting a test bundle rather than a real launch.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// A disposable Home under the temporary directory, for the test host only.
    /// Never adopted, so no pointer is written and no real vault is claimed.
    static func scratchHomeForTestHost() -> Home {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ainkrad-test-host-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return Home(vaultRoot: base.appendingPathComponent("vault", isDirectory: true),
                    cacheRoot: base.appendingPathComponent("cache", isDirectory: true))
    }

    /// The first-run folder chooser.
    ///
    /// Runs during `App.init`, before any window exists. `NSApplication.shared` is
    /// already instantiated by then (SwiftUI creates it before running the `App`
    /// initialiser), and `NSOpenPanel.runModal` spins up its own modal session with
    /// its own window, so it does not need a host window. It DOES need the process
    /// to be frontmost, or the panel opens behind whatever the user was looking at
    /// with no Dock click able to raise it — hence the explicit activation.
    static func presentFolderChooser() -> URL? {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder for your Ainkrad Home. "
            + "Pick an empty folder, or create a new one — Ainkrad will not take over "
            + "a folder that already has files in it."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        return panel.runModal() == .OK ? panel.url : nil
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
            // The test bundle is hosted by this app, so this initialiser also runs
            // under `xcodebuild test`. Resolving for real there would present a
            // modal folder chooser and hang the suite forever on any machine
            // without a configured Home — and would write a pointer and migrate the
            // developer's real container as a side effect of running tests. A
            // scratch Home keeps the host inert; `LaunchHomeResolver` is tested
            // directly rather than through this initialiser.
            home = LaunchHomeResolver.isRunningTests
                ? LaunchHomeResolver.scratchHomeForTestHost()
                : try LaunchHomeResolver.resolveOrAdopt()
        } catch LaunchHomeResolver.Failure.setupCancelled {
            // The user closed the folder chooser. Quit cleanly rather than
            // re-presenting: at this point there is no window and no menu bar, so
            // a re-present loop would be a modal the user cannot escape except by
            // force-quitting. Exiting changes nothing on disk — no pointer was
            // written — so the next launch simply asks again. `exit(0)` and not
            // `fatalError`, because cancelling setup is a decision, not a crash.
            exit(0)
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
