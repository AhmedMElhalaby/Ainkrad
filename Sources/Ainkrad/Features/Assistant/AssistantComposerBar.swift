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
            AinkradTextArea(text: $draft, placeholder: "Message Assistant…")
                .disabled(isBusy)

            HStack(spacing: 8) {
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
