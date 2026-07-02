import SwiftUI

@main
struct AinkradApp: App {
    @State private var environment = AppEnvironment.bootstrap()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Launcher") {
                    environment.isLauncherPresented = true
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("New Workspace") {
                    environment.workspaceManager.createWorkspace()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                ForEach(1...9, id: \.self) { number in
                    Button("Switch to Workspace \(number)") {
                        environment.workspaceManager.switchToWorkspace(at: number - 1)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                }
            }
        }
    }
}
