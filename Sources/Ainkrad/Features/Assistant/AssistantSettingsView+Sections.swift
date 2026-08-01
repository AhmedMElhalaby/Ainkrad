import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// The "LABEL over control" row idiom shared by the Assistant's settings
/// sections. Previously a private `labeled(_:tokens:)` helper on
/// `AssistantSettingsView`; now a standalone view, because those sections are
/// standalone views themselves.
struct AssistantSettingsLabeled<Content: View>: View {
    private let title: String
    private let tokens: DesignTokens
    private let content: () -> Content

    init(_ title: String, tokens: DesignTokens, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.tokens = tokens
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(AinkradFont.display(10, weight: .medium)).kerning(0.6)
                .foregroundStyle(tokens.foreground.opacity(0.45))
            content()
        }
    }
}

extension AssistantSettingsView {
    // MARK: - Model

    /// Connection + model + reasoning effort. Owns the model picker model that
    /// used to live on `AssistantSettingsView`, so the settings catalog can
    /// instantiate it with no arguments.
    struct ModelSection: View {
        @Environment(AppEnvironment.self) private var environment
        @State private var modelPicker = AssistantModelPickerModel()

        var body: some View {
            let tokens = environment.themeManager.tokens
            let configStore = environment.agentConfigStore
            let store = environment.connectionStore
            let active = modelPicker.activeConnection(environment)

            return AinkradSettingsPanel(title: "Model",
                                       hint: "Which model answers, and how much reasoning effort it spends.") {
                VStack(alignment: .leading, spacing: 12) {
                    if store.connections.isEmpty {
                        AinkradEmptyState(
                            icon: "bolt.horizontal",
                            title: "No connections",
                            message: "Add a connection to choose a model."
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        AinkradCaptionedRow("Connection") {
                            // Keyed on connection `id` (UUID) — `Connection` isn't Hashable
                            // and lives out of task scope. Setter preserves the exact
                            // `selectConnection` write-back (switch + curated-model reset
                            // + refresh). This branch is only reached when connections is
                            // non-empty, so a connection always resolves.
                            AinkradSelect(
                                items: store.connections.map(\.id),
                                selection: Binding(
                                    get: { active?.id ?? store.connections.first?.id ?? UUID() },
                                    set: { id in
                                        if let connection = store.connections.first(where: { $0.id == id }) {
                                            modelPicker.selectConnection(connection, environment)
                                        }
                                    }
                                ),
                                label: { id in store.connections.first(where: { $0.id == id })?.displayName ?? "Select…" }
                            )
                        }
                        AinkradCaptionedRow("Model") {
                            HStack(spacing: 8) {
                                AinkradSelect(
                                    items: modelPicker.modelOptions(for: active, environment),
                                    selection: Binding(get: { configStore.current.model }, set: { configStore.setModel($0) }),
                                    label: { $0 }
                                )
                                Button { if let c = active { modelPicker.refreshModels(for: c, environment, force: true) } } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 11))
                                        .foregroundStyle(tokens.foreground.opacity(modelPicker.isRefreshing ? 0.3 : 0.6))
                                }
                                .buttonStyle(.plain).disabled(modelPicker.isRefreshing)
                            }
                        }
                        if active?.kind == .claude {
                            AinkradCaptionedRow("Effort") {
                                AinkradSegmentedPicker(
                                    items: ["low", "medium", "high", "xhigh"],
                                    selection: Binding(get: { configStore.current.effort }, set: { configStore.setEffort($0) }),
                                    label: { $0.capitalized })
                            }
                        }
                    }
                }
            }
            .onAppear { if let c = active { modelPicker.refreshModels(for: c, environment) } }
            .onChange(of: active?.id) { _, _ in if let c = active { modelPicker.refreshModels(for: c, environment) } }
        }
    }

    // MARK: - Permissions

    /// Default permission mode, the read gate, and the always-allowed tool list.
    /// Stateless beyond the stores it reads, so it constructs with no arguments.
    struct PermissionsSection: View {
        @Environment(AppEnvironment.self) private var environment

        var body: some View {
            let tokens = environment.themeManager.tokens
            let permissionStore = environment.agentPermissionStore
            let allowed = permissionStore.allowlist.sorted()

            return AinkradSettingsPanel(title: "Permissions",
                                       hint: "What the assistant may do without asking.") {
                VStack(alignment: .leading, spacing: 12) {
                    AinkradCaptionedRow("Default mode") {
                        AinkradSelect(
                            items: AgentPermissionMode.allCases,
                            selection: Binding(get: { permissionStore.mode }, set: { permissionStore.setMode($0) }),
                            label: { modeTitle($0) }
                        )
                    }

                    permissionToggleRow(
                        title: "Ask before reading files",
                        subtitle: "When on, the assistant asks before reading any file (except in Full-auto).",
                        isOn: Binding(get: { permissionStore.gateReads }, set: { permissionStore.setGateReads($0) }),
                        tokens: tokens)

                    AssistantSettingsLabeled("Always-allowed tools", tokens: tokens) {
                        VStack(alignment: .leading, spacing: 8) {
                            if allowed.isEmpty {
                                Text("No tools are always-allowed yet. Use \u{201C}Allow always\u{201D} on an approval to add one.")
                                    .font(AinkradFont.display(11)).foregroundStyle(tokens.foreground.opacity(0.45))
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                ForEach(allowed, id: \.self) { name in
                                    HStack(spacing: 10) {
                                        Text(ToolPresentation.humanize(name))
                                            .font(AinkradFont.display(12, weight: .medium))
                                            .foregroundStyle(tokens.foreground.opacity(0.85))
                                        Spacer(minLength: 8)
                                        Button { permissionStore.removeFromAllowlist(name) } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 13))
                                                .foregroundStyle(tokens.accentTertiary.opacity(0.8))
                                        }
                                        .buttonStyle(.plain).help("Remove")
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.45)))
                                }
                                Button { permissionStore.clearAllowlist() } label: {
                                    Text("Clear all")
                                        .font(AinkradFont.display(11, weight: .medium))
                                        .foregroundStyle(tokens.accentTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }

        private func permissionToggleRow(title: String, subtitle: String,
                                         isOn: Binding<Bool>, tokens: DesignTokens) -> some View {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(AinkradFont.display(13, weight: .medium))
                        .foregroundStyle(tokens.foreground.opacity(0.9))
                    Text(subtitle).font(AinkradFont.display(11))
                        .foregroundStyle(tokens.foreground.opacity(0.5))
                }
                Spacer(minLength: 12)
                AinkradToggle(isOn: isOn)
            }
            .padding(14)
            .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.45)))
        }

        private func modeTitle(_ mode: AgentPermissionMode) -> String {
            switch mode {
            case .ask: return "Ask"
            case .autoApprove: return "Auto-approve"
            case .fullAuto: return "Full-auto"
            }
        }
    }

    // MARK: - Context privacy

    /// What workspace context the assistant may read into its prompts.
    struct ContextPrivacySection: View {
        @Environment(AppEnvironment.self) private var environment

        var body: some View {
            let tokens = environment.themeManager.tokens
            let settingsStore = environment.agentContextSettingsStore

            return AinkradSettingsPanel(title: "Context privacy",
                                       hint: "What the assistant is allowed to read from your workspace.") {
                VStack(alignment: .leading, spacing: 12) {
                    privacyRow(tokens: tokens, kind: "terminal", title: "Terminal buffers",
                               subtitle: "Recent output from open Terminal Blocks.", store: settingsStore)
                    privacyRow(tokens: tokens, kind: "git", title: "Git status",
                               subtitle: "Branch, staged/unstaged changes, and recent commits.", store: settingsStore)
                    privacyRow(tokens: tokens, kind: "repo-instructions", title: "Repo instruction files",
                               subtitle: "CLAUDE.md / AGENTS.md found in the working repo.", store: settingsStore)
                }
            }
        }

        private func privacyRow(tokens: DesignTokens, kind: String, title: String, subtitle: String,
                                store: AgentContextSettingsStore) -> some View {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AinkradFont.display(13, weight: .medium))
                        .foregroundStyle(tokens.foreground.opacity(0.9))
                    Text(subtitle)
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.foreground.opacity(0.5))
                }
                Spacer(minLength: 12)
                AinkradToggle(
                    isOn: Binding(
                        get: { store.isEnabled(kind: kind) },
                        set: { store.setEnabled($0, for: kind) }
                    )
                )
            }
            .padding(14)
            .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.45)))
        }
    }

    // MARK: - Appearance

    func appearanceSection(tokens: DesignTokens) -> some View {
        let appearance = environment.appAppearanceStore
        let manager = environment.themeManager
        let appID = AssistantApp.id

        return AinkradSettingsPanel(
            title: "Appearance",
            hint: "Applies to the assistant's messages only. Leave matching Appearance to inherit the app-wide setting."
        ) {
            VStack(alignment: .leading, spacing: 12) {
            // Surface opacity
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Surface opacity")
                        .font(AinkradFont.display(13, weight: .medium))
                        .foregroundStyle(tokens.foreground.opacity(0.9))
                    Text("Lower opacity lets the workspace show through this app.")
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.foreground.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                HStack(spacing: 10) {
                    AinkradSlider(
                        value: Binding(
                            get: { appearance.surfaceOpacity(appID) },
                            set: { appearance.setSurfaceOpacity(appID, $0) }
                        ),
                        in: 0.3...1.0
                    )
                    .frame(width: 130)
                    Text("\(Int(appearance.surfaceOpacity(appID) * 100))%")
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.foreground.opacity(0.55))
                        .frame(width: 42, alignment: .trailing)
                }
            }
            .padding(14)
            .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.45)))

            // Blur
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Blur")
                        .font(AinkradFont.display(13, weight: .medium))
                        .foregroundStyle(tokens.foreground.opacity(0.9))
                    Text("Blur the workspace revealed behind this app when it's translucent.")
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.foreground.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                AinkradToggle(
                    isOn: Binding(
                        get: { appearance.blurEnabled(appID) },
                        set: { appearance.setBlurEnabled(appID, $0) }
                    )
                )
            }
            .padding(14)
            .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.45)))

            // Assistant text: font family + size (assistant-only override; nil = inherit global)
            AinkradCaptionedRow("Text font") {
                AinkradSegmentedPicker(
                    items: UIFontFamily.allCases,
                    selection: Binding(
                        get: { appearance.fontFamily(appID) ?? manager.uiFontFamily },
                        set: { appearance.setFontFamily(appID, $0) }
                    ),
                    label: { fontFamilyTitle($0) })
            }
            AinkradCaptionedRow("Text size") {
                AinkradSegmentedPicker(
                    items: UIFontScale.allCases,
                    selection: Binding(
                        get: { appearance.fontScale(appID) ?? manager.uiFontScale },
                        set: { appearance.setFontScale(appID, $0) }
                    ),
                    label: { fontScaleTitle($0) })
            }
            }
        }
    }

    private func fontFamilyTitle(_ family: UIFontFamily) -> String {
        switch family {
        case .exo2: return "Exo 2"
        case .jetBrainsMono: return "JetBrains Mono"
        case .system: return "System"
        }
    }

    private func fontScaleTitle(_ scale: UIFontScale) -> String {
        switch scale { case .small: return "Small"; case .medium: return "Medium"; case .large: return "Large" }
    }
}
