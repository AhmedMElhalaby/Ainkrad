import SwiftUI

/// The in-app HUD shown before Ainkrad actually quits — summoned by
/// `QuitCoordinator.isConfirming` from ⌘Q, the app menu's Quit, or the
/// Dock's Quit (all funnel through `AinkradAppDelegate.applicationShouldTerminate`).
/// Same visual language as the Launcher/Settings/App Store/Workspace
/// Overview overlays. Cancel keeps the app running; Quit (optionally with
/// "Don't ask again") delivers the coordinator's deferred termination reply.
struct QuitConfirmationView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var dontAskAgain = false

    var body: some View {
        let tokens = environment.themeManager.tokens
        let coordinator = environment.quitCoordinator

        GeometryReader { geo in
            ZStack {
                Color.black.opacity(OverlayChrome.backdropOpacity)
                    .ignoresSafeArea()
                    .onTapGesture { coordinator.cancel() }

                panel(tokens: tokens, coordinator: coordinator)
                    .frame(width: min(max(340, geo.size.width * 0.3), 420))
            }
        }
    }

    private func panel(tokens: DesignTokens, coordinator: QuitCoordinator) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Quit Ainkrad?")
                    .font(AinkradFont.display(16, weight: .semibold))
                    .foregroundStyle(tokens.foreground)

                Text("Running workspaces and their sessions will end.")
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 26)
            .padding(.horizontal, 26)
            .padding(.bottom, 18)

            Toggle("Don't ask again", isOn: $dontAskAgain)
                .toggleStyle(.switch)
                .tint(tokens.accentPrimary)
                .font(AinkradFont.display(12, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.8))
                .padding(.horizontal, 26)
                .padding(.bottom, 20)

            LinearGradient(
                colors: [.clear, tokens.accentPrimary.opacity(0.4), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            .padding(.horizontal, 22)

            HStack(spacing: 10) {
                cancelButton(tokens: tokens, coordinator: coordinator)
                quitButton(tokens: tokens, coordinator: coordinator)
            }
            .padding(20)
        }
        .hudPanelChrome(tokens: tokens)
        .onKeyPress(.escape) { coordinator.cancel(); return .handled }
    }

    private func cancelButton(tokens: DesignTokens, coordinator: QuitCoordinator) -> some View {
        Button { coordinator.cancel() } label: {
            Text("Cancel")
                .font(AinkradFont.display(12, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.8))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(tokens.surfaceElevated.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(tokens.accentPrimary.opacity(0.28), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
    }

    private func quitButton(tokens: DesignTokens, coordinator: QuitCoordinator) -> some View {
        Button { coordinator.confirm(dontAskAgain: dontAskAgain) } label: {
            Text("Quit")
                .font(AinkradFont.display(12, weight: .semibold))
                .foregroundStyle(tokens.background)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(tokens.accentPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: tokens.accentPrimary.opacity(0.5), radius: 10)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
    }
}
