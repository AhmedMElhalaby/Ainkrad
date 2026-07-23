import SwiftUI
import AppKit
import AinkradAppKit
import AinkradHostRuntime

/// Settings → Keyboard: view + rebind the six named shortcuts, with conflict
/// detection and reset-to-defaults (AIN-144). The positional/structural
/// shortcuts (pane focus/resize, workspace cycle, number jumps) are listed
/// read-only under SYSTEM — they are not customizable this issue.
struct ShortcutsSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var recorder = ShortcutRecorder()

    var body: some View {
        let tokens = environment.themeManager.tokens
        let store = environment.shortcutStore

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSectionHeader(title: "KEYBOARD", tokens: tokens)

                Text("Click Record, then press a new key combination. Press Esc to cancel.")
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))

                if let conflictMessage = recorder.conflictMessage {
                    Text(conflictMessage)
                        .font(AinkradFont.display(11, weight: .medium))
                        .foregroundStyle(.red.opacity(0.85))
                }

                VStack(spacing: 8) {
                    ForEach(ShortcutAction.allCases, id: \.self) { action in
                        actionRow(action, store: store, tokens: tokens)
                    }
                }

                systemSection(tokens: tokens)

                Button {
                    recorder.stop()
                    store.resetToDefaults()
                } label: {
                    Text("Reset All to Defaults")
                        .font(AinkradFont.display(12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(tokens.accentSecondary)
                .padding(.top, 4)
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
        .onDisappear { recorder.stop() }
    }

    // MARK: - Rows

    private func actionRow(_ action: ShortcutAction, store: ShortcutStore, tokens: DesignTokens) -> some View {
        let isRecording = recorder.action == action
        let isCustom = store.bindings.overrides[action.rawValue] != nil

        return HStack(spacing: 10) {
            Text(action.displayName)
                .font(AinkradFont.display(13))
                .foregroundStyle(tokens.foreground.opacity(0.85))

            Spacer()

            Text(isRecording ? "Press keys…" : store.chord(for: action).displayString)
                .font(AinkradFont.mono(12))
                .foregroundStyle(isRecording ? tokens.accentSecondary : tokens.foreground.opacity(0.7))
                .frame(minWidth: 90, alignment: .trailing)

            Button {
                if isRecording {
                    recorder.stop()
                } else {
                    recorder.start(action, store: store)
                }
            } label: {
                Text(isRecording ? "Cancel" : "Record")
                    .font(AinkradFont.display(11, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(tokens.foreground.opacity(0.75))

            Button {
                recorder.stop()
                store.resetToDefault(action)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isCustom ? tokens.accentSecondary : tokens.foreground.opacity(0.25))
            .disabled(!isCustom)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(isRecording ? 0.5 : 0.3)))
        .overlay(
            ChamferShape(cut: AinkradRadius.sm)
                .strokeBorder(isRecording ? tokens.accentSecondary.opacity(0.7) : .clear, lineWidth: 1.2)
        )
    }

    // MARK: - Fixed/positional shortcuts (read-only)

    private static let systemShortcuts: [(String, String)] = [
        ("Pane Focus", "⌘←→↑↓"),
        ("Resize Pane", "⌘⇧←→↑↓"),
        ("Cycle Workspace", "⌘⌥←→"),
        ("Jump to Workspace", "⌘1–9"),
    ]

    private func systemSection(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionHeader(title: "SYSTEM (FIXED)", tokens: tokens)
            ForEach(Self.systemShortcuts, id: \.0) { name, chord in
                HStack {
                    Text(name)
                        .font(AinkradFont.display(12))
                        .foregroundStyle(tokens.foreground.opacity(0.6))
                    Spacer()
                    Text(chord)
                        .font(AinkradFont.mono(11))
                        .foregroundStyle(tokens.foreground.opacity(0.45))
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
            }
        }
        .padding(.top, 8)
    }
}

/// Captures the next key-down event as a `KeyChord` and applies it via
/// `ShortcutStore.rebind`, surfacing a conflict message if it collides with
/// another action. A reference type so the local `NSEvent` monitor's
/// completion closure mutates shared, observable state rather than a
/// snapshot of a value-type view.
@MainActor
@Observable
final class ShortcutRecorder {
    private(set) var action: ShortcutAction?
    private(set) var conflictMessage: String?
    private var monitor: Any?
    private var store: ShortcutStore?

    func start(_ action: ShortcutAction, store: ShortcutStore) {
        stop()
        conflictMessage = nil
        self.action = action
        self.store = store
        // Suppress the always-on KeyboardShortcutMonitor for the duration of
        // the recording so it can't act on the chord being captured (AIN-144).
        store.isRecordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {   // Esc cancels the recording without rebinding.
                self.stop()
                return nil
            }
            let chord = KeyChord(
                keyCode: event.keyCode,
                command: event.modifierFlags.contains(.command),
                shift: event.modifierFlags.contains(.shift),
                option: event.modifierFlags.contains(.option),
                control: event.modifierFlags.contains(.control)
            )
            if store.rebind(action, to: chord) {
                self.conflictMessage = nil
            } else {
                let owner = store.bindings.conflict(of: chord, excluding: action)
                self.conflictMessage = "\(chord.displayString) is already used by \(owner?.displayName ?? "another shortcut")."
            }
            self.stop()
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        action = nil
        // Always clear the suppression gate on the way out — captured,
        // cancelled (Esc), or the view disappearing all route through here —
        // so a stuck flag can never disable the always-on monitor (AIN-144).
        store?.isRecordingShortcut = false
        store = nil
    }
}
