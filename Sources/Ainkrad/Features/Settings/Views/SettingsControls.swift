import SwiftUI
import AinkradAppKit

/// Cardinal HUD switch, shared across the Settings sections. Thin adapter over
/// the kit's `AinkradToggle` — the `tokens` parameter is unused (the kit reads
/// its theme from the injected `\.ainkradTheme` environment) but kept so this
/// wave's consumers stay untouched.
struct NeonToggle: View {
    @Binding var isOn: Bool
    let tokens: DesignTokens // unused adapter param — kit reads \.ainkradTheme

    var body: some View {
        AinkradToggle(isOn: $isOn)
    }
}

/// Masked API-key entry with a reveal (eye) toggle. Thin adapter over the kit's
/// `AinkradSecureField` (which already carries the reveal toggle + chamfer focus
/// ring). The `tokens` parameter is unused (kit reads `\.ainkradTheme`) but kept
/// so its Assistant Connections consumers stay untouched this wave. Never logs or
/// otherwise surfaces the value beyond this field.
struct NeonSecureField: View {
    @Binding var text: String
    let placeholder: String
    let tokens: DesignTokens // unused adapter param — kit reads \.ainkradTheme

    var body: some View {
        AinkradSecureField(text: $text, placeholder: placeholder)
    }
}

/// A generic segmented selector in the HUD language. Thin adapter over the kit's
/// `AinkradSegmentedPicker`. The `tokens` parameter is unused (kit reads
/// `\.ainkradTheme`) but kept so this wave's consumers stay untouched.
struct NeonSegmentedPicker<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String
    let tokens: DesignTokens // unused adapter param — kit reads \.ainkradTheme

    var body: some View {
        AinkradSegmentedPicker(items: items, selection: $selection, label: label)
    }
}
