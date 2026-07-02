import SwiftUI

@main
struct AinkradApp: App {
    @State private var environment: AppEnvironment

    init() {
        FontRegistrar.registerBundledFonts()
        _environment = State(initialValue: AppEnvironment.bootstrap())
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

                Button("New Tab") {
                    let workspace = environment.workspaceManager.activeWorkspace
                    if workspace.isMain {
                        environment.workspaceManager.createWorkspace()
                    } else {
                        workspace.addTab()
                    }
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Workspaces…") {
                    environment.isLauncherPresented = false
                    environment.isWorkspaceOverviewPresented.toggle()
                }
                .keyboardShortcut(.tab, modifiers: .option)
            }
        }
    }
}
