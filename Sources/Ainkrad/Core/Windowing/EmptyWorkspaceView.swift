import SwiftUI

/// The bare-canvas empty state. See Navigation & Settings Architecture.md.
struct EmptyWorkspaceView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Text("Press ⌘K to open an app.")
            .font(.system(size: 13))
            .foregroundStyle(environment.themeManager.tokens.foreground.opacity(0.4))
    }
}
