import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// View-model for `SkillsManagerView`. Owns the local-skill editor drafts and
/// the bind/unbind flow; kept separate from the view body so the
/// bind→`CommandRegistry` re-sync logic is unit-testable without SwiftUI.
///
/// `resyncCommands` is the seam that fixes the Task 12 gap: bootstrap only
/// registered the skill `/name` commands into `CommandRegistry` once, at
/// launch, so a bind/unbind made here — at runtime — would otherwise sit
/// invisibly in `SkillCommandStore` until the next relaunch. Every mutating
/// action below (bind, unbind, delete-a-bound-skill) calls it so `/name`
/// starts/stops resolving immediately.
@MainActor
@Observable
final class SkillsManagerViewModel {
    let registry: SkillRegistry
    let store: SkillCommandStore
    private let resyncCommands: () -> Void
    private let fileManager: FileManager

    /// In-progress edits for LOCAL skills' raw `SKILL.md` text, keyed by
    /// skill name. Populated lazily from disk on first access.
    private(set) var drafts: [String: String] = [:]
    /// Set when `bind(command:toSkill:)` rejects a name — surfaced by the
    /// view instead of silently no-op'ing (mirrors `SkillCommandStore.bind`'s
    /// guarded-but-silent contract; the manager is where the user finds out).
    private(set) var bindError: String?

    init(registry: SkillRegistry, store: SkillCommandStore, resyncCommands: @escaping () -> Void,
         fileManager: FileManager = .default) {
        self.registry = registry
        self.store = store
        self.resyncCommands = resyncCommands
        self.fileManager = fileManager
    }

    /// Count of pending `_proposed/` drafts — drives the manager-entry badge so a
    /// freshly proposed/improved skill is visible without opening the manager.
    var proposalCount: Int { registry.proposals().count }

    // MARK: - Active skills / local editor

    private func onDiskText(_ skill: Skill) -> String {
        (try? String(contentsOf: registry.paths.skillFile(skill.name), encoding: .utf8)) ?? ""
    }

    func draft(for skill: Skill) -> String {
        if let existing = drafts[skill.name] { return existing }
        let text = onDiskText(skill)
        drafts[skill.name] = text
        return text
    }

    func setDraft(_ text: String, for skill: Skill) { drafts[skill.name] = text }

    func hasUnsavedChanges(_ skill: Skill) -> Bool { draft(for: skill) != onDiskText(skill) }

    /// Overwrites the local skill's `SKILL.md` with the current draft. A
    /// no-op when unchanged, mirroring `MemoryUIViewModel.save`.
    func save(_ skill: Skill) {
        let text = draft(for: skill)
        guard text != onDiskText(skill) else { return }
        try? registry.writeLocal(text, name: skill.name)
        drafts[skill.name] = nil
    }

    /// Deletes an active skill's directory and reloads. Also re-syncs
    /// commands: a deleted skill may have had a `/name` bound to it, which
    /// should immediately read as a broken binding rather than stay wired to
    /// a stale in-memory closure until relaunch.
    func delete(_ skill: Skill) {
        try? fileManager.removeItem(at: registry.paths.skillDir(skill.name))
        drafts[skill.name] = nil
        registry.reload()
        resyncCommands()
    }

    // MARK: - Proposals

    func approve(_ proposal: SkillProposal) { try? registry.approve(name: proposal.name) }
    func discard(_ proposal: SkillProposal) { try? registry.discard(name: proposal.name) }

    // MARK: - Commands

    /// Binds `command` to `skillName` and re-syncs the live `CommandRegistry`.
    /// Rejects — with `bindError` set for the view to surface — exactly the
    /// names `SkillCommandStore.bind` itself would silently refuse (unsafe
    /// slug, or a builtin-shadowing name): checked here BEFORE calling
    /// `store.bind` so the rejection reason can be reported instead of the
    /// caller just observing nothing happened.
    @discardableResult
    func bind(command: String, toSkill skillName: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            bindError = "Enter a command name to bind."
            return false
        }
        guard SkillCommandStore.isValidCommandName(trimmed) else {
            bindError = "\"/\(trimmed)\" is invalid — command names must be a lowercase slug (letters, numbers, \"-\") and can't shadow a builtin like /new or /model."
            return false
        }
        store.bind(command: trimmed, toSkill: skillName)
        resyncCommands()
        bindError = nil
        return true
    }

    func unbind(_ command: String) {
        store.unbind(command: command)
        resyncCommands()
    }

    func clearBindError() { bindError = nil }
}

