import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The first-run gate. Deliberately non-dismissible: no scrim tap, no Escape,
/// no onDismiss closure — that trio is what makes every other overlay closable.
/// ⌘Q still quits; it is not routed through KeyboardShortcutMonitor.
struct SetupOverlayView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var coordinator: SetupCoordinator?

    var body: some View {
        let tokens = environment.themeManager.tokens

        GeometryReader { geo in
            ZStack {
                Color.black.opacity(OverlayChrome.backdropOpacity)
                    .ignoresSafeArea()          // no .onTapGesture — intentional

                if let coordinator {
                    panel(coordinator: coordinator, tokens: tokens)
                        .frame(width: min(geo.size.width * 0.62, 720),
                               height: min(geo.size.height * 0.72, 640))
                }
            }
        }
        .onAppear {
            if coordinator == nil {
                coordinator = SetupCoordinator(
                    persistence: environment.persistence,
                    isProvisionalHome: environment.isProvisionalHome)
            }
        }
        // Deliberately no .onKeyPress(.escape) — this overlay must not be
        // dismissible by keyboard either. ⌘Q is exempted upstream in
        // `SetupGate.swallows`, not handled here.
    }

    private func panel(coordinator: SetupCoordinator, tokens: DesignTokens) -> some View {
        VStack(spacing: 0) {
            header(coordinator: coordinator, tokens: tokens)
            SetupStepBody(step: coordinator.step, coordinator: coordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .hudPanelChrome(tokens: tokens)
    }

    private func header(coordinator: SetupCoordinator, tokens: DesignTokens) -> some View {
        HStack {
            Text(coordinator.step.title)
                .font(AinkradFont.display(16, weight: .semibold))
                .foregroundStyle(tokens.foreground)
            Spacer()
            Text("\((coordinator.steps.firstIndex(of: coordinator.step) ?? 0) + 1) of \(coordinator.steps.count)")
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.62))
        }
        .padding(20)
    }
}

/// Minimal per-step content: a title and a Continue button. Tasks 4-9 replace
/// each case with the real step content; the switch itself is the seam they
/// hook into.
struct SetupStepBody: View {
    let step: SetupStep
    let coordinator: SetupCoordinator

    var body: some View {
        VStack(spacing: AinkradSpacing.md) {
            Spacer(minLength: 0)
            Text(step.title)
                .font(AinkradFont.display(20, weight: .semibold))
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                AinkradButton(title: step == .done ? "Finish" : "Continue", style: .primary) {
                    if step == .done {
                        coordinator.complete()
                    } else {
                        coordinator.advance()
                    }
                }
            }
        }
        .padding(20)
    }
}
