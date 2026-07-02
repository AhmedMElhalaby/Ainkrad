import SwiftUI
import SwiftTerm

/// Hosts SwiftTerm's `LocalProcessTerminalView` (an AppKit `NSView`) inside
/// SwiftUI. Spawns the session's PTY-backed login shell on creation and
/// terminates it deterministically when this view leaves the hierarchy —
/// see ADR-0002 Terminal Emulation Approach and Terminal App
/// Architecture.md. Resize forwarding to the PTY is handled internally by
/// SwiftTerm whenever this view's frame changes.
struct TerminalContainerView: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        view.startProcess(
            executable: session.shellPath,
            args: ["-l"],
            environment: nil,
            currentDirectory: session.workingDirectory.path
        )
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: Coordinator) {
        nsView.terminate()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        private let session: TerminalSession

        init(session: TerminalSession) {
            self.session = session
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            Task { @MainActor [session] in
                session.terminate()
            }
        }
    }
}
