import SwiftUI

/// The floating-island hero artwork at the center of an empty workspace.
/// The source images sit on pure black, so they're screen-blended over the
/// ambient sky — black vanishes, the glows add light. Drifts vertically in
/// a slow hover; Reduce Motion holds it still. A live, interactive island
/// (parallax/3D) is planned as a future upgrade — this is the 2D draft.
struct FloatingIslandView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var imageName: String {
        switch environment.themeManager.currentTheme {
        case .neonBlue: return "Island-NeonBlue"
        case .cyberPurple: return "Island-CyberPurple"
        }
    }

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .blendMode(.screen)
            .offset(y: reduceMotion ? 0 : (isHovering ? -9 : 9))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) {
                    isHovering = true
                }
            }
    }
}
