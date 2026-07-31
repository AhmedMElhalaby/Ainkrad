import Foundation
import Testing
@testable import Ainkrad
import AinkradAppKit
import AinkradHostRuntime

@Suite("Setup home step")
@MainActor
struct SetupHomeStepTests {
    @Test func choosingAnEmptyFolderAdopts() {
        let url = URL(fileURLWithPath: "/tmp/vault-\(UUID().uuidString)")
        var adopted: URL?
        let model = SetupHomeStepModel(chooseVault: { url }, adopt: { adopted = $0 })
        #expect(model.choose() == .adopted)
        #expect(adopted == url)
    }

    @Test func cancellingLeavesTheStepUnfinished() {
        let model = SetupHomeStepModel(chooseVault: { nil }, adopt: { _ in
            Issue.record("adopt must not run when the user cancels")
        })
        #expect(model.choose() == .cancelled)
    }

    /// A populated folder must be refused with an explanation, not a crash and
    /// not a silent claim. This is the rule that exists because an interim
    /// default once claimed a live Obsidian vault.
    @Test func aPopulatedFolderIsRejectedWithAReason() {
        let url = URL(fileURLWithPath: "/tmp/populated")
        let model = SetupHomeStepModel(chooseVault: { url },
                                       adopt: { _ in throw HomeError.notEmpty(url) })
        guard case .rejected(let message) = model.choose() else {
            Issue.record("expected .rejected"); return
        }
        #expect(!message.isEmpty)
        #expect(message.lowercased().contains("empty"))
    }

    /// After the swap the coordinator is rebuilt against the ADOPTED home's
    /// store and walked to the step after `.home`.
    @Test func reseatingResumesAtTheStepAfterHome() {
        let store = InMemoryPersistenceStore()
        let fresh = SetupCoordinator(persistence: store, isProvisionalHome: false)
        #expect(SetupReseat.plan(fresh, toward: .appearance) == .resumed(.appearance))
        #expect(fresh.step == .appearance)
        #expect(!fresh.steps.contains(.home), "a configured Home must never be re-asked")
    }

    /// Reinstall-and-restore: the chosen folder is an existing Home whose setup
    /// was already completed. The fresh coordinator then has nothing left to
    /// walk (`steps == [.done]`), so the target is unreachable — that is a
    /// legitimate outcome, not a step transition that quietly did nothing.
    @Test func reseatingOntoAnAlreadyConfiguredHomeReportsItRatherThanStalling() {
        let store = InMemoryPersistenceStore()
        store.save(SetupDocument(completedAt: Date(),
                                 setupVersion: SetupCoordinator.currentSetupVersion))
        let fresh = SetupCoordinator(persistence: store, isProvisionalHome: false)
        #expect(fresh.isComplete)
        #expect(SetupReseat.plan(fresh, toward: .appearance) == .alreadyConfigured)
        // And emphatically NOT a silent .resumed(.done) the caller cannot tell
        // apart from a normal transition.
        #expect(SetupReseat.plan(fresh, toward: .appearance) != .resumed(.done))
    }

    /// The `setupVersion` re-gating mechanism, exercised for real.
    ///
    /// When `currentSetupVersion` is bumped, a user who adopts a vault carrying
    /// an OLDER completed marker owes only the newly added steps — so the
    /// outgoing coordinator's successor to `.home` is very likely NOT in the
    /// fresh list. Walking blindly toward an absent target runs the coordinator
    /// all the way to `.done`, landing the user on the closing screen having
    /// never been asked the step the bump exists for; Start then writes the new
    /// version's marker and the step is lost permanently.
    ///
    /// `.home` stands in for any unreachable target: the non-provisional step
    /// list excludes it unconditionally, so it can never be walked to.
    @Test func reseatingTowardAnUnreachableStepLandsOnTheFirstOwedStep() throws {
        let store = InMemoryPersistenceStore()
        let fresh = SetupCoordinator(persistence: store, isProvisionalHome: false)
        let first = try #require(fresh.steps.first)
        #expect(!fresh.steps.contains(.home), "the target must genuinely be unreachable")

        #expect(SetupReseat.plan(fresh, toward: .home) == .resumed(first))
        #expect(fresh.step == first)
        // The failure this pins: skipping every owed step to the closing screen.
        #expect(fresh.step != .done)
    }

