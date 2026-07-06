import SwiftUI

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
        let environment = AppEnvironment.bootstrap()
        _environment = State(initialValue: environment)
        appDelegate.quitCoordinator = environment.quitCoordinator
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
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
