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
        private var mouseUpMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // One-part screen: no title-bar material or separator may
            // tint the top region — the sky runs edge to edge. The window
            // deliberately does NOT move by background drag — it would
            // steal in-app drags (e.g. Workspace Overview card reorder);
            // the top strip still drags the window.
            if let window {
                window.titlebarAppearsTransparent = true
                window.titlebarSeparatorStyle = .none
                window.isMovableByWindowBackground = false
            }
            if window != nil {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, let environment = self.environment, self.handle(event, in: environment) else {
                        return event
                    }
                    return nil
                }
                // Pane drags set a transient "dragging" flag; if the drag
                // ends outside any drop target, no delegate fires — clear
                // it on mouse-up so the lifted pane settles back.
                mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                    if let environment = self?.environment {
                        let layout = environment.workspaceManager.activeWorkspace.tileLayout
                        if layout.draggingBlockID != nil {
                            DispatchQueue.main.async {
                                layout.draggingBlockID = nil
                            }
                        }
                    }
                    return event
                }
            } else {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                }
                if let mouseUpMonitor {
                    NSEvent.removeMonitor(mouseUpMonitor)
                    self.mouseUpMonitor = nil
                }
            }
        }

        private func handle(_ event: NSEvent, in environment: AppEnvironment) -> Bool {
            // ⌥Tab toggles the Workspace Overview (keyCode 48 = Tab).
            if event.keyCode == 48,
               event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.command) {
                environment.isLauncherPresented = false
                environment.isWorkspaceOverviewPresented.toggle()
                return true
            }

            guard event.modifierFlags.contains(.command),
                  let characters = event.charactersIgnoringModifiers else { return false }
            let isShifted = event.modifierFlags.contains(.shift)

            switch characters {
            case "k" where !isShifted:
                environment.isWorkspaceOverviewPresented = false
                if environment.isLauncherPresented {
                    environment.launcherStore.query = ""
                    environment.isLauncherPresented = false
                } else {
                    environment.isLauncherPresented = true
                }
                return true
            case "n" where isShifted:
                environment.workspaceManager.createWorkspace()
                // A hidden workspace's terminal must not keep receiving
                // keystrokes after the switch.
                window?.makeFirstResponder(nil)
                return true
            case "w" where !isShifted:
                let layout = environment.workspaceManager.activeWorkspace.tileLayout
                if let focusedBlockID = layout.focusedBlockID {
                    layout.close(focusedBlockID)
                }
                return true
            case "f", "F":
                guard isShifted else { return false }
                let layout = environment.workspaceManager.activeWorkspace.tileLayout
                if let focusedBlockID = layout.focusedBlockID {
                    layout.toggleMagnify(focusedBlockID)
                }
                return true
            case "d", "D":
                // Split the focused pane: ⌘D right, ⌘⇧D down.
                let layout = environment.workspaceManager.activeWorkspace.tileLayout
                layout.splitFocused(isShifted ? .bottom : .trailing)
                return true
            default:
                if !isShifted, let number = Int(characters), (1...9).contains(number) {
                    environment.workspaceManager.switchToWorkspace(at: number - 1)
                    window?.makeFirstResponder(nil)
                    return true
                }
                return false
            }
        }
    }
}
