import SwiftUI

/// A neon capsule toggle in place of the stock macOS switch: the track
/// lights with the accent when on, the knob carries a soft glow. Shared
/// across the Settings sections.
struct NeonToggle: View {
    @Binding var isOn: Bool
    let tokens: DesignTokens

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? tokens.accentPrimary.opacity(0.9) : tokens.surface)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isOn ? tokens.accentSecondary.opacity(0.65) : tokens.foreground.opacity(0.18),
                                lineWidth: 1
                            )
                    )

                Circle()
                    .fill(.white)
                    .padding(3)
                    .shadow(color: isOn ? tokens.accentSecondary.opacity(0.7) : .black.opacity(0.4), radius: 3)
            }
            .frame(width: 40, height: 22)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.16), value: isOn)
    }
}

/// Masked API-key entry with a reveal (eye) toggle — HUD card styling, no
/// separator lines. Shared by the Assistant Connections settings (AIN — M5
/// Phase B). Never logs or otherwise surfaces the value beyond this field.
struct NeonSecureField: View {
    @Binding var text: String
    let placeholder: String
    let tokens: DesignTokens

    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(AinkradFont.mono(13))
            .foregroundStyle(tokens.foreground)
            .tint(tokens.accentSecondary)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.foreground.opacity(0.55))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
    }
}

/// A generic segmented selector in the HUD language — the shared form of the
/// `segmented(...)` idiom in `AppearanceSettingsView`, usable outside that
/// file (e.g. the Assistant's provider picker).
struct NeonSegmentedPicker<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String
    let tokens: DesignTokens

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                let isSelected = item == selection
                Button {
                    selection = item
                } label: {
                    Text(label(item))
                        .font(AinkradFont.display(12, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? tokens.accentPrimary.contrastingText : tokens.foreground.opacity(0.75))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? tokens.accentPrimary.opacity(0.9) : tokens.surfaceElevated.opacity(0.5)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tokens.accentPrimary.opacity(isSelected ? 0 : 0.15), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.14), value: selection)
    }
}
