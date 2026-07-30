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
        let home: Home
        // First run: no pointer, so nothing to resolve. The app does NOT ask for a
        // folder here any more — it boots against a provisional Home so the whole
        // environment loads, and raises the setup gate over it. The wizard's Choose
        // Home step adopts the user's real vault and swaps the environment
        // in-session. Nothing is adopted, no pointer is written, and nothing the
        // user authors may be written while this flag is up.
        var provisional = false
        do {
            if case .unset = AinkradHome.resolve() {
                home = LaunchHomeResolver.provisionalHome()
                provisional = true
            } else if LaunchHomeResolver.isRunningTests {
                // The test bundle is hosted by this app, so this initialiser also
                // runs under `xcodebuild test`. Resolving for real there would
                // present a modal folder chooser and hang the suite forever on any
                // machine without a configured Home — and would write a pointer and
                // migrate the developer's real container as a side effect of
                // running tests. A provisional Home keeps the host inert;
                // `LaunchHomeResolver` is tested directly, not through this
                // initialiser.
                home = LaunchHomeResolver.provisionalHome()
            } else {
                // `.missing`/`.foreign` keep their native-alert recovery: those are
                // not first run, and the user already has a Home to be reunited
                // with rather than a wizard to walk through.
                home = try LaunchHomeResolver.resolveWithRecovery()
            }
        } catch {
            // Either the user closed the folder chooser, or they chose Quit from a
            // recovery alert. Both are decisions, not crashes, so `exit(0)` and not
            // `fatalError`. Exiting changes nothing on disk — no pointer was
            // written — so the next launch simply asks again. Nothing else can
            // reach here: `resolveWithRecovery` turns every other failure into an
            // alert the user can act on.
            //
            // `exit(0)` from `init` is correct at this point specifically: `NSApp`
            // exists but is not running, so there is no run loop to unwind and
            // `NSApp.terminate` would do nothing.
            exit(0)
        }
        let environment = AppEnvironment.bootstrap(home: home)
        environment.isProvisionalHome = provisional
        environment.isSetupPresented = provisional
        _environment = State(initialValue: environment)
        Self.install(environment, into: appDelegate)
    }

    /// Points every holder that outlives a view body at `environment`.
    ///
    /// This is the ONLY place the app delegate's store references are written,
    /// so the initial boot and the setup wizard's mid-session re-root
    /// (`HomeAdoption.adoptAndRebuild`, whose `install:` closure calls this)
    /// cannot diverge. A holder assigned anywhere else would keep writing to
    /// the home the app booted against — which during setup is a temporary
    /// directory the OS deletes.
    ///
    /// Everything else that outlives a view body lives INSIDE `AppEnvironment`
    /// (`skillWatcher`, `customCommandWatcher`, `fileChangeWatcher`,
    /// `scheduleRunner`, `remoteChannelService`, `mcpServerRegistry`,
    /// `lspServerRegistry`, `menuBarController`) and is rebuilt wholesale by
    /// `bootstrap`. `KeyboardShortcutMonitor.MonitoringView` re-reads its
    /// `environment` through `updateNSView` when the `@State` swaps.
    ///
    /// **Conditions under which a mid-session swap is safe.** The OUTGOING
    /// environment's long-lived members are not stopped here — `AppEnvironment`
    /// has no `shutdown()`. The swap is therefore only safe while the outgoing
    /// home is a provisional scratch home that satisfies all of:
    ///
    /// 1. No enabled `.fileChange`/`.gitChange` schedules — otherwise the
    ///    outgoing `FileChangeWatcher`'s FSEvents streams (which strongly
    ///    capture `triggerDispatcher` → `runManager` → the OLD `persistence`)
    ///    outlive the swap and keep firing against the scratch home.
    /// 2. No enabled remote channel — otherwise the outgoing `WebhookServer`
    ///    keeps its 127.0.0.1 port bound, routing into the old run graph.
    /// 3. No in-flight agent turn or queued run.
    /// 4. **No secret written while the home is provisional.**
    ///    `Home.keychainServiceName` resolves a vault under the temporary
    ///    directory to a hashed throwaway namespace and a real vault to the
    ///    canonical one (see `Home+KeychainService.swift`). An API key entered
    ///    before adoption therefore lands in a namespace the rebuilt
    ///    environment never reads — the user would see it accepted and then
    ///    find it gone, with no error at all. Any wizard step that collects a
    ///    credential MUST come after Choose Home; `Home.isProvisional` is the
    ///    predicate to assert against.
    ///
    /// `ScheduleRunner` is instantiated and `start()`ed unconditionally
    /// (`AppEnvironment+BootstrapSession.swift`), so unlike 1 and 2 it always
    /// exists across a swap. It is nonetheless inert: its `Timer` block is
    /// `[weak self]` and a scratch home has no schedules, so `tick` is a no-op.
    private static func install(_ environment: AppEnvironment, into appDelegate: AinkradAppDelegate) {
        // Retire the outgoing status item first: `NSStatusBar` would otherwise
        // keep showing it, still bound to the previous environment's presence.
        // No-op on the initial boot, where there is no previous controller.
        //
        // Re-installing the incoming one happens HERE rather than being left to
        // the caller. On the initial boot `applicationDidFinishLaunching` does
        // the install, but by swap time that has long since fired — a caller
        // who merely assigned would be left with a torn-down status item and no
        // menu bar, and nothing in the code would say so. Gated on there having
        // BEEN an outgoing controller, so the boot path is untouched and the
        // delegate still owns the first install. (`MenuBarController.install()`
        // is guarded idempotent anyway: `guard statusItem == nil`.)
        if appDelegate.menuBarController !== environment.menuBarController,
           let outgoing = appDelegate.menuBarController {
            outgoing.teardown()
            environment.menuBarController?.install()
        }
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
            // Every item here is disabled while the first-run gate is up. They
            // are mouse-reachable even though the keyboard monitor swallows their
            // chords, and they are NOT all harmless: "New Workspace" mutates and
            // PERSISTS into the provisional Home, a write Task 4's swap then
            // silently discards — precisely the loss this design exists to
            // prevent. "Workspaces…" would latch its overlay invisibly beneath
            // the gate and pop it open the moment setup finishes.
            CommandGroup(after: .newItem) {
                let isGated = environment.isSetupPresented

                Button("Open Launcher") {
                    environment.isLauncherPresented = true
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(isGated)

                Button("New Workspace") {
                    environment.workspaceManager.createWorkspace()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(isGated)

                Button("Workspaces…") {
                    environment.isLauncherPresented = false
                    environment.isWorkspaceOverviewPresented.toggle()
                }
                .keyboardShortcut(.tab, modifiers: .option)
                .disabled(isGated)
            }
        }
    }
}
