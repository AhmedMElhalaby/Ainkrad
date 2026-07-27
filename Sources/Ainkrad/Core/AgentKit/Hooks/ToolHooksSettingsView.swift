import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Pure, validatable draft for the add/edit form — keeps validation testable
/// without SwiftUI.
struct ToolHookDraft: Equatable {
    var event: ToolHookEvent = .postToolUse
    var match: String = ""
    var command: String = ""
    var timeoutSeconds: Int = 30

    /// Recomputed from the current fields on every access, so mutating
    /// `match`/`command`/`timeoutSeconds` directly keeps this in sync
    /// without any explicit setter plumbing.
    var validationError: String? {
        if match.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter a tool-name match (e.g. edit_file or *)." }
        if command.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter a shell command to run." }
        if timeoutSeconds <= 0 { return "Timeout must be positive." }
        return nil
    }

    func build() -> ToolHook? {
        guard validationError == nil else { return nil }
        return ToolHook(id: UUID(), enabled: true, event: event,
                         match: match.trimmingCharacters(in: .whitespaces),
                         command: command.trimmingCharacters(in: .whitespaces),
                         timeoutSeconds: timeoutSeconds)
    }
}

/// Cardinal HUD settings surface for tool hooks. Zero native controls: a
/// chamfered list of hook rows (each with a custom enable toggle chip + delete),
/// and an inline add/edit form using the host's text-field style (NOT
/// `SecureField`/`Picker`/`Stepper`). Event choice is a two-chip segmented
/// selector.
struct ToolHooksSettingsView: View {
    @Bindable var store: ToolHooksStore
    let tokens: DesignTokens
    @State private var draft = ToolHookDraft()
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tool Hooks")
                .font(AinkradFont.display(13, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.9))
            Text("Run a shell command before or after a tool call; PreToolUse can block the call.")
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.foreground.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            if store.hooks.isEmpty {
                Text("No hooks configured.")
                    .font(AinkradFont.mono(11))
                    .foregroundStyle(tokens.foreground.opacity(0.4))
            } else {
                VStack(spacing: 6) {
                    ForEach(store.hooks) { hook in hookRow(hook) }
                }
            }

            addForm
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.45)))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: store.hooks.count)
    }

    private func hookRow(_ hook: ToolHook) -> some View {
        HStack(spacing: 10) {
            eventBadge(hook.event)
            Text(hook.match)
                .font(AinkradFont.mono(12))
                .foregroundStyle(tokens.accentSecondary)
            Text(hook.command)
                .font(AinkradFont.mono(11))
                .foregroundStyle(tokens.foreground.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            enableChip(hook)
            Button {
                store.remove(id: hook.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.danger.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.background.opacity(0.4)))
    }

    private func enableChip(_ hook: ToolHook) -> some View {
        Button {
            var h = hook
            h.enabled.toggle()
            store.update(h)
        } label: {
            Text(hook.enabled ? "on" : "off")
                .font(AinkradFont.mono(10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(ChamferShape(cut: 3).fill((hook.enabled ? tokens.success : tokens.foreground).opacity(0.18)))
        }
        .buttonStyle(.plain)
    }

    private func eventBadge(_ event: ToolHookEvent) -> some View {
        Text(event == .preToolUse ? "PRE" : "POST")
            .font(AinkradFont.mono(9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(ChamferShape(cut: 3).fill(tokens.accentPrimary.opacity(0.2)))
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                eventSelector
                timeoutStepper
                Spacer(minLength: 0)
                AinkradButton(title: "Add hook", style: .primary) {
                    if let hook = draft.build() {
                        store.add(hook)
                        draft = ToolHookDraft()
                    }
                }
                .disabled(draft.validationError != nil)
                .opacity(draft.validationError != nil ? 0.4 : 1)
            }
            AinkradTextField(text: $draft.match, placeholder: "Match (edit_file, mcp/*, *)")
            AinkradTextField(text: $draft.command, placeholder: "Shell command (uses $AINKRAD_TOOL_PATH etc.)")
        }
    }

    private var timeoutStepper: some View {
        HStack(spacing: 6) {
            Button {
                draft.timeoutSeconds = max(1, draft.timeoutSeconds - 10)
            } label: {
                Text("−")
                    .font(AinkradFont.mono(11, weight: .medium))
                    .frame(width: 16, height: 16)
                    .background(ChamferShape(cut: 3).fill(tokens.accentSecondary.opacity(0.08)))
            }
            .buttonStyle(.plain)

            Text("\(draft.timeoutSeconds)s")
                .font(AinkradFont.mono(11))
                .foregroundStyle(tokens.foreground.opacity(0.7))
                .frame(minWidth: 32)

            Button {
                draft.timeoutSeconds = min(600, draft.timeoutSeconds + 10)
            } label: {
                Text("+")
                    .font(AinkradFont.mono(11, weight: .medium))
                    .frame(width: 16, height: 16)
                    .background(ChamferShape(cut: 3).fill(tokens.accentSecondary.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
    }

    private var eventSelector: some View {
        HStack(spacing: 6) {
            ForEach(ToolHookEvent.allCases, id: \.self) { event in
                Button {
                    draft.event = event
                } label: {
                    Text(event == .preToolUse ? "Pre" : "Post")
                        .font(AinkradFont.mono(11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(ChamferShape(cut: 3).fill(tokens.accentSecondary.opacity(draft.event == event ? 0.3 : 0.08)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
