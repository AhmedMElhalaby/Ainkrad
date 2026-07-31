import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// A read-only display of the current push-to-talk chord.
///
/// All of `VoiceSettingsView` decomposed into declarative `SettingsField`s
/// except this: the chord is rebound in Settings → Keyboard
/// (`ShortcutsSettingsView` already renders every `ShortcutAction` including
/// `.pushToTalk`), so there is nothing to edit here. `.shortcut` implies an
/// editable recorder and the kit has no informational field kind, so this stays
/// a small `.custom` — the escape hatch used for exactly what it is for.
@MainActor
struct VoiceHotkeyDisplay: View {
    let shortcuts: ShortcutStore
    let tokens: DesignTokens

    var body: some View {
        HStack(spacing: AinkradSpacing.sm) {
            Text(shortcuts.chord(for: .pushToTalk).displayString)
                .font(AinkradFont.mono(12))
                .foregroundStyle(tokens.foreground.opacity(0.85))
                .padding(.horizontal, AinkradSpacing.sm)
                .padding(.vertical, AinkradSpacing.xs)
                .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.6)))
            Text("Change in Settings \u{2192} Keyboard")
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.foreground.opacity(0.45))
        }
    }
}
