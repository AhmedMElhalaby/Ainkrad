import SwiftUI

/// The Assistant composer: one seamless neon surface (soft elevated fill + a
/// focus ring — the only stroke) with a bottom control strip holding the
/// connection·model pill, the compact permission-mode menu, and send. Owns the
/// draft binding shared with `AssistantRootView`.
struct AssistantComposerBar: View {
    @Environment(AppEnvironment.self) private var environment
    let session: AgentSession
    let tokens: DesignTokens
    let modelPicker: AssistantModelPickerModel
    @Binding var draft: String
    var autoFocusOnAppear: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        let isBusy = AssistantComposerBar.isBusy(session.state)

        return VStack(alignment: .leading, spacing: 8) {
            TextField("Message Assistant…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(AinkradFont.display(13))
                .foregroundStyle(tokens.foreground)
                .tint(tokens.accentSecondary)
                .focused($isFocused)
                .disabled(isBusy)
                .lineLimit(1...6)
                .onSubmit { send() }

            HStack(spacing: 8) {
                AssistantConnectionModelPicker(
                    model: modelPicker,
                    tokens: tokens,
                    onManageConnections: { environment.isSettingsPresented = true }
                )

                permissionModeMenu

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
        .background(RoundedRectangle(cornerRadius: 12).fill(tokens.surfaceElevated.opacity(0.45)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(tokens.accentSecondary.opacity(isFocused ? 0.5 : 0), lineWidth: 1)
        )
        .shadow(color: tokens.accentPrimary.opacity(isFocused ? 0.18 : 0), radius: 10)
        .animation(.easeOut(duration: 0.16), value: isFocused)
        .padding(14)
        .onAppear {
            if autoFocusOnAppear { isFocused = true }
        }
    }

    private var permissionModeMenu: some View {
        let store = environment.agentPermissionStore
        return Menu {
            ForEach(AgentPermissionMode.allCases, id: \.self) { mode in
                Button { store.setMode(mode) } label: {
                    if store.mode == mode {
                        Label(AssistantComposerBar.title(mode), systemImage: "checkmark")
                    } else {
                        Text(AssistantComposerBar.title(mode))
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(AssistantComposerBar.dotColor(store.mode, tokens))
                    .frame(width: 7, height: 7)
                Text(AssistantComposerBar.title(store.mode))
                    .font(AinkradFont.display(11, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 8))
            }
            .foregroundStyle(tokens.foreground.opacity(0.75))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(tokens.surfaceElevated.opacity(0.45)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .animation(.easeOut(duration: 0.16), value: store.mode)
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

    /// Dot color encodes the mode: Ask = accentSecondary, Auto = accentPrimary,
    /// Full-auto = accentTertiary (the destructive-leaning accent).
    static func dotColor(_ mode: AgentPermissionMode, _ tokens: DesignTokens) -> Color {
        switch mode {
        case .ask: return tokens.accentSecondary
        case .autoApprove: return tokens.accentPrimary
        case .fullAuto: return tokens.accentTertiary
        }
    }
}
