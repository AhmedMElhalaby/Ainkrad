import AppKit
import SwiftUI
import AinkradAppKit

/// The Assistant composer: one seamless neon surface (soft elevated fill) with a
/// bottom control strip holding the connection·model pill, the compact
/// permission-mode select, and send. Owns the draft binding shared with
/// `AssistantRootView`. The text field is `AinkradTextArea`, which carries its
/// own chamfer focus ring.
struct AssistantComposerBar: View {
    @Environment(AppEnvironment.self) private var environment
    let session: AgentSession
    let tokens: DesignTokens
    let modelPicker: AssistantModelPickerModel
    @Binding var draft: String
    var autoFocusOnAppear: Bool = false

    var body: some View {
        let isBusy = AssistantComposerBar.isBusy(session.state)

        return VStack(alignment: .leading, spacing: 8) {
            AinkradTextArea(text: $draft, placeholder: "Message Assistant…",
                            minHeight: 34, maxHeight: 80, autoFocus: autoFocusOnAppear,
                            onSubmit: { send() })
                .disabled(isBusy)

            HStack(spacing: 8) {
                AgentSwitcherView(store: environment.agentStore, tokens: tokens)

                AssistantConnectionModelPicker(
                    model: modelPicker,
                    tokens: tokens,
                    onManageConnections: { environment.isSettingsPresented = true }
                )

                permissionModeSelect

                Spacer(minLength: 8)

                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(canSend(isBusy: isBusy) ? tokens.accentSecondary : tokens.foreground.opacity(0.25))
                }
                .buttonStyle(.plain)
                .disabled(!canSend(isBusy: isBusy))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.45)))
        .background(
            // Tab-cycle affordance (M7 Slice 5a Task 5): swallows a plain Tab
            // keyDown to advance the active agent, but ONLY when the draft is
            // empty — otherwise Tab still moves keyboard focus as normal. A
            // remappable `ShortcutAction` binding is explicitly deferred; this
            // is a local (app-scoped, not global) monitor, same pattern as
            // `KeyboardShortcutMonitor`.
            ComposerTabCycleMonitor(
                isDraftEmpty: { draft.isEmpty },
                onCycle: { environment.agentStore.cycleActive() }
            )
        )
        .padding(14)
    }

    private var permissionModeSelect: some View {
        let store = environment.agentPermissionStore
        // `AinkradSelect` is a single `Binding<T>` with no on-change hook, so the
        // `store.setMode` write-back rides in the binding's setter.
        return AinkradSelect(
            items: AgentPermissionMode.allCases,
            selection: Binding(get: { store.mode }, set: { store.setMode($0) }),
            label: { AssistantComposerBar.title($0) }
        )
        .fixedSize()
    }

    private func canSend(isBusy: Bool) -> Bool {
        !isBusy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend(isBusy: AssistantComposerBar.isBusy(session.state)) else { return }
        let text = draft
        draft = ""
        session.send(text)
    }

    static func isBusy(_ state: AgentSession.State) -> Bool {
        switch state {
        case .thinking, .streaming, .callingTool, .awaitingApproval: return true
        case .idle, .failed: return false
        }
    }

    static func title(_ mode: AgentPermissionMode) -> String {
        switch mode {
        case .ask: return "Ask"
        case .autoApprove: return "Auto"
        case .fullAuto: return "Full-auto"
        }
    }
}

/// Installs a local `keyDown` monitor (app-scoped, not global — mirrors
/// `KeyboardShortcutMonitor`'s established pattern) that swallows a plain Tab
/// keystroke to cycle the active agent, ONLY while the composer's draft is
/// empty — otherwise Tab is returned untouched so it keeps moving keyboard
/// focus everywhere else (M7 Slice 5a Task 5). Zero-size, invisible; attached
/// via `.background(...)` so it rides the composer's lifetime.
private struct ComposerTabCycleMonitor: NSViewRepresentable {
    let isDraftEmpty: () -> Bool
    let onCycle: () -> Void

    func makeNSView(context: Context) -> MonitoringView {
        let view = MonitoringView()
        view.isDraftEmpty = isDraftEmpty
        view.onCycle = onCycle
        return view
    }

    func updateNSView(_ nsView: MonitoringView, context: Context) {
        nsView.isDraftEmpty = isDraftEmpty
        nsView.onCycle = onCycle
    }

    final class MonitoringView: NSView {
        var isDraftEmpty: (() -> Bool)?
        var onCycle: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else { return event }
                    // Tab, no modifiers (keyCode 48) — Shift-Tab and any
                    // Tab+modifier combo pass through untouched.
                    let isPlainTab = event.keyCode == 48
                        && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
                    if isPlainTab, self.isDraftEmpty?() == true {
                        self.onCycle?()
                        return nil
                    }
                    return event
                }
            } else if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
