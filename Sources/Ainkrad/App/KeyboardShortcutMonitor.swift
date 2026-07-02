import AppKit
import SwiftUI

/// Installs a local `keyDown` monitor for the app-wide shortcuts (⌘K,
/// ⌘1-⌘9, ⌘⇧N, ⌘W) — see ADR-0008 App Launcher & Workspace Switching.
/// A local monitor fires before the event reaches the menu bar's key
/// equivalents, so it is the reliable delivery path regardless of how the
/// running app was launched; a local monitor (not global/CGEventTap) is
/// sufficient since these shortcuts only need to work while Ainkrad is
/// frontmost, and needs no Accessibility/Input Monitoring permission.
struct KeyboardShortcutMonitor: NSViewRepresentable {
    let environment: AppEnvironment

    func makeNSView(context: Context) -> MonitoringView {
        let view = MonitoringView()
        view.environment = environment
        return view
    }

    func updateNSView(_ nsView: MonitoringView, context: Context) {
        nsView.environment = environment
    }

    final class MonitoringView: NSView {
        var environment: AppEnvironment?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // One-part screen: no title-bar material or separator may
            // tint the top region — the sky runs edge to edge.
            if let window {
                window.titlebarAppearsTransparent = true
                window.titlebarSeparatorStyle = .none
                window.isMovableByWindowBackground = true
            }
            if window != nil {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, let environment = self.environment, self.handle(event, in: environment) else {
                        return event
                    }
                    return nil
                }
            } else if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent, in environment: AppEnvironment) -> Bool {
            guard event.modifierFlags.contains(.command),
                  let characters = event.charactersIgnoringModifiers else { return false }
            let isShifted = event.modifierFlags.contains(.shift)

            switch characters {
            case "k" where !isShifted:
                if environment.isLauncherPresented {
                    environment.launcherStore.query = ""
                    environment.isLauncherPresented = false
                } else {
                    environment.isLauncherPresented = true
                }
                return true
            case "n" where isShifted:
                environment.workspaceManager.createWorkspace()
                return true
            case "w" where !isShifted:
                let layout = environment.workspaceManager.activeWorkspace.tileLayout
                if let focusedBlockID = layout.focusedBlockID {
                    layout.close(focusedBlockID)
                }
                return true
            default:
                if !isShifted, let number = Int(characters), (1...9).contains(number) {
                    environment.workspaceManager.switchToWorkspace(at: number - 1)
                    return true
                }
                return false
            }
        }
    }
}
