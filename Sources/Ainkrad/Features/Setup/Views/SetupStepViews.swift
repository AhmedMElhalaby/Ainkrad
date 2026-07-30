import SwiftUI
import AppKit
import AinkradAppKit
import AinkradHostRuntime

/// Pure decision logic for the Home step, independent of SwiftUI and of NSOpenPanel,
/// so it can be tested without a UI. The view supplies the real chooser and adopter.
@MainActor
final class SetupHomeStepModel {
    enum Outcome: Equatable {
        case adopted
        case rejected(String)
        case cancelled
    }

    private let chooseVault: LaunchHomeResolver.VaultChooser
    private let adopt: (URL) throws -> Void

    init(chooseVault: @escaping LaunchHomeResolver.VaultChooser,
         adopt: @escaping (URL) throws -> Void) {
        self.chooseVault = chooseVault
        self.adopt = adopt
    }

    func choose() -> Outcome {
        guard let chosen = chooseVault() else { return .cancelled }
        do {
            try adopt(chosen)
            return .adopted
        } catch {
            // Reuse the recovery copy so the wizard and the launch-time alerts
            // explain the same failures the same way.
            let message = LaunchRecovery.prompt(for: error)?.message
                ?? "That folder can't be used as your Ainkrad Home."
            return .rejected(message)
        }
    }
}

/// The Home step: the one irreversible screen in the wizard.
///
/// Choosing adopts the folder, migrates any legacy container into it, rebuilds the
/// environment against it and re-points every holder through
/// `AinkradHostApp.install(_:into:)` — reached here only via the injected
/// `SetupHomeInstaller`, never by re-pointing anything at this call site.
///
/// A refusal (a populated folder, a nested Home, an unwritable one) is rendered
/// INLINE rather than in a modal alert: the user is already inside a modal gate,
/// and stacking a second modal over it is how the launch-time alerts became
/// unverifiable. Nothing is written on a refusal — `adoptAndRebuild` throws
/// before `install` runs — so the step simply stays where it is.
struct SetupHomeStepView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.setupHomeInstaller) private var installer

    let coordinator: SetupCoordinator
    /// Handed the REBUILT environment so the overlay can re-seat anything it owns
    /// that still points at the provisional home (notably the coordinator's
    /// `PersistenceStore`, which would otherwise write setup state into a
    /// temporary directory the OS deletes).
    let onAdopted: (AppEnvironment) -> Void

    @State private var rejection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            Text("Ainkrad keeps everything you make — workspaces, notes, skills, "
                 + "agent history — in one folder you own, called your Home.")
                .font(AinkradFont.display(14))
                .fixedSize(horizontal: false, vertical: true)

            Text("Choose an empty folder, or create a new one. Ainkrad will not take "
                 + "over a folder that already has files in it.")
                .font(AinkradFont.display(13))
                .opacity(0.72)
                .fixedSize(horizontal: false, vertical: true)

            if let rejection {
                ScrollView {
                    Text(rejection)
                        .font(AinkradFont.display(12))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .accessibilityIdentifier("setup.home.rejection")
            }

            Spacer(minLength: 0)

            HStack {
                Spacer(minLength: 0)
                AinkradButton(title: "Choose Folder…", style: .primary) { choose() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private func choose() {
        // Bail BEFORE adopting, not at the re-point. `adoptAndRebuild` writes the
        // marker, migrates the real legacy container and writes the POINTER
        // before `install` is ever called, so an optional-chained
        // `installer?.install` would let all of that happen and skip only the
        // re-point — leaving the app running on the provisional home while a real
        // vault on disk had been claimed and the legacy tree renamed. Nothing at
        // all is the only safe answer when there is nobody to hand the rebuilt
        // environment to (previews, and any test that builds this view without an
        // installer).
        guard let installer else { return }

        var rebuilt: AppEnvironment?
        let model = SetupHomeStepModel(
            chooseVault: LaunchHomeResolver.presentFolderChooser,
            adopt: { url in
                let result = try HomeAdoption.adoptAndRebuild(chosen: url) { newEnvironment in
                    // The gate must stay up across the swap: `bootstrap` defaults
                    // this to false, and a rebuilt environment that forgets it
                    // would drop the user into the workspace mid-wizard.
                    newEnvironment.isSetupPresented = true
                    // The real vault is claimed, so the provisional restrictions
                    // (above all the throwaway Keychain namespace) are lifted.
                    newEnvironment.isProvisionalHome = false
                    rebuilt = newEnvironment
                    installer.install(newEnvironment)
                }
                // Recorded, not rendered: this step advances the moment it
                // succeeds, so there is no surface left to show it on. The
                // closing step is where a "we moved your existing data" line
                // belongs — see the Task 4 report's proposals.
                if result.migrated {
                    Log.persistence.info("Setup migrated the legacy container into the adopted Home")
                }
            })

        switch model.choose() {
        case .adopted:
            rejection = nil
            // `install` always runs on a successful adoption, so `rebuilt` is
            // always set here. Advancing the OUTGOING coordinator would move the
            // wizard on while still bound to the provisional store, so there is
            // deliberately no fallback.
            if let rebuilt { onAdopted(rebuilt) }
        case .rejected(let message):
            rejection = message
        case .cancelled:
            break
        }
    }
}
