import SwiftUI

/// Terminal's root view for a Block: creates its `TerminalSession` on
/// first appearance and hosts it via `TerminalContainerView`. See
/// Terminal App Architecture.md.
struct TerminalBlockRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var session: TerminalSession?

    var body: some View {
        Group {
            if let session {
                TerminalContainerView(session: session)
            } else {
                Color.clear
            }
        }
        .onAppear {
            guard session == nil else { return }
            session = TerminalSessionFactory(settingsStore: environment.settingsStore).makeSession()
        }
    }
}