    // MARK: - What the folder preview promises

    /// The listing is the explanation, so it must not drift from the layout the
    /// app actually writes. Every named folder has to be a real first component
    /// under the vault root.
    @Test func theFolderPreviewNamesRealVaultDirectories() {
        let root = URL(fileURLWithPath: "/tmp/preview-home", isDirectory: true)
        let home = Home(vaultRoot: root, cacheRoot: root)
        var real = Set(SharedDomain.allCases.compactMap { domain -> String? in
            home.shared(domain).pathComponents
                .dropFirst(root.pathComponents.count).first
        })
        // `Apps/` has no `SharedDomain`; it is `Home.vault(app:)`'s root.
        real.insert(home.vault(app: AppID("probe")).pathComponents
            .dropFirst(root.pathComponents.count).first ?? "")

        #expect(!SetupHomePreview.entries.isEmpty)
        for entry in SetupHomePreview.entries {
            let name = String(entry.name.dropLast())  // trailing "/"
            #expect(real.contains(name), "\(entry.name) is not a real vault directory")
            #expect(!entry.detail.isEmpty)
        }
    }

    /// **The gate on a new shared domain.**
    ///
    /// `SharedDomain` is non-frozen across the module boundary, so
    /// `SetupHomePreview.description(of:)` is forced to carry an
    /// `@unknown default` and cannot fail to compile when a case is added. This
    /// is therefore where a new domain gets caught: every domain's top-level
    /// folder must appear in the listing, so adding one that creates a new
    /// folder at the root of the vault fails here until someone decides what to
    /// tell the user about it. A domain that lives inside an existing folder
    /// (as `.memory` and friends do inside `Assistant/`) passes, correctly.
    @Test func everySharedDomainIsAccountedForInTheFolderPreview() {
        let root = URL(fileURLWithPath: "/tmp/preview-home", isDirectory: true)
        let home = Home(vaultRoot: root, cacheRoot: root)
        let listed = Set(SetupHomePreview.entries.map(\.name))

        for domain in SharedDomain.allCases {
            let folder = (home.shared(domain).pathComponents
                .dropFirst(root.pathComponents.count).first ?? "?") + "/"
            let complaint = "\(domain) creates \(folder) at the vault root, which the "
                + "Home step never tells the user about"
            #expect(listed.contains(folder), Comment(rawValue: complaint))
        }
    }

    /// The domains that live inside `Assistant/` fold into its one row rather
    /// than appearing as phantom top-level folders.
    @Test func theFolderPreviewFoldsAssistantSubdirectoriesIntoOneRow() {
        let names = SetupHomePreview.entries.map(\.name)
        #expect(Set(names).count == names.count, "no folder may be listed twice")
        #expect(names.contains("Assistant/"))
        for absent in ["memory/", "skills/", "commands/", "sessions/"] {
            #expect(!names.contains(absent), "\(absent) is inside Assistant/, not top level")
        }
    }

    // MARK: - The migration warning, derived BEFORE adoption

