import SwiftUI

/// The floating-island hero artwork at the center of an empty workspace
/// (AIN-107, "Living Island"). Renders the original static painted artwork,
/// selecting the Blue or Purple variant to match the active color scheme.
///
/// Live motion (depth-parallax, ambient sway/breathe/glow, drifting
/// particles, a reactive energy ring/flare) was previously layered on here
/// and has been removed — the plain static image is the intended baseline.
/// `isVisible` is kept as the gating hook for any future motion work; the
/// static image ignores it.
struct FloatingIslandView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Whether the island is the one currently on screen. Unused while the
    /// artwork is static; retained so a future live version can gate its
    /// motion off backgrounded or covered workspaces without a signature
    /// change here or at the call site (`EmptyWorkspaceView.islandVisible`).
    var isVisible: Bool = true

    private var imageName: String {
        switch environment.themeManager.currentTheme {
        case .cyberPurple, .dracula, .tokyoNight: return "Island-CyberPurple"
        default: return "Island-NeonBlue"
        }
    }

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
    }
}
