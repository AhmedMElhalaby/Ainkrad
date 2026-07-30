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
            SetupStepBody(step: coordinator.step,
                          coordinator: coordinator,
                          onAdopted: { rebuilt in reseat(after: coordinator, using: rebuilt) })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .hudPanelChrome(tokens: tokens)
    }

    /// Re-seats the coordinator onto the ADOPTED home's `PersistenceStore` after
    /// the Home step swaps the environment.
    ///
    /// The coordinator held here was built against the provisional home. Left
    /// alone it survives the swap (same view identity, same `@State`) and would
    /// write the completion marker into a temporary directory the OS deletes —
    /// so the gate would come back on every future launch. Rebuilding it with
    /// `isProvisionalHome: false` also drops `.home` from the remaining steps,
    /// which is the correct answer: a Home is now configured and must never be
    /// re-asked. `complete()` is NOT called here — Task 10 owns completion.
    private func reseat(after outgoing: SetupCoordinator, using rebuilt: AppEnvironment) {
        // Where the outgoing coordinator was about to go.
        let target: SetupStep? = outgoing.steps.firstIndex(of: .home)
            .map { $0 + 1 }
            .flatMap { outgoing.steps.indices.contains($0) ? outgoing.steps[$0] : nil }

        let fresh = SetupCoordinator(persistence: rebuilt.persistence, isProvisionalHome: false)
        coordinator = fresh

        switch SetupReseat.plan(fresh, toward: target) {
        case .alreadyConfigured:
            // A reinstall-and-restore: the adopted vault already carries a
            // completed SetupDocument at the current version. Re-walking the
            // wizard would re-ask questions this user has answered, and the
            // fresh coordinator has no steps left to walk anyway. Lower the
            // gate. Nothing is written — the marker is already there.
            Log.persistence.info(
                "Adopted an already-configured Home; first-run setup is complete for it")
            rebuilt.isSetupPresented = false
        case .resumed(let step):
            // Never silently: if the target was unreachable the wizard would
            // otherwise appear to have simply not moved.
            if let target, step != target {
                Log.persistence.error(
                    "Setup re-seat could not reach \(target.rawValue, privacy: .public); stopped at \(step.rawValue, privacy: .public)")
            }
        }
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
    /// Called with the rebuilt environment once the Home step adopts a vault.
    let onAdopted: (AppEnvironment) -> Void

    var body: some View {
        if step == .home {
            SetupHomeStepView(coordinator: coordinator, onAdopted: onAdopted)
        } else if step == .appearance {
            SetupAppearanceStepView(coordinator: coordinator)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: AinkradSpacing.md) {
            Spacer(minLength: 0)
            Text(step.title)
                .font(AinkradFont.display(20, weight: .semibold))
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                // `.done` is deliberately inert here: this placeholder must never
                // write a completion marker. `coordinator.complete()` persists
                // SetupDocument to disk immediately, which would suppress the
                // gate on every future launch — including during Task 4/10
                // hand-verification, before any real step content exists.
                // Task 10 owns wiring the real "Finish" action.
                if step == .done {
                    AinkradButton(title: "Finish", style: .primary) {}
                        .disabled(true)
                } else {
                    AinkradButton(title: "Continue", style: .primary) {
                        coordinator.advance()
                    }
                }
            }
        }
        .padding(20)
    }
}
