import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The first-run gate. Deliberately non-dismissible: no scrim tap, no Escape,
/// no onDismiss closure — that trio is what makes every other overlay closable.
/// ⌘Q still quits; it is not routed through KeyboardShortcutMonitor.
struct SetupOverlayView: View {
    @Environment(AppEnvironment.self) private var environment
    /// Read live from `GeneralSettingsStore.uiReduceMotion` (injected in
    /// `AinkradApp`), so the Motion & Sound step's toggle stops the remaining
    /// steps animating the instant it is flipped.
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var coordinator: SetupCoordinator?
    /// Set by the Home step's adoption. Survives the environment swap for the
    /// same reason the coordinator does — same view identity, same `@State` —
    /// and is read four steps later by `.done`.
    @State private var didMigrateLegacyData = false
    /// Raised by a step when it needs a blocking answer. Owned here so the modal
    /// is centred on the WHOLE gate rather than inside the step's content group,
    /// which is scrollable and can carry its buttons below the fold.
    @State private var modals = SetupModalPresenter()

    var body: some View {
        let tokens = environment.themeManager.tokens

        ZStack {
            // The scrim stays; the PANEL is what went away. The island keeps
            // living behind it — that is the point of running the wizard after
            // bootstrap. Still no .onTapGesture — intentional.
            Color.black.opacity(OverlayChrome.backdropOpacity)
                .ignoresSafeArea()

            if let coordinator {
                stage(coordinator: coordinator, tokens: tokens)
                    .environment(modals)
            }

            // Above the stage, always. A step raises this only for a decision
            // that blocks the wizard; refusals stay inline in the step.
            if let modal = modals.modal {
                SetupModalView(modal: modal, tokens: tokens)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: modals.modal?.id)
        .onAppear {
            if coordinator == nil {
                coordinator = SetupCoordinator(
                    persistence: environment.persistence,
                    isProvisionalHome: environment.isProvisionalHome,
                    isReplay: environment.isSetupReplay)
            }
        }
        // Deliberately no .onKeyPress(.escape) — this overlay must not be
        // dismissible by keyboard either. ⌘Q is exempted upstream in
        // `SetupGate.swallows`, not handled here.
    }

    /// Full-bleed: rail, heading, step, nav — no panel chrome, no fixed size.
    private func stage(coordinator: SetupCoordinator, tokens: DesignTokens) -> some View {
        SetupStage(coordinator: coordinator,
                   tokens: tokens,
                   reduceMotion: reduceMotion) { step in
            SetupStepBody(step: step,
                          coordinator: coordinator,
                          didMigrateLegacyData: didMigrateLegacyData,
                          onAdopted: { rebuilt, migrated in
                              didMigrateLegacyData = migrated
                              reseat(after: coordinator, using: rebuilt)
                          })
        }
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
            // The other gate-lowering site (see `SetupDoneStepView.finish()`):
            // the status item is suppressed while the gate is up and nothing
            // re-installs it on its own, so it has to be brought back here too.
            rebuilt.menuBarController?.install()
        case .resumed(let step):
            // Never silently: if the target was unreachable the wizard would
            // otherwise appear to have simply not moved.
            if let target, step != target {
                Log.persistence.error(
                    "Setup re-seat could not reach \(target.rawValue, privacy: .public); stopped at \(step.rawValue, privacy: .public)")
            }
        }
    }

    // The "n of m" header is gone with the panel. The rail replaces it, and is
    // spatial on purpose: the counter's denominator changed at the vault swap
    // ("3 of 8" → "2 of 7"), which the rail cannot contradict because it only
    // ever draws the steps actually owed.
}

/// Minimal per-step content: a title and a Continue button. Tasks 4-9 replace
/// each case with the real step content; the switch itself is the seam they
/// hook into.
struct SetupStepBody: View {
    let step: SetupStep
    let coordinator: SetupCoordinator
    /// True once the Home step's adoption migrated a legacy container into the
    /// adopted vault. Carried to `.done`, which is the only screen left to
    /// acknowledge it on — see `SetupDoneStepView`.
    let didMigrateLegacyData: Bool
    /// Called with the rebuilt environment, and whether adoption migrated a
    /// legacy container, once the Home step adopts a vault.
    let onAdopted: (AppEnvironment, Bool) -> Void

    /// A `switch`, not an if/else chain: every `SetupStep` now has a real view,
    /// and exhaustiveness is what makes the compiler — rather than a user
    /// staring at an empty panel — catch the next step that ships without one.
    /// The `.welcome` case shipped as a bare placeholder for exactly that
    /// reason, and it was the first screen anyone saw.
    var body: some View {
        switch step {
        case .welcome:
            SetupWelcomeStepView(coordinator: coordinator)
        case .home:
            SetupHomeStepView(coordinator: coordinator, onAdopted: onAdopted)
        case .appearance:
            SetupAppearanceStepView(coordinator: coordinator)
        case .motionAndSound:
            SetupMotionSoundStepView(coordinator: coordinator)
        case .you:
            SetupYouStepView(coordinator: coordinator)
        case .providers:
            SetupProvidersStepView(coordinator: coordinator)
        case .assistant:
            SetupAssistantStepView(coordinator: coordinator)
        case .done:
            SetupDoneStepView(coordinator: coordinator,
                              didMigrateLegacyData: didMigrateLegacyData)
        }
    }
}
