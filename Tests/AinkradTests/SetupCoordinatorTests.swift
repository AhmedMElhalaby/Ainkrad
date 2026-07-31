import Foundation
import Testing
@testable import Ainkrad
import AinkradHostRuntime

@Suite("Setup coordinator")
@MainActor
struct SetupCoordinatorTests {
    @Test func afreshInstallOwesEveryStep() {
        let store = InMemoryPersistenceStore()
        let c = SetupCoordinator(persistence: store, isProvisionalHome: true)
        #expect(c.steps == SetupStep.allCases)
        #expect(c.step == .welcome)
        #expect(!c.isComplete)
    }

    @Test func advancingWalksTheStepsInOrderAndStops() {
        let store = InMemoryPersistenceStore()
        let c = SetupCoordinator(persistence: store, isProvisionalHome: true)
        for _ in 0..<20 { c.advance() }
        #expect(c.step == .done, "advance past the end must clamp, not wrap or crash")
    }

    @Test func completingWritesTheMarkerWithTheCurrentVersion() {
        let store = InMemoryPersistenceStore()
        let c = SetupCoordinator(persistence: store, isProvisionalHome: true)
        c.complete()
        let doc = store.load(SetupDocument.self)
        #expect(doc?.completedAt != nil)
        #expect(doc?.setupVersion == SetupCoordinator.currentSetupVersion)
        #expect(c.isComplete)
    }

    /// A user who completed an older setup owes only the steps added since —
    /// not the whole wizard again.
    @Test func anOlderCompletionOwesOnlyTheNewSteps() {
        let store = InMemoryPersistenceStore()
        store.save(SetupDocument(completedAt: Date(timeIntervalSince1970: 0), setupVersion: 0))
        let c = SetupCoordinator(persistence: store, isProvisionalHome: false)
        #expect(c.steps.allSatisfy { $0.introducedIn > 0 || $0 == .done })
        #expect(!c.steps.contains(.home), "a configured user must not be asked for a vault again")
    }

    @Test func aCurrentCompletionOwesNothing() {
        let store = InMemoryPersistenceStore()
        store.save(SetupDocument(completedAt: Date(),
                                 setupVersion: SetupCoordinator.currentSetupVersion))
        let c = SetupCoordinator(persistence: store, isProvisionalHome: false)
        #expect(c.isComplete)
    }

    @Test func backNeverReachesTheHomeStep() {
        let store = InMemoryPersistenceStore()
        let c = SetupCoordinator(persistence: store, isProvisionalHome: false)
        for _ in 0..<20 { c.advance() }
        for _ in 0..<20 { c.back() }
        #expect(c.step != .home, "the vault is already adopted; Back must never offer to re-choose it")
        #expect(c.step == c.steps.first)
    }

    /// Back is offered on every step but the first shown — and on the first it
    /// is absent, not disabled, which is what `canGoBack` drives in the views.
    @Test func backIsUnavailableOnlyOnTheFirstStep() {
        let store = InMemoryPersistenceStore()
        let c = SetupCoordinator(persistence: store, isProvisionalHome: true)
        #expect(c.step == .welcome)
        #expect(!c.canGoBack)
        for _ in 0..<20 {
            c.advance()
            #expect(c.canGoBack, "every step after the first must offer Back")
        }
        #expect(c.step == .done)
    }

    /// A provisional (never-adopted) home is the one case where `.home` is in
    /// `steps` at all — and even there Back may only reach it because nothing
    /// has been adopted yet. Once adoption happens the coordinator is rebuilt
    /// with `isProvisionalHome: false` (see `SetupOverlayView.reseat`), and
    /// that rebuilt list is what `backNeverReachesTheHomeStep` pins.
    @Test func theAdoptedCoordinatorHasNoHomeStepAtAll() {
        let store = InMemoryPersistenceStore()
        let c = SetupCoordinator(persistence: store, isProvisionalHome: false)
        #expect(!c.steps.contains(.home))
    }
}
