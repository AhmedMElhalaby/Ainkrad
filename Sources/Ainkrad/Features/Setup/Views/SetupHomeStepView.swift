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
    ///
    /// The `Bool` is `HomeAdoption.Result.migrated`: adoption may have moved an
    /// existing legacy container into the vault and renamed the original, and
    /// this step advances the instant it succeeds, so it has no surface of its
    /// own to say so. The overlay carries it to the closing step.
    let onAdopted: (AppEnvironment, Bool) -> Void

    @State private var rejection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            // Back here returns to Welcome, and is safe precisely because
            // nothing has been adopted yet — this step is only ever reached on
            // a provisional home. The instant adoption succeeds the coordinator
            // is rebuilt without `.home` at all, so Back can never return to it.
            SetupStepFooter(coordinator: coordinator,
                            primaryTitle: "Choose Folder…") { choose() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var content: some View {
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
        }
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
        // Logged, not silent: returning is correct, but this step's ONLY button
        // then does nothing at all, with no rejection text and no alert — a
        // wizard that appears frozen on its one irreversible screen. Anyone who
        // hits it in a preview or a hand-built tree needs to be told why.
        guard let installer else {
            Log.persistence.error(
                "Setup Home step has no SetupHomeInstaller; adoption is unavailable in this view tree")
            return
        }

        var rebuilt: AppEnvironment?
        var migrated = false
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
                // Carried, not just logged. This step advances the moment it
                // succeeds so it has no surface of its own left to render on,
                // but a user whose container was moved and whose old copy was
                // renamed `Documents.migrated` must be told somewhere — and
                // `.done` is that somewhere. Dropping it here is how the rename
                // became a thing users would only ever discover in Finder.
                migrated = result.migrated
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
            if let rebuilt { onAdopted(rebuilt, migrated) }
        case .rejected(let message):
            rejection = message
        case .cancelled:
            break
        }
    }
}
