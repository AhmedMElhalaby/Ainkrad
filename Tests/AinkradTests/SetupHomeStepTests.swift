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
}