    /// Nothing to move, nothing said. The overwhelmingly common case: a fresh
    /// install has no legacy container at all.
    @Test func noWarningWhenThereIsNoLegacyContainer() {
        #expect(SetupHomeMigrationNotice.make(legacyContainer: nil,
                                              needsMigration: { _ in
            Issue.record("needsMigration must not be asked without a container")
            return true
        }) == nil)
    }

    /// **The distinction this task exists for.**
    ///
    /// The warning is derived from `VaultMigration.needsMigration(container:)`
    /// — a question answerable BEFORE the user chooses a folder — and not from
    /// `HomeAdoption.Result.migrated`, which does not exist until the migration
    /// has already run and the container has already been renamed.
    ///
    /// Driven through the REAL predicate against real directories, in both
    /// states, so this cannot pass against a stub that happens to agree:
    ///
    /// 1. A container holding legacy data, un-migrated → warned, in advance.
    /// 2. The SAME container after migration (the `Documents.migrated` rename
    ///    is the marker) → silent, even though a migration demonstrably did
    ///    happen. A warning built from a post-hoc "did we migrate" flag would
    ///    fire here, on a screen where the move is already in the past.
    @Test func theWarningIsDerivedFromNeedsMigrationNotFromAPostMigrationFlag() throws {
        let container = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("legacy-\(UUID().uuidString)", isDirectory: true)
        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        try Data("{}".utf8).write(to: documents.appendingPathComponent("settings.json"))

        // 1 — before: the real predicate says yes, and the notice exists.
        #expect(VaultMigration.needsMigration(container: container))
        let before = try #require(SetupHomeMigrationNotice.make(legacyContainer: container))
        #expect(before.legacyCopyPath.hasSuffix("Documents.migrated"))
        #expect(before.message.contains(before.legacyCopyPath),
                "the warning must say where the old copy will end up")
        #expect(before.message.contains("not deleted"))

        // 2 — after: the migration HAS run. A flag set by the migration would be
        // true here; `needsMigration` is false, and so is the notice.
        try FileManager.default.moveItem(
            at: documents,
            to: container.appendingPathComponent("Documents.migrated", isDirectory: true))
        #expect(!VaultMigration.needsMigration(container: container))
        #expect(SetupHomeMigrationNotice.make(legacyContainer: container) == nil)
    }

    /// And it asks about the container it was given, rather than reaching for
    /// the real Application Support tree — the seam the view relies on to stay
    /// honest, and the reason the test above can run at all.
    @Test func theWarningAsksAboutTheContainerItWasGiven() {
        let container = URL(fileURLWithPath: "/tmp/legacy-probe")
        var asked: [URL] = []
        _ = SetupHomeMigrationNotice.make(legacyContainer: container,
                                          needsMigration: { asked.append($0); return true })
        #expect(asked == [container])
    }

    /// One wizard, one notation. This screen says where the old copy WILL be
    /// and `SetupDoneStepView` says where it IS; a user comparing them must see
    /// the same string, not `/Users/you/Library/…` in one and `~/Library/…` in
    /// the other. The Done screen builds the tilde form literally, so this is
    /// pinned by asserting the abbreviation the notice applies.
    @Test func theWarningNamesTheLegacyCopyTheSameWayTheDoneScreenDoes() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let container = home
            .appendingPathComponent("Library/Application Support/com.ainkrad.test",
                                    isDirectory: true)
        let notice = try #require(
            SetupHomeMigrationNotice.make(legacyContainer: container,
                                          needsMigration: { _ in true }))
        #expect(notice.legacyCopyPath
            == "~/Library/Application Support/com.ainkrad.test/Documents.migrated")
        #expect(!notice.legacyCopyPath.hasPrefix("/Users"))

        // A path outside the home directory is left exactly as it is, rather
        // than mangled — which is what an injected temp container gets.
        #expect(SetupHomeMigrationNotice.abbreviatingHome("/tmp/elsewhere")
            == "/tmp/elsewhere")
        // And a directory whose name merely STARTS with the home path is not a
        // child of it.
        #expect(SetupHomeMigrationNotice.abbreviatingHome(home.path + "-sibling")
            == home.path + "-sibling")
    }

    // MARK: - Headline

    /// The rail label and the 30pt stage headline are different jobs. Welcome's
    /// label stays "Welcome"; its headline says what the product is.
    @Test func welcomeHeadlineSaysWhatAinkradIsWithoutChangingItsRailLabel() {
        #expect(SetupStep.welcome.title == "Welcome")
        #expect(SetupStep.welcome.headline != SetupStep.welcome.title)
        #expect(SetupStep.welcome.headline.contains("Ainkrad"))
        // Every other step's rail label still reads well large, so none of them
        // pays for a second string.
        for step in SetupStep.allCases where step != .welcome {
            #expect(step.headline == step.title)
        }
    }
}
