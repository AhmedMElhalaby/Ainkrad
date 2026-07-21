import SwiftUI
import AinkradAppKit

/// Segmented-picker-friendly stand-in for `NetworkPolicy`'s associated-value
/// case (`AinkradSegmentedPicker` needs a plain `Hashable` selection). The
/// allow-list hosts themselves are edited separately, only when `.allowList`
/// is selected.
enum NetworkMode: String, CaseIterable, Hashable, Sendable {
    case off, allowList, on

    var title: String {
        switch self {
        case .off: return "Off"
        case .allowList: return "Allow-list"
        case .on: return "On"
        }
    }
}

/// `NetworkPolicy` <-> `NetworkMode` conversions. Pure, unit-testable without
/// a view — the allow-list hosts are carried separately so switching modes
/// back and forth never silently drops a previously-typed host list.
enum NetworkModeMapping {
    static func mode(for policy: NetworkPolicy) -> NetworkMode {
        switch policy {
        case .off: return .off
        case .on: return .on
        case .allowList: return .allowList
        }
    }

    static func policy(for mode: NetworkMode, hosts: [String]) -> NetworkPolicy {
        switch mode {
        case .off: return .off
        case .on: return .on
        case .allowList: return .allowList(hosts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        }
    }
}

/// Drives the "why was this blocked/allowed" inspector: picks a sample tool's
/// permission class (mirroring the real `AgentTool.permission` values) and
/// runs the SAME two-step pipeline the runtime uses (`AgentPermissionPolicy`
/// gate, then `SandboxPermissionPolicy.compose`) so the explanation shown
/// here can never drift from what the tool call would actually do. Pure, no
/// I/O — unit-testable without a view or a store.
enum SandboxPolicyExplainer {
    /// Illustrative subset of real tool names (`AgentTool.name` values) — not
    /// an exhaustive registry lookup, since this pane is a fail-closed
    /// explainer, not a live tool catalog.
    static let sampleToolNames = ["read_file", "edit_file", "run_terminal", "git_op", "workspace_control"]

    static func permissionClass(for toolName: String) -> ToolPermissionClass {
        toolName == "read_file" ? .read : .write
    }

    static func explain(
        profile: SandboxProfile,
        toolName: String,
        mode: AgentPermissionMode,
        allowlist: Set<String>,
        gateReads: Bool
    ) -> PermissionExplanation {
        let gate = AgentPermissionPolicy.decide(
            toolPermission: permissionClass(for: toolName),
            toolName: toolName,
            mode: mode,
            allowlist: allowlist,
            gateReads: gateReads,
            isIrreversible: false)
        return SandboxPermissionPolicy.compose(
            gate: gate,
            agentAllowList: nil,   // this inspector explains the SANDBOX layer; no per-Agent restriction assumed
            sandboxAllowList: profile.toolAllowList,
            toolName: toolName)
    }
}

/// Settings pane: view/edit `SandboxProfile`s. Built-ins are read-only badges
/// (backend + fs/network/resource summary); user-defined profiles are
/// editable/deletable. `allowHostOverride` is surfaced as an explicit,
/// off-by-default, danger-styled toggle — never bundled into a generic
/// "advanced" switch — so a user can't accidentally grant a non-main trust
/// tier a path to `.host` execution. Zero native SwiftUI controls: every
/// input is an AinkradAppKit component.
@MainActor
struct SandboxPolicyUIView: View {
    let store: SandboxProfileStore

    @Environment(AppEnvironment.self) private var environment
    @State private var selectedID: String = BuiltInSandboxProfiles.defaultNonMainID
    @State private var draft: SandboxProfile?
    @State private var hostsText: String = ""
    @State private var pendingDeleteID: String?
    @State private var explainToolName: String = SandboxPolicyExplainer.sampleToolNames[0]
    /// Local draft of each provider's token — mirrors
    /// `CloudCredentialsStore.credential(for:)` at `onAppear`; each edit
    /// writes straight through to the Keychain-backed store via
    /// `setCredential(_:for:)`. Never logged, never persisted anywhere but
    /// the store itself.
    @State private var cloudTokens: [CloudProvider: String] = [:]

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "SANDBOXING", tokens: tokens, icon: "shippingbox")

