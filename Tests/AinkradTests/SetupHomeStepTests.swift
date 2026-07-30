import Foundation
import Testing
@testable import Ainkrad
import AinkradAppKit

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
}
