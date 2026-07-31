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

    @Environment(\.ainkradReduceMotion) private var reduceMotion

    /// Asked BEFORE the user chooses, which is the entire point of this task:
    /// `VaultMigration.needsMigration(container:)` is answerable up front, so a
    /// user whose data is about to be moved and whose old container is about to
    /// be renamed is told first rather than on the closing screen after the
    /// fact. Never derived from `HomeAdoption.Result.migrated` — that value
    /// does not exist until the migration has already run.
    ///
    /// Computed once in `onAppear` rather than per body evaluation: it hits the
    /// file system, and the answer cannot change while this screen is up (the
    /// only thing that changes it is an adoption, which ends this screen).
    @State private var migrationNotice: SetupHomeMigrationNotice?

    /// Flipped once, by the first preview row to appear, to stage the folder
    /// listing in. Never reset — Back to this step re-mounts the view.
    @State private var hasSettled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .onAppear { migrationNotice = SetupHomeMigrationNotice.make() }
            // Back here returns to Welcome, and is safe precisely because
            // nothing has been adopted yet — this step is only ever reached on
            // a provisional home. The instant adoption succeeds the coordinator
            // is rebuilt without `.home` at all, so Back can never return to it.
            //
            // No `SetupRequirementNote` here, unlike the other gated steps, and
            // the primary is never disabled: this step's requirement IS its
            // primary button. "Choose a folder to continue" printed above a
            // button reading "Choose Folder…" would be noise, not an
            // explanation. The rule still lives in `SetupValidation` so
            // `canAdvance(from: .home,)` tells a programmatic caller the truth.
            SetupStepFooter(coordinator: coordinator,
                            primaryTitle: "Choose Folder…",
                            primaryIdentifier: "setup.home.choose") { choose() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// The folder is the idea, so the folder is what is drawn: a listing of
    /// what will exist inside whatever the user picks. Someone looking at this
    /// is choosing a place for their work to live, not filling in a path.
    private var content: some View {
        let tokens = environment.themeManager.tokens

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Pick an empty folder, or make a new one anywhere you like — "
                     + "your Documents, an external drive, a synced folder. Ainkrad "
                     + "will never take over a folder that already has files in it.")
                    .font(AinkradFont.display(14))
                    .foregroundStyle(tokens.foreground.opacity(0.78))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 560, alignment: .leading)

                folderPreview(tokens: tokens)

                if let migrationNotice {
                    notice(title: migrationNotice.title,
                           message: migrationNotice.message,
                           icon: "arrow.right.doc.on.clipboard",
                           tint: tokens.accentSecondary,
                           tokens: tokens)
                        .accessibilityIdentifier("setup.home.migrationWarning")
                }

                // The one failure state on this screen, and deliberately the
                // plainest thing on it: a refusal has to be READ, so it gets a
                // tint and an icon and nothing else.
                //
                // It has NO scroller and no height clamp of its own. It used to
                // have both, which was correct when this step's content did not
                // scroll — now that it does, an inner vertical scroller inside
                // an outer vertical scroller is a gesture and sizing hazard, and
                // a long `HomeError.notEmpty` message is exactly the case the
                // brief says must stay readable. One scroller on this axis: the
                // rejection lays out at its full height and the step's own
                // scroller carries it.
                if let rejection {
                    notice(title: "That folder can't be used",
                           message: rejection,
                           icon: "exclamationmark.circle",
                           tint: tokens.accentTertiary,
                           tokens: tokens)
                        .accessibilityIdentifier("setup.home.rejection")
                }
            }
            .padding(.bottom, 4)
        }
    }

    /// A live folder listing. No separator lines between the rows — one
    /// seamless recessed surface, per the design language — and each row
    /// arrives a beat after the one above it so the list assembles rather than
    /// appearing as a block. Flat under reduce-motion.
    private func folderPreview(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.accentPrimary)
                Text("Inside it")
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(SetupHomePreview.entries.enumerated()), id: \.element.id) {
                    index, entry in
                    entryRow(entry, index: index, tokens: tokens)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: AinkradRadius.md)
            .fill(tokens.surfaceElevated.opacity(0.35)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What Ainkrad will create in the folder you choose")
    }

    private func entryRow(_ entry: SetupHomePreview.Entry, index: Int,
                          tokens: DesignTokens) -> some View {
        let geometry = SetupStageMotion.layerGeometry(.content,
                                                      reduceMotion: reduceMotion,
                                                      isForward: true)
        // The stage's own `.content` travel, scaled down — these are rows
        // settling inside a panel, not the panel arriving. Scaled rather than
        // hardcoded so the rows still track `SetupStageMotion`'s vocabulary if
        // that geometry is ever retuned.
        //
        // `isForward: true` above is not a direction claim: the stage already
        // owns directional entry for the step as a whole, and this is a settle
        // that runs once on appear. It is asked in the forward orientation
        // purely to take the magnitude and the reduce-motion gate.
        let travel = geometry.map { $0.travel * 0.22 } ?? 0
        // Per-index stagger ONLY. `SetupStageMotion.animation(layer: .content)`
        // already carries that layer's 0.11s delay; adding `geometry.delay` to
        // it — as this line originally did — counted the same delay twice and
        // held the first row off screen for 0.22s before the list began
        // assembling. `geometry` is still what is consulted, because `nil` is
        // the reduce-motion seam.
        let delay = geometry.map { _ in Double(index) * 0.05 } ?? 0

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.icon)
                .font(.system(size: 12))
                .foregroundStyle(tokens.accentSecondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(AinkradFont.mono(12))
                    .foregroundStyle(tokens.foreground.opacity(0.9))
                Text(entry.detail)
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(hasSettled ? 1 : 0)
        .offset(x: hasSettled ? 0 : travel)
        // Through `SetupStageMotion`, never a bare `.animation` — reduce-motion
        // makes this `nil` and the rows are simply present.
        .animation(SetupStageMotion.animation(reduceMotion: reduceMotion,
                                              layer: .content)?.delay(delay),
                   value: hasSettled)
        .onAppear {
            guard !hasSettled else { return }
            hasSettled = true
        }
    }

    /// One shape for both the migration warning and the rejection, differing
    /// only in tint. They are the same kind of thing — something the user has to
    /// read before choosing — and giving them two different treatments would
    /// make the rarer one look like a decoration.
    ///
    /// Neither variant scrolls. The step owns the only scroller on this axis —
    /// see the rejection's call site.
    private func notice(title: String, message: String, icon: String,
                        tint: Color, tokens: DesignTokens) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(tint)
                Text(message)
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(0.72))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tint.opacity(0.09)))
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