/// Cardinal-HUD Skills manager: active skills (with a local-skill editor +
/// delete), pending proposals (approve/discard), `/name` command bindings
/// (bind/unbind, broken-binding state), and load errors from malformed
/// `SKILL.md` files. Reads/writes exclusively through `SkillRegistry` /
/// `SkillCommandStore` — no direct file access outside the view-model.
@MainActor
struct SkillsManagerView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: SkillsManagerViewModel
    @State private var expandedSkill: String?
    @State private var newCommandName: String = ""
    @State private var newCommandSkill: String = ""

    init(registry: SkillRegistry, commands: SkillCommandStore, resyncCommands: @escaping () -> Void) {
        _viewModel = State(initialValue: SkillsManagerViewModel(
            registry: registry, store: commands, resyncCommands: resyncCommands))
    }

    var body: some View {
        let tokens = environment.themeManager.tokens

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSectionHeader(title: "ACTIVE SKILLS", tokens: tokens)
                activeSkillsSection(tokens: tokens)

                SettingsSectionHeader(title: "PROPOSED", tokens: tokens)
                proposedSection(tokens: tokens)

                SettingsSectionHeader(title: "COMMANDS", tokens: tokens)
                commandsSection(tokens: tokens)

                if !viewModel.registry.loadErrors.isEmpty {
                    SettingsSectionHeader(title: "LOAD ERRORS", tokens: tokens)
                    loadErrorsSection(tokens: tokens)
                }
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
        .onAppear(perform: syncDefaultCommandSkill)
        .onChange(of: viewModel.registry.skills) { _, _ in syncDefaultCommandSkill() }
    }

    private func syncDefaultCommandSkill() {
        if newCommandSkill.isEmpty || !viewModel.registry.skills.contains(where: { $0.name == newCommandSkill }) {
            newCommandSkill = viewModel.registry.skills.first?.name ?? ""
        }
    }

    // MARK: - Active skills

    @ViewBuilder
    private func activeSkillsSection(tokens: DesignTokens) -> some View {
        if viewModel.registry.skills.isEmpty {
            AinkradEmptyState(
                icon: "sparkles",
                title: "No active skills",
                message: "Approve a proposal below, or install one from the App Store, to see it here."
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.registry.skills) { skill in
                    activeSkillRow(skill, tokens: tokens)
                }
            }
        }
    }

    private func activeSkillRow(_ skill: Skill) -> some View { activeSkillRow(skill, tokens: environment.themeManager.tokens) }

    private func activeSkillRow(_ skill: Skill, tokens: DesignTokens) -> some View {
        let isExpanded = expandedSkill == skill.name

        return VStack(alignment: .leading, spacing: 8) {
            AinkradListRow(
                leading: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                        .foregroundStyle(tokens.accentSecondary.opacity(0.85))
                        .frame(width: 18)
                },
                title: skill.name,
                subtitle: skill.description,
                trailing: {
                    HStack(spacing: 8) {
                        AinkradBadge(text: skill.source.rawValue, tint: badgeTint(skill.source, tokens: tokens))
                        if skill.source == .local {
                            AinkradButton(title: isExpanded ? "Close" : "Edit", style: .secondary) {
                                expandedSkill = isExpanded ? nil : skill.name
                            }
                        }
                        AinkradButton(title: "Delete", style: .danger) {
                            if expandedSkill == skill.name { expandedSkill = nil }
                            viewModel.delete(skill)
                        }
                    }
                }
            )

            if !skill.triggers.isEmpty || !skill.allowedTools.isEmpty {
                HStack(spacing: 12) {
                    if !skill.triggers.isEmpty {
                        Text("Triggers: \(skill.triggers.joined(separator: ", "))")
                    }
                    if !skill.allowedTools.isEmpty {
                        Text("Tools: \(skill.allowedTools.joined(separator: ", "))")
                    }
                }
                .font(AinkradFont.mono(9))
                .foregroundStyle(tokens.foreground.opacity(0.45))
                .padding(.horizontal, AinkradSpacing.md)
            }

            if isExpanded, skill.source == .local {
                localSkillEditor(skill, tokens: tokens)
            }
        }
    }

    private func localSkillEditor(_ skill: Skill, tokens: DesignTokens) -> some View {
        let hasChanges = viewModel.hasUnsavedChanges(skill)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                if hasChanges {
                    Text("UNSAVED")
                        .font(AinkradFont.mono(8, weight: .medium))
                        .kerning(1.2)
                        .foregroundStyle(tokens.warning.opacity(0.9))
                }
                Spacer()
                AinkradButton(title: "Save", style: hasChanges ? .primary : .ghost) {
                    viewModel.save(skill)
                }
            }
            AinkradTextArea(
                text: Binding(
                    get: { viewModel.draft(for: skill) },
                    set: { viewModel.setDraft($0, for: skill) }
                ),
                placeholder: "SKILL.md source…",
                minHeight: 120
            )
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.4)))
    }

    private func badgeTint(_ source: SkillSource, tokens: DesignTokens) -> Color {
        switch source {
        case .marketplace: return tokens.accentPrimary
        case .local: return tokens.accentSecondary
        case .proposed: return tokens.warning
        }
    }

    // MARK: - Proposed

    @ViewBuilder
    private func proposedSection(tokens: DesignTokens) -> some View {
        let proposals = viewModel.registry.proposals()
        if proposals.isEmpty {
            AinkradEmptyState(
                icon: "tray",
                title: "No proposals pending",
                message: "Drafts the assistant proposes via `propose_skill` will show up here for review."
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(proposals) { proposal in
                    proposalRow(proposal, tokens: tokens)
                }
            }
        }
    }

    private func proposalRow(_ proposal: SkillProposal, tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AinkradListRow(
                leading: {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 13))
                        .foregroundStyle(tokens.warning.opacity(0.85))
                        .frame(width: 18)
                },
                title: proposal.name,
                subtitle: proposal.skill?.description ?? proposal.error ?? "Unreadable draft",
                trailing: {
                    HStack(spacing: 8) {
                        AinkradButton(title: "Approve", style: .primary) { viewModel.approve(proposal) }
                            .disabled(proposal.skill == nil)
                        AinkradButton(title: "Discard", style: .danger) { viewModel.discard(proposal) }
                    }
                }
            )

            if !proposal.issues.isEmpty {
                Text(proposal.issues.map(issueDescription).joined(separator: " · "))
                    .font(AinkradFont.mono(9))
                    .foregroundStyle(tokens.warning.opacity(0.85))
                    .padding(.horizontal, AinkradSpacing.md)
            }
        }
    }

    private func issueDescription(_ issue: SkillValidationIssue) -> String {
        switch issue {
        case .unsafeName(let name): return "unsafe name \"\(name)\""
        case .emptyBody: return "empty body"
        case .emptyDescription: return "empty description"
        }
    }

    // MARK: - Commands

    private func commandsSection(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let bindings = viewModel.store.all()
            if bindings.isEmpty {
                AinkradEmptyState(
                    icon: "slash.circle",
                    title: "No command bindings",
                    message: "Bind a skill to a `/name` below to run it as a slash command."
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(bindings) { binding in
                        commandRow(binding, tokens: tokens)
                    }
                }
            }

            newCommandRow(tokens: tokens)
        }
    }

    private func commandRow(_ binding: SkillCommandBinding, tokens: DesignTokens) -> some View {
        let isBroken = viewModel.registry.skill(named: binding.skillName) == nil

        return AinkradListRow(
            leading: {
                Image(systemName: isBroken ? "exclamationmark.triangle" : "slash.circle")
                    .font(.system(size: 13))
                    .foregroundStyle((isBroken ? tokens.danger : tokens.accentSecondary).opacity(0.85))
                    .frame(width: 18)
            },
            title: "/\(binding.command)",
            subtitle: isBroken ? "Bound skill \"\(binding.skillName)\" is missing" : "→ \(binding.skillName)",
            trailing: {
                AinkradButton(title: "Unbind", style: .danger) { viewModel.unbind(binding.command) }
            }
        )
    }

    private func newCommandRow(tokens: DesignTokens) -> some View {
        let skillNames = viewModel.registry.skills.map(\.name)

        return VStack(alignment: .leading, spacing: 8) {
            if skillNames.isEmpty {
                Text("Approve at least one skill to bind it to a command.")
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
            } else {
                HStack(spacing: 8) {
                    Text("/").font(AinkradFont.mono(13)).foregroundStyle(tokens.foreground.opacity(0.6))
                    AinkradTextField(text: $newCommandName, placeholder: "command-name")
                        .frame(width: 160)
                    Text("→").foregroundStyle(tokens.foreground.opacity(0.4))
                    AinkradSelect(items: skillNames, selection: $newCommandSkill, label: { $0 })
                        .frame(width: 180)
                    AinkradButton(title: "Bind", style: .primary) {
                        if viewModel.bind(command: newCommandName, toSkill: newCommandSkill) {
                            newCommandName = ""
                        }
                    }
                }
                if let bindError = viewModel.bindError {
                    Text(bindError)
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.danger.opacity(0.9))
                }
            }
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.4)))
    }

    // MARK: - Load errors

    private func loadErrorsSection(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(viewModel.registry.loadErrors, id: \.name) { err in
                Text("\(err.name): \(err.message)")
                    .font(AinkradFont.mono(10))
                    .foregroundStyle(tokens.danger.opacity(0.85))
            }
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.3)))
    }
}
