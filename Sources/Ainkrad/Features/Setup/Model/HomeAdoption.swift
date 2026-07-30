import Foundation
import AinkradAppKit

/// Adopts the user's chosen vault mid-session and rebuilds the environment against it.
///
/// The app boots against a scratch Home so the workspace can render behind the
/// setup overlay, which means the storage root changes exactly once, during
/// setup, before anything the user authors has been written. `install` is where
/// the caller re-points every holder of a store reference — anything missed
/// keeps writing to the scratch home, silently.
///
/// Ordering is deliberate and load-bearing: `LaunchHomeResolver.adopt` performs
/// validate → marker → migrate → adopt (pointer) → markMigrated, and it is
/// called BEFORE `bootstrap`. A failure anywhere in that sequence therefore
/// throws with `install` never having run, so a caller can never be handed —
/// and never re-points its holders at — a half-built environment rooted at a
/// vault the app does not actually own.
enum HomeAdoption {
    struct Result: Equatable {
        let home: Home
        /// True when a legacy container was found and migrated into `home` as
        /// part of this adoption — the wizard surfaces this to the user.
        let migrated: Bool
    }

    /// `@MainActor` because `AppEnvironment` (and every store it builds) is
    /// main-actor-isolated, and because `install` re-points UI-owned holders.
    @MainActor
    static func adoptAndRebuild(
        chosen: URL,
        pointerDirectory: URL = AinkradHome.defaultPointerDirectory(),
        cacheRoot: URL = AinkradHome.defaultCacheRoot(
            bundleID: Bundle.main.bundleIdentifier ?? "com.ainkrad.app"),
        legacyContainer: URL? = VaultMigration.legacyContainerURL(),
        defaults: UserDefaults = .standard,
        install: (AppEnvironment) -> Void
    ) throws -> Result {
        // Asked BEFORE `adopt`, because `adopt` ends by marking the legacy tree
        // as migrated — after which `needsMigration` answers false and the
        // answer to "did we just migrate?" would be lost.
        let needed = legacyContainer.map { VaultMigration.needsMigration(container: $0) } ?? false

        // Throws before anything is installed: validation, marker, migration and
        // the pointer write all happen inside adopt.
        let home = try LaunchHomeResolver.adopt(
            chosen,
            pointerDirectory: pointerDirectory,
            cacheRoot: cacheRoot,
            legacyContainer: legacyContainer)

        let environment = AppEnvironment.bootstrap(home: home, defaults: defaults)
        install(environment)
        return Result(home: home, migrated: needed)
    }
}
