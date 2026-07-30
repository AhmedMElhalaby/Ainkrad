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

/// Applies the Assistant step. `AgentStore.setActive` is a no-op unless the id is
/// already in `agents`, so a custom profile must be added before it is activated.
@MainActor
enum SetupAssistant {
    static func apply(profile: AgentProfile, model: String, effort: String,
                      agents: AgentStore, config: AgentConfigStore) {
        let resolved: AgentProfile
        if profile.builtin {
            resolved = profile
        } else if agents.agents.contains(where: { $0.id == profile.id }) {
            // Back-then-Continue on the same custom persona: update the
            // existing entry in place rather than appending a duplicate.
            // `commit()` reuses the same `AgentProfile.id` across the step's
            // session, so this branch is what makes that reuse matter.
            agents.update(profile)
            resolved = profile
        } else {
            resolved = agents.add(profile)
        }
        agents.setActive(resolved.id)
        config.setModel(model)
        config.setEffort(effort)
    }

    /// The model to seed the step with: the active connection's first curated
    /// model, mirroring `AssistantModelPickerModel.selectConnection`
    /// (Sources/Ainkrad/Features/Assistant/AssistantModelPicker.swift
    /// ~lines 178-180) — the existing precedent for defaulting a model off a
    /// connection rather than a hardcoded Anthropic id. Falls back to
    /// `AgentConfigDocument`'s own default only when there is no connection
    /// to key off (a fresh install with nothing configured yet). Static
    /// `curatedModels` data — no live network call.
    static func defaultModel(connections: [Connection], activeConnectionID: UUID?) -> String {
        let connection = activeConnectionID.flatMap { id in connections.first { $0.id == id } }
            ?? connections.first
        guard let connection else { return AgentConfigDocument().model }
        return ProviderPreset.preset(id: connection.presetID).curatedModels.first
            ?? AgentConfigDocument().model
    }
}

/// The Assistant step: a confirmation, not an authoring task. Plan and Build —
/// the two built-in agents — are shown with their instructions so the user can
/// see what they do; Build is the default (matching `AgentStore.active`'s own
/// fallback). A custom persona is a secondary path via `AgentProfile.custom`,
/// added to the store only on Continue (never on every keystroke, unlike the
/// You step — an agent profile isn't a fact to accumulate, it's a choice to commit).
///
/// Model defaults to the active connection's curated model (see
/// `SetupAssistant.defaultModel`) rather than a live model-list call: in this
/// developer's judgment (informed by this task's dispatch context, not a
/// stated brief requirement) a network fetch here could hang the wizard on a
/// flaky connection, and curated data is static and instant. Effort defaults
/// to `AgentConfigDocument`'s own default (`"xhigh"`).
///
/// Model and effort persist immediately on change (plain scalars, no
/// partial-typing risk — same convention as the Appearance/You steps); only
/// the custom-persona commit stays gated on Continue, since a half-typed
/// name/instructions shouldn't become the active agent mid-edit.
struct SetupAssistantStepView: View {
    @Environment(AppEnvironment.self) private var environment

    let coordinator: SetupCoordinator

    private static let efforts = ["low", "medium", "high", "xhigh"]

