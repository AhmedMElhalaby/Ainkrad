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
                environment.isSettingsPresented = false
                environment.isMarketplacePresented = false
                environment.isWorkspaceOverviewPresented.toggle()
                return true
            }

            guard event.modifierFlags.contains(.command) else { return false }
            let isShifted = event.modifierFlags.contains(.shift)
            let isOption = event.modifierFlags.contains(.option)

            // ⌘⌥←/→ cycle to the previous/next workspace (wrapping around),
            // the quick companion to the ⌘1-9 direct jumps.
            if isOption,
               !environment.isLauncherPresented,
               !environment.isWorkspaceOverviewPresented,
               !environment.isSettingsPresented,
               !environment.isMarketplacePresented {
                switch event.keyCode {
                case 123:
                    environment.workspaceManager.switchToPreviousWorkspace()
                    window?.makeFirstResponder(nil)
                    return true
                case 124:
                    environment.workspaceManager.switchToNextWorkspace()
                    window?.makeFirstResponder(nil)
                    return true
                default:
                    break
                }
            }

            // ⌘arrows move pane focus; ⌘⇧arrows resize the focused pane —
            // only while no overlay owns the keyboard (and never when ⌥ is
            // held, which is the workspace-cycle chord above).
            if !isOption, !environment.isLauncherPresented, !environment.isWorkspaceOverviewPresented, !environment.isSettingsPresented, !environment.isMarketplacePresented {
                let direction: PaneDirection? = switch event.keyCode {
                case 123: .left
                case 124: .right
                case 125: .down
                case 126: .up
                default: nil
                }
                if let direction {
                    let layout = environment.workspaceManager.activeWorkspace.tileLayout
                    if isShifted {
                        layout.resizeFocused(direction)
                    } else {
                        layout.focusNeighbor(direction)
                        window?.makeFirstResponder(nil)
                    }
                    return true
                }
            }

            // `charactersIgnoringModifiers` still applies Shift, so a shifted
            // letter arrives uppercase (⌘⇧A → "A"). Lowercase it so the
            // shifted cases below (matched on `isShifted` + a lowercase letter)
            // fire regardless of case.
            guard let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }

            switch characters {
            case "k" where !isShifted:
                environment.isWorkspaceOverviewPresented = false
                environment.isSettingsPresented = false
                environment.isMarketplacePresented = false
                if environment.isLauncherPresented {
                    environment.launcherStore.query = ""
                    environment.isLauncherPresented = false
                } else {
                    environment.isLauncherPresented = true
                }
                return true
            case "," where !isShifted:
                // ⌘, summons/dismisses the Settings overlay (macOS convention).
                environment.isLauncherPresented = false
                environment.isWorkspaceOverviewPresented = false
                environment.isMarketplacePresented = false
                environment.isSettingsPresented.toggle()
                window?.makeFirstResponder(nil)
                return true
            case "a" where isShifted:
                // ⌘⇧A summons/dismisses the Marketplace overlay.
                environment.isLauncherPresented = false
                environment.isWorkspaceOverviewPresented = false
                environment.isSettingsPresented = false
                environment.isMarketplacePresented.toggle()
                window?.makeFirstResponder(nil)
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
            case "m" where !isShifted:
                // Toggle Focus Mode / Split Mode for the active workspace.
                let workspace = environment.workspaceManager.activeWorkspace
                workspace.viewMode = workspace.viewMode == .focus ? WorkspaceViewMode.split : WorkspaceViewMode.focus
                environment.workspaceManager.persist()
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
