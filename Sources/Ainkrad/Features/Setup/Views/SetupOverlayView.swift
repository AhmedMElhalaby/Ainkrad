import SwiftUI

/// Placeholder for the first-run setup wizard — Task 3 replaces this with the
/// real chrome. It exists now so the gate is a real, blocking surface: an opaque
/// scrim over the whole window that swallows every click, with no dismiss
/// affordance of any kind.
struct SetupOverlayView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(OverlayChrome.backdropOpacity)
                .ignoresSafeArea()
                // Consumes clicks so nothing behind the gate is reachable by
                // mouse either. Deliberately NOT a dismissal.
                .contentShape(Rectangle())
                .onTapGesture { }

            Text("Setup")
        }
    }
}