            profileList(tokens: tokens)

            if let selected = store.profile(id: selectedID) {
                if BuiltInSandboxProfiles.reservedIDs.contains(selected.id) {
                    readOnlySummary(selected, tokens: tokens)
                } else if let draft, draft.id == selected.id {
                    editor(tokens: tokens)
                }
            }

            newProfileRow()
            trustTierDefaults(tokens: tokens)
            cloudSection(tokens: tokens)
            explainerSection(tokens: tokens)
        }
        .onAppear {
            syncDraft()
            syncCloudTokens()
        }
        .onChange(of: selectedID) { _, _ in syncDraft() }
    }

    // MARK: - Profile list

    private func profileList(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(store.all()) { profile in
                let isBuiltIn = BuiltInSandboxProfiles.reservedIDs.contains(profile.id)
                AinkradListRow(
                    isSelected: selectedID == profile.id,
                    onTap: { selectedID = profile.id },
                    leading: {
                        AinkradChip(label: isBuiltIn ? "BUILT-IN" : "USER")
                    },
                    title: profile.name,
                    subtitle: summary(profile),
                    trailing: {
                        if !isBuiltIn {
                            AinkradIconButton(systemName: "trash") { pendingDeleteID = profile.id }
                        }
                    }
                )
            }
        }
        .ainkradConfirmDialog(
            isPresented: Binding(get: { pendingDeleteID != nil }, set: { if !$0 { pendingDeleteID = nil } }),
            title: "Delete sandbox profile",
            message: "This user-defined profile will be removed. This can't be undone.",
            confirmTitle: "Delete",
            isDestructive: true,
            onConfirm: {
                if let id = pendingDeleteID {
                    store.delete(id: id)
                    if selectedID == id { selectedID = BuiltInSandboxProfiles.defaultNonMainID }
                }
                pendingDeleteID = nil
            }
        )
    }

    private func summary(_ p: SandboxProfile) -> String {
        "backend: \(p.backend.rawValue) · fs: r\(p.fsPolicy.readablePaths.count)/w\(p.fsPolicy.writablePaths.count) · " +
        "net: \(networkLabel(p.networkPolicy)) · timeout \(p.resourceLimits.timeoutSeconds)s" +
        (p.allowHostOverride ? " · HOST-OVERRIDE" : "")
    }

    private func networkLabel(_ n: NetworkPolicy) -> String {
        switch n {
        case .off: return "off"
        case .on: return "on"
        case .allowList(let hosts): return "allow(\(hosts.count))"
        }
    }

    private func readOnlySummary(_ p: SandboxProfile, tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Built-in profiles are shipped defaults and can't be edited or deleted.")
                .font(AinkradFont.display(11)).foregroundStyle(tokens.foreground.opacity(0.45))
            AinkradStatRow(label: "Readable paths", value: p.fsPolicy.readablePaths.joined(separator: ", "))
            AinkradStatRow(label: "Writable paths", value: p.fsPolicy.writablePaths.joined(separator: ", "))
            AinkradStatRow(label: "Network", value: networkLabel(p.networkPolicy))
            AinkradStatRow(label: "Timeout", value: "\(p.resourceLimits.timeoutSeconds)s")
        }
        .padding(12)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.3)))
    }

    // MARK: - Editor

    private func syncDraft() {
        guard let selected = store.profile(id: selectedID),
              !BuiltInSandboxProfiles.reservedIDs.contains(selected.id) else {
            draft = nil
            return
        }
        draft = selected
        hostsText = hostsList(from: selected.networkPolicy).joined(separator: ", ")
    }

    private func hostsList(from policy: NetworkPolicy) -> [String] {
        if case .allowList(let hosts) = policy { return hosts }
        return []
    }

    private func editor(tokens: DesignTokens) -> some View {
        guard let bound = Binding($draft) else { return AnyView(EmptyView()) }

        return AnyView(VStack(alignment: .leading, spacing: 10) {
            AinkradTextField(text: bound.name, placeholder: "Profile name")

            AinkradFormRow(title: "Backend") {
                AinkradSegmentedPicker(items: SandboxBackendKind.allCases, selection: bound.backend) { $0.rawValue }
            }

            pathsEditor(title: "Readable paths", paths: bound.fsPolicy.readablePaths)
            pathsEditor(title: "Writable paths", paths: bound.fsPolicy.writablePaths)

            AinkradFormRow(title: "Network") {
                AinkradSegmentedPicker(
                    items: NetworkMode.allCases,
                    selection: Binding(
                        get: { NetworkModeMapping.mode(for: bound.wrappedValue.networkPolicy) },
                        set: { mode in
                            bound.wrappedValue.networkPolicy = NetworkModeMapping.policy(
                                for: mode, hosts: hostsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                        }
                    ),
                    label: { $0.title })
            }
            if NetworkModeMapping.mode(for: bound.wrappedValue.networkPolicy) == .allowList {
                AinkradTextField(
                    text: Binding(
                        get: { hostsText },
                        set: { newValue in
                            hostsText = newValue
                            bound.wrappedValue.networkPolicy = NetworkModeMapping.policy(
                                for: .allowList, hosts: newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                        }),
                    placeholder: "Allowed hosts, comma-separated")
            }

            AinkradFormRow(title: "Timeout", help: "Seconds before a sandboxed run is killed.") {
                AinkradStepper(value: bound.resourceLimits.timeoutSeconds, in: 1...600, step: 5)
            }
            AinkradFormRow(title: "Tool allow-list", help: "Empty defers to the other permission layers.") {
                AinkradMultiSelect(
                    items: Array(Set(SandboxPolicyExplainer.sampleToolNames).union(bound.wrappedValue.toolAllowList)).sorted(),
                    selection: bound.toolAllowList,
                    label: { $0 })
            }

            dangerousHostOverrideToggle(bound: bound, tokens: tokens)

            HStack(spacing: 10) {
                AinkradButton(title: "Save") { store.upsert(bound.wrappedValue); syncDraft() }
                AinkradButton(title: "Discard", style: .ghost) { syncDraft() }
            }
        }
        .padding(12)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.45))))
    }

    private func pathsEditor(title: String, paths: Binding<[String]>) -> some View {
        AinkradFormRow(title: title) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(paths.wrappedValue.indices, id: \.self) { i in
                    HStack(spacing: 6) {
                        AinkradTextField(text: Binding(
                            get: { i < paths.wrappedValue.count ? paths.wrappedValue[i] : "" },
                            set: { if i < paths.wrappedValue.count { paths.wrappedValue[i] = $0 } }
                        ), placeholder: "/path")
                        AinkradIconButton(systemName: "minus.circle") {
                            if i < paths.wrappedValue.count { paths.wrappedValue.remove(at: i) }
                        }
                    }
                }
                AinkradButton(title: "+ Add path", style: .ghost) { paths.wrappedValue.append("") }
            }
        }
    }

    /// `allowHostOverride` — explicit opt-in for a non-main trust tier to
    /// resolve to `.host`. Deliberately its OWN labeled, off-by-default,
    /// danger-styled row (never folded into a generic toggle group) so
    /// turning it on is a visible, intentional act, not an accidental side
    /// effect of editing something else.
    private func dangerousHostOverrideToggle(bound: Binding<SandboxProfile>, tokens: DesignTokens) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Allow host override (dangerous)")
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.accentTertiary)
                Text("Lets a non-main trust tier (background/scheduled/subagent/untrusted-MCP) resolve to unsandboxed host execution. Off by default — leave off unless you understand the escalation risk.")
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.55))
            }
            Spacer(minLength: 12)
            AinkradToggle(isOn: bound.allowHostOverride)
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.accentTertiary.opacity(0.08)))
        .overlay(ChamferShape(cut: AinkradRadius.sm).strokeBorder(tokens.accentTertiary.opacity(0.4), lineWidth: 1))
    }

    private func newProfileRow() -> some View {
        AinkradButton(title: "+ New profile", style: .secondary) {
            let fresh = SandboxProfileFactory.blank()
            store.upsert(fresh)
            selectedID = fresh.id
        }
    }

    // MARK: - Trust-tier defaults

    private func trustTierDefaults(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Trust-tier defaults").font(AinkradFont.display(13, weight: .medium)).foregroundStyle(tokens.foreground.opacity(0.9))
            Text("Main session → Host (trusted). Background / scheduled / subagent / untrusted-MCP → Workspace write (network off).")
                .font(AinkradFont.display(11)).foregroundStyle(tokens.foreground.opacity(0.5))
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.3)))
    }

    // MARK: - Cloud

    private func syncCloudTokens() {
        for provider in CloudProvider.allCases {
            cloudTokens[provider] = environment.cloudCredentialsStore.credential(for: provider) ?? ""
        }
    }

    /// Cloud provider credential entry. Storing a token here only satisfies
    /// `ModalCloudBackend.isAvailable()` — it does NOT enable cloud routing by
    /// itself. Cloud stays opt-in per-Agent (`AgentExecutionPolicy.allowCloud`,
    /// set on an Agent's profile, not here) and, even once opted in, the
    /// remote-execution driver itself still fails closed until Task 15's
    /// research lands (see `ModalCloudBackend`).
    private func cloudSection(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CLOUD").font(AinkradFont.display(12, weight: .semibold)).foregroundStyle(tokens.foreground.opacity(0.6))
            Text("Cloud execution is opt-in per Agent — enable it on an Agent's profile.")
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.foreground.opacity(0.55))

            ForEach(CloudProvider.allCases, id: \.self) { provider in
                AinkradFormRow(title: providerLabel(provider)) {
                    AinkradSecureField(
                        text: Binding(
                            get: { cloudTokens[provider] ?? "" },
                            set: { newValue in
                                cloudTokens[provider] = newValue
                                environment.cloudCredentialsStore.setCredential(
                                    newValue.isEmpty ? nil : newValue, for: provider)
                            }),
                        placeholder: "\(providerLabel(provider)) token")
                }
            }
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.3)))
    }

    private func providerLabel(_ provider: CloudProvider) -> String {
        switch provider {
        case .modal: return "Modal"
        case .daytona: return "Daytona"
        case .singularity: return "Singularity"
        }
    }

    // MARK: - Explainer

    private func explainerSection(tokens: DesignTokens) -> some View {
        let permissionStore = environment.agentPermissionStore
        let profile = store.profile(id: selectedID) ?? BuiltInSandboxProfiles.workspaceWrite
        let explanation = SandboxPolicyExplainer.explain(
            profile: profile, toolName: explainToolName,
            mode: permissionStore.mode, allowlist: permissionStore.allowlist, gateReads: permissionStore.gateReads)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Why blocked / allowed?").font(AinkradFont.display(13, weight: .medium)).foregroundStyle(tokens.foreground.opacity(0.9))
            AinkradSelect(items: SandboxPolicyExplainer.sampleToolNames, selection: $explainToolName, label: { $0 })
            Text(explanation.reason)
                .font(AinkradFont.display(12))
                .foregroundStyle(explanation.effective == .denied ? tokens.accentTertiary : tokens.foreground.opacity(0.7))
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.3)))
    }
}

/// Factory for a brand-new user-defined profile — fail-closed defaults
/// (network off, no fs access granted, `allowHostOverride` false) so a fresh
/// profile never accidentally grants more than the user explicitly adds.
enum SandboxProfileFactory {
    static func blank() -> SandboxProfile {
        SandboxProfile(
            id: UUID().uuidString,
            name: "New profile",
            backend: .seatbelt,
            fsPolicy: FilesystemPolicy(readablePaths: [], writablePaths: []),
            networkPolicy: .off,
            resourceLimits: ResourceLimits(timeoutSeconds: 60),
            toolAllowList: [],
            allowHostOverride: false)
    }
}
