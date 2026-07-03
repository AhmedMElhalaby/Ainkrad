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
