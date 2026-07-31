import Foundation
import AinkradHostRuntime

@MainActor
@Observable
final class SetupCoordinator {
    /// Bump when a step is added. Existing users are then asked for that step only.
    static let currentSetupVersion = 1

    private let persistence: PersistenceStore
    private(set) var steps: [SetupStep]
    private(set) var step: SetupStep
    private(set) var isComplete: Bool
    /// Steps the user walked past without satisfying. Seeded from the marker, so
    /// a relaunch resumes owing exactly what the last run recorded.
    private(set) var deferredSteps: Set<SetupStep>

    init(persistence: PersistenceStore, isProvisionalHome: Bool) {
        let doc = persistence.load(SetupDocument.self) ?? SetupDocument()
        let completedVersion = doc.completedAt == nil ? -1 : doc.setupVersion
        let deferred = Set(doc.deferredSteps.compactMap(SetupStep.init(rawValue:)))

        let resolvedSteps: [SetupStep]
        if isProvisionalHome {
            // No vault chosen yet: the full wizard, always.
            resolvedSteps = SetupStep.allCases
        } else {
            // Only steps introduced since the version the user completed — or
            // deferred by them, which owes the step for the same reason and is
            // resolved by the same filter — plus the closing screen. `.home` is
            // never re-asked: a configured vault stands.
            resolvedSteps = SetupStep.allCases.filter {
                $0 == .done
                    || ($0 != .home && ($0.introducedIn > completedVersion || deferred.contains($0)))
            }
        }

        // Assigned only after every local is resolved: with `@Observable`,
        // reading `self.steps` mid-init (before every stored property has a
        // value) fails to compile, since the macro routes property access
        // through observation-tracking accessors.
        self.persistence = persistence
        self.steps = resolvedSteps
        self.step = resolvedSteps.first ?? .done
        self.deferredSteps = deferred
        // A deferred step keeps setup INCOMPLETE, which is what re-raises the
        // gate at launch. Combined with the step filter above, the gate comes
        // back on that step alone rather than replaying the wizard.
        self.isComplete = doc.completedAt != nil
            && doc.setupVersion >= Self.currentSetupVersion
            && deferred.isEmpty
    }

    /// Records (or clears) a step as deferred-but-owed. Persisted by `complete()`.
    ///
    /// Clearing matters as much as setting: a user who returns through the
    /// banner and connects a provider must stop owing the step, or the gate
    /// would greet them again forever.
    func setDeferred(_ step: SetupStep, _ deferred: Bool) {
        if deferred { deferredSteps.insert(step) } else { deferredSteps.remove(step) }
    }

    var canAdvance: Bool { step != .done }

    /// False only on the first step shown. Drives the Back control's PRESENCE,
    /// not its enablement: a greyed button the user can never use is noise.
    ///
    /// Note what this is not gated on — the current step's own validation. Back
    /// is always available (except on the first step) whether or not the step's
    /// requirements are met. The Providers step is the reason that matters: it
    /// is mandatory, and a user who cannot get a connection to verify must be
    /// able to go back rather than being stuck on it.
    var canGoBack: Bool { (steps.firstIndex(of: step) ?? 0) > 0 }

    func advance() {
        guard let i = steps.firstIndex(of: step), i + 1 < steps.count else { return }
        step = steps[i + 1]
    }

    func back() {
        guard let i = steps.firstIndex(of: step), i > 0 else { return }
        step = steps[i - 1]
    }

    /// Writes the completion marker, including anything still owed.
    ///
    /// `isComplete` deliberately tracks the marker rather than being forced
    /// true: if a step was deferred, setup is *not* complete, and the next
    /// launch must say so.
    func complete() {
        persistence.save(SetupDocument(completedAt: Date(),
                                       setupVersion: Self.currentSetupVersion,
                                       deferredSteps: deferredSteps.map(\.rawValue).sorted()))
        isComplete = deferredSteps.isEmpty
    }
}