    @State private var selection: AgentProfile = BuiltInAgents.build
    @State private var isCustom = false
    @State private var customName = ""
    @State private var customInstructions = ""
    @State private var model = AgentConfigDocument().model
    @State private var effort = AgentConfigDocument().effort
    /// The id of the custom persona this step session has already added to
    /// `agents`, if any — reused on subsequent commits so Back-then-Continue
    /// updates the existing entry instead of appending a duplicate.
    @State private var customProfileID: UUID?

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro(tokens: tokens)
                    builtins(tokens: tokens)
                    custom(tokens: tokens)
                    modelAndEffort(tokens: tokens)
                }
                .padding(20)
            }

            HStack {
                Spacer(minLength: 0)
                AinkradButton(title: "Continue", style: .primary) {
                    commit()
                    coordinator.advance()
                }
                .disabled(isCustom && (
                    customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
            .padding(20)
        }
        .onAppear {
            model = SetupAssistant.defaultModel(
                connections: environment.connectionStore.connections,
                activeConnectionID: environment.agentConfigStore.activeConnectionID)
            environment.agentConfigStore.setModel(model)
        }
        .onChange(of: effort) { _, newValue in
            environment.agentConfigStore.setEffort(newValue)
        }
    }

    /// Effort only means anything to `ClaudeProvider` (see
    /// `AgentSession.effortString`); Settings gates its own effort picker on
    /// `active?.kind == .claude` (AssistantSettingsView+Sections.swift
    /// ~line 91), so this step mirrors that rather than showing a control
    /// that silently does nothing for OpenAI/Ollama/Groq/etc.
    private var activeConnectionIsClaude: Bool {
        let connections = environment.connectionStore.connections
        let active = environment.agentConfigStore.activeConnectionID.flatMap { id in
            connections.first { $0.id == id }
        } ?? connections.first
        return active?.kind == .claude
    }

    private func intro(tokens: DesignTokens) -> some View {
        Text("Ainkrad ships with two agents, Plan and Build. Confirm which one starts "
             + "active — or write your own persona instead. You can add and edit more "
             + "agents later.")
            .font(AinkradFont.display(12))
            .foregroundStyle(tokens.foreground.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func builtins(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "STARTING AGENT", tokens: tokens)
            ForEach(BuiltInAgents.all) { agent in
                builtinRow(agent, tokens: tokens)
            }
        }
    }

    private func builtinRow(_ agent: AgentProfile, tokens: DesignTokens) -> some View {
        let isSelected = !isCustom && selection.id == agent.id
        return Button {
            isCustom = false
            selection = agent
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: agent.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? tokens.accentSecondary : tokens.foreground.opacity(0.6))
                VStack(alignment: .leading, spacing: 4) {
                    Text(agent.name)
                        .font(AinkradFont.display(13, weight: .medium))
                        .foregroundStyle(tokens.foreground.opacity(0.9))
                    Text(agent.instructions)
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.foreground.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(tokens.accentSecondary)
                }
            }
            .padding(12)
            .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.5)))
            .overlay(ChamferShape(cut: AinkradRadius.md)
                .strokeBorder(isSelected ? tokens.accentSecondary.opacity(0.5) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func custom(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                isCustom = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(isCustom ? tokens.accentSecondary : tokens.foreground.opacity(0.6))
                    Text("Write your own persona instead")
                        .font(AinkradFont.display(12, weight: .medium))
                        .foregroundStyle(tokens.foreground.opacity(0.85))
                    Spacer(minLength: 0)
                    if isCustom {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(tokens.accentSecondary)
                    }
                }
                .padding(12)
                .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.35)))
            }
            .buttonStyle(.plain)

            if isCustom {
                AinkradTextField(text: $customName, placeholder: "Name (e.g. Scribe)")
                AinkradTextField(text: $customInstructions, placeholder: "Instructions")
            }
        }
    }

    private func modelAndEffort(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "MODEL", tokens: tokens)
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model").font(AinkradFont.display(11)).foregroundStyle(tokens.foreground.opacity(0.5))
                    Text(model).font(AinkradFont.display(12, weight: .medium))
                        .foregroundStyle(tokens.foreground.opacity(0.9))
                }
                if activeConnectionIsClaude {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Effort").font(AinkradFont.display(11)).foregroundStyle(tokens.foreground.opacity(0.5))
                        AinkradSegmentedPicker(
                            items: Self.efforts,
                            selection: $effort,
                            label: { $0.capitalized })
                        .fixedSize()
                    }
                }
            }
        }
    }

    private func commit() {
        let profile: AgentProfile
        if isCustom {
            // Reuse the same id across Back-then-Continue within this step
            // session so `SetupAssistant.apply` updates the existing custom
            // persona instead of appending a duplicate.
            let id = customProfileID ?? UUID()
            customProfileID = id
            profile = AgentProfile(
                id: id,
                name: customName.trimmingCharacters(in: .whitespacesAndNewlines),
                instructions: customInstructions.trimmingCharacters(in: .whitespacesAndNewlines),
                toolPolicy: .all)
        } else {
            profile = selection
        }
        SetupAssistant.apply(profile: profile, model: model, effort: effort,
                             agents: environment.agentStore, config: environment.agentConfigStore)
    }
}
