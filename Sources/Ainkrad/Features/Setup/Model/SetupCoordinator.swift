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

    init(persistence: PersistenceStore, isProvisionalHome: Bool) {
        let doc = persistence.load(SetupDocument.self) ?? SetupDocument()
        let completedVersion = doc.completedAt == nil ? -1 : doc.setupVersion

        let resolvedSteps: [SetupStep]
        if isProvisionalHome {
            // No vault chosen yet: the full wizard, always.
            resolvedSteps = SetupStep.allCases
        } else {
            // Only steps introduced since the version the user completed, plus the
            // closing screen. `.home` is never re-asked — a configured vault stands.
            resolvedSteps = SetupStep.allCases.filter {
                $0 == .done || ($0 != .home && $0.introducedIn > completedVersion)
            }
        }

        // Assigned only after every local is resolved: with `@Observable`,
        // reading `self.steps` mid-init (before every stored property has a
        // value) fails to compile, since the macro routes property access
        // through observation-tracking accessors.
        self.persistence = persistence
        self.steps = resolvedSteps
        self.step = resolvedSteps.first ?? .done
        self.isComplete = doc.completedAt != nil && doc.setupVersion >= Self.currentSetupVersion
    }

    var canAdvance: Bool { step != .done }

    func advance() {
        guard let i = steps.firstIndex(of: step), i + 1 < steps.count else { return }
        step = steps[i + 1]
    }

    func back() {
        guard let i = steps.firstIndex(of: step), i > 0 else { return }
        step = steps[i - 1]
    }

    func complete() {
        persistence.save(SetupDocument(completedAt: Date(),
                                       setupVersion: Self.currentSetupVersion))
        isComplete = true
    }
}
