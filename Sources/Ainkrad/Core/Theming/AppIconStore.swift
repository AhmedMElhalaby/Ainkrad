import Observation

/// Owns the user's manual app-icon choice: loads it from `GlobalSettings`,
/// persists changes (preserving other settings), and drives the applier.
@MainActor
@Observable
final class AppIconStore {
    private(set) var choice: AppIconChoice
    private let persistence: PersistenceStore
    private let applier: AppIconApplying

    init(persistence: PersistenceStore, applier: AppIconApplying) {
        self.persistence = persistence
        self.applier = applier
        self.choice = persistence.load(GlobalSettings.self)?.appIconChoice ?? .blue
    }

    /// Apply the current choice to the running app (e.g. at launch).
    func applyCurrent() { applier.apply(choice) }

    /// Persist + apply a new choice.
    func select(_ choice: AppIconChoice) {
        self.choice = choice
        var settings = persistence.load(GlobalSettings.self) ?? GlobalSettings()
        settings.appIconChoice = choice
        persistence.save(settings)
        applier.apply(choice)
    }
}
