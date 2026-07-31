import Foundation
import AinkradAppKit

/// What the Home step shows the user is about to be created inside the folder
/// they pick.
///
/// The point of the screen is that the folder IS the idea: a user who is shown
/// a path field and a button is choosing a string, while a user who is shown
/// the shape of what will appear inside the folder is choosing a place for
/// their work to live. So this is not decoration — it is the explanation.
///
/// Every entry is anchored to a real `SharedDomain` rather than typed out, so
/// the screen cannot drift away from the layout the app actually writes. A new
/// shared domain fails to compile here until someone decides whether the user
/// should be told about it, which is the correct place for that decision.
struct SetupHomePreview {
    struct Entry: Identifiable, Equatable {
        /// The directory name as it will appear in Finder, with its trailing
        /// slash — this is a folder listing, not a menu of features.
        let name: String
        /// One line, in the user's terms, of what goes in it.
        let detail: String
        let icon: String

        var id: String { name }
    }

    /// The top-level entries, in the order they read best — not alphabetical
    /// order, which would open on `Apps/`, the least meaningful of them.
    static let entries: [Entry] = [
        Entry(name: folderName(for: .agents),
              detail: "Your assistant: its agents, its memory, your skills and "
                  + "commands, and every conversation it has had.",
              icon: "bubble.left.and.text.bubble.right"),
        Entry(name: folderName(for: .config),
              detail: "Your settings, as plain JSON you can read.",
              icon: "slider.horizontal.3"),
        Entry(name: "Apps/",
              detail: "Whatever the apps you install make — one folder each.",
              icon: "square.grid.2x2"),
        Entry(name: folderName(for: .media),
              detail: "Images and files you bring into a conversation.",
              icon: "photo"),
        Entry(name: folderName(for: .sounds),
              detail: "The sounds Ainkrad plays, and any you add.",
              icon: "speaker.wave.2"),
    ]

    /// The first path component of a domain's location under the vault root, as
    /// a folder name. `.memory` and friends live INSIDE `Assistant/`, so the top
    /// level of this listing is the set of first components, not the set of
    /// domains.
    ///
    /// Asked of a `Home` rooted at a probe path rather than read off
    /// `SharedDomain.relativePath`, which is internal to `AinkradAppKitHome`.
    /// `shared(_:)` is the public accessor and is the same expression the app
    /// uses to build the real directories, so this stays honest either way.
    private static func folderName(for domain: SharedDomain) -> String {
        let root = URL(fileURLWithPath: "/__ainkrad-home-probe", isDirectory: true)
        let probe = Home(vaultRoot: root, cacheRoot: root)
        let components = probe.shared(domain).pathComponents
            .dropFirst(root.pathComponents.count)
        return (components.first ?? "?") + "/"
    }
}

/// The warning shown on the Home step when adopting will move an existing
/// legacy container.
///
/// Derived from `VaultMigration.needsMigration(container:)`, asked BEFORE the
/// user chooses — deliberately the same predicate `LaunchHomeResolver.adopt`
/// gates the real migration on, so the warning cannot promise a move that will
/// not happen or stay silent about one that will.
///
/// This is not the same value as `HomeAdoption.Result.migrated`, and must never
/// be rebuilt from it. That flag is sampled during adoption and only exists
/// afterwards; a warning derived from it could only ever be shown once the
/// rename had already happened, which is exactly the bug this replaces. The
/// closing step keeps using it, because there the migration genuinely is in the
/// past tense.
struct SetupHomeMigrationNotice: Equatable {
    /// Where the untouched original will still be afterwards, written the way a
    /// user could paste it into Finder's Go-to-Folder.
    let legacyCopyPath: String

    /// `nil` when there is nothing to move — the overwhelmingly common case,
    /// and the reason this screen does not mention migration at all by default.
    ///
    /// Both dependencies are injected so a test can drive the decision without
    /// touching the real Application Support container; the defaults are the
    /// real ones, so the view supplies nothing.
    static func make(
        legacyContainer: URL? = VaultMigration.legacyContainerURL(),
        needsMigration: (URL) -> Bool = { VaultMigration.needsMigration(container: $0) }
    ) -> SetupHomeMigrationNotice? {
        guard let legacyContainer, needsMigration(legacyContainer) else { return nil }
        return SetupHomeMigrationNotice(
            legacyCopyPath: legacyContainer
                .appendingPathComponent("Documents.migrated", isDirectory: true)
                .path)
    }

    var title: String { "Your existing data will be moved in" }

    var message: String {
        "Ainkrad found data from an earlier version on this Mac — your agents, "
            + "settings, skills and past conversations. When you choose a folder, "
            + "all of it is copied in first, so you carry on where you left off.\n\n"
            + "The original is not deleted. It stays where it is and is renamed to "
            + "\(legacyCopyPath), so you can check everything came across before "
            + "you remove it."
    }
}
