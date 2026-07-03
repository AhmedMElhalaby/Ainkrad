import SwiftUI

/// The floating-island hero artwork at the center of an empty workspace.
/// The bundled images carry real alpha (the pure-black source backgrounds
/// were "unmultiplied" into transparency at asset-prep time), so they draw
/// normally — no blend mode — and survive rasterization such as the
/// Launcher's backdrop blur. Drifts vertically in a slow hover; Reduce
/// Motion holds it still. A live, interactive island (parallax/3D) is
/// planned as a future upgrade — see Living Island concept in the vault.
struct FloatingIslandView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var imageName: String {
        // Island art ships in two accents; new themes use the nearer one.
        switch environment.themeManager.currentTheme {
        case .cyberPurple, .dracula, .tokyoNight: return "Island-CyberPurple"
        default: return "Island-NeonBlue"
        }
    }

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .offset(y: reduceMotion ? 0 : (isHovering ? -9 : 9))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) {
                    isHovering = true
                }
            }
    }
}
