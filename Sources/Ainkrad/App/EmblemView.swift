import SwiftUI

/// The brand chevron — the upward arrow from the Ainkrad logo mark,
/// drawn as a path so it can be stroked, glowed, and themed natively.
struct ChevronMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Outer arrow: apex at top center, feet at the bottom corners,
        // with a notch cut upward into the bottom center (the "A").
        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: w * 0.68, y: h))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.42))
        path.addLine(to: CGPoint(x: w * 0.32, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path
    }
}

/// The floating "power core" shown on an empty workspace: the arch ring
/// with the chevron inside, breathing slowly. Reduce Motion freezes the
/// pulse at full glow.
struct EmblemView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        let tokens = environment.themeManager.tokens
        let pulse = reduceMotion ? 1.0 : (isBreathing ? 1.0 : 0.72)

        ZStack {
            // Arch ring — brightest at the top, fading toward the base,
            // like the brand mark's halo.
            Circle()
                .stroke(
                    AngularGradient(
                        stops: [
                            .init(color: tokens.accentPrimary.opacity(0.1), location: 0),
                            .init(color: tokens.accentSecondary, location: 0.25),
                            .init(color: tokens.accentPrimary.opacity(0.1), location: 0.5),
                            .init(color: tokens.accentPrimary.opacity(0.05), location: 0.75),
                            .init(color: tokens.accentPrimary.opacity(0.1), location: 1),
                        ],
                        center: .center,
                        angle: .degrees(-90)
                    ),
                    lineWidth: 2
                )
                .frame(width: 150, height: 150)
                .shadow(color: tokens.accentPrimary.opacity(0.6 * pulse), radius: 18)

            ChevronMark()
                .fill(tokens.foreground)
                .frame(width: 54, height: 46)
                .shadow(color: tokens.accentSecondary.opacity(0.8 * pulse), radius: 10)
                .offset(y: 6)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }
}
