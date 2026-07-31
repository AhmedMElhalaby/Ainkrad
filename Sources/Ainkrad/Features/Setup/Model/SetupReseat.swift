import Foundation

/// Decides what happens to the wizard's coordinator once the Home step has
/// adopted a vault and swapped the environment.
///
/// Pure and view-free so the two outcomes can be tested without SwiftUI. The
/// coordinator passed in must already be built against the ADOPTED home's
/// `PersistenceStore` — re-seating exists precisely because the outgoing one was
/// built against the provisional store.
@MainActor
enum SetupReseat {
    enum Outcome: Equatable {
        /// The wizard continues, at the step reported. Equal to the requested
        /// target unless the target was unreachable, which the caller logs.
        case resumed(SetupStep)
        /// The adopted vault is an existing Home whose setup was already
        /// completed at the current version — a reinstall-and-restore.
        ///
        /// `AinkradHome.validate` accepts an existing Home on purpose; that is
        /// the restore path. When it happens there is nothing left to ask: the
        /// fresh coordinator's step list collapses to `[.done]`, so walking
        /// toward `.appearance` cannot arrive and the wizard would sit on a
        /// screen whose only button is inert. The marker on disk is the user's
        /// own completed setup, so the honest answer is to honour it and lower
        /// the gate. Nothing is WRITTEN here — `complete()` stays Task 10's.
        case alreadyConfigured
    }

    static func plan(_ fresh: SetupCoordinator, toward target: SetupStep?) -> Outcome {
        guard !fresh.isComplete else { return .alreadyConfigured }
        // Only walk toward a target the fresh list actually contains. Walking
        // blindly runs `advance()` until it can advance no further — i.e. all
        // the way to `.done` — which is not "stalled where the target was", it
        // is "skipped every step the user still owes".
        //
        // This is the `setupVersion` bump path, not a hypothetical: a user who
        // adopts a vault with an older completed marker gets a step list of
        // only the newly introduced steps plus `.done`, while the outgoing
        // coordinator's successor to `.home` is whatever came next in the FULL
        // list. Those disagree by construction. Landing on the first owed step
        // (which is where `init` already put `fresh`) asks the new step; landing
        // on `.done` writes the new version's marker having asked nothing.
        if let target, fresh.steps.contains(target) {
            while fresh.step != target, fresh.canAdvance { fresh.advance() }
        }
        return .resumed(fresh.step)
    }
}
