import SwiftUI

/// The Assistant's Settings surface (rendered inside the BUILT-IN APPS
/// section of `SettingsOverlayView`): Connections (API keys), Model
/// (provider/model/effort), Permissions, Context privacy (per-source opt-outs),
/// and Appearance (surface opacity/blur).
struct AssistantSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var newPreset: ProviderPreset = ProviderPreset.preset(id: "openai")
    @State private var newBaseURL: String = ProviderPreset.preset(id: "openai").defaultBaseURL
    @State private var newDisplayName: String = ""
    @State private var newConnectionToken = ""
    @State private var revealedConnectionIDs: Set<UUID> = []
    @State private var modelPicker = AssistantModelPickerModel()
    @State private var testResults: [UUID: ConnectionTestResult] = [:]
    @State private var testingIDs: Set<UUID> = []
    @State private var hoveredConnectionID: UUID?

    var body: some View {
        let tokens = environment.themeManager.tokens

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                connectionsSection(tokens: tokens)
                modelSection(tokens: tokens)
                permissionsSection(tokens: tokens)
                contextPrivacySection(tokens: tokens)
                appearanceSection(tokens: tokens)
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Connections

    private func connectionsSection(tokens: DesignTokens) -> some View {
        let store = environment.connectionStore

        return VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "CONNECTIONS", tokens: tokens)

            ForEach(store.connections) { connection in
                connectionRow(connection, tokens: tokens)
            }

            addConnectionRow(tokens: tokens)
        }
    }

    private func connectionRow(_ connection: Connection, tokens: DesignTokens) -> some View {
        let store = environment.connectionStore
        let isRevealed = revealedConnectionIDs.contains(connection.id)
        let requiresKey = ProviderPreset.preset(id: connection.presetID).requiresKey

        return HStack(spacing: 12) {
            Text(connection.displayName)
                .font(AinkradFont.display(12, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.85))
                .frame(width: 110, alignment: .leading)

            if requiresKey {
                Text(isRevealed ? (store.token(for: connection) ?? "") : "••••••••••••")
                    .font(AinkradFont.mono(12))
                    .foregroundStyle(tokens.foreground.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(connection.baseURL)
                    .font(AinkradFont.mono(12))
                    .foregroundStyle(tokens.foreground.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            HStack(spacing: 12) {
                if requiresKey {
                    Button {
                        if isRevealed {
                            revealedConnectionIDs.remove(connection.id)
                        } else {
                            revealedConnectionIDs.insert(connection.id)
                        }
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .font(.system(size: 12))
                            .foregroundStyle(tokens.foreground.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                }

                Button { testConnection(connection) } label: {
                    if testingIDs.contains(connection.id) {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "bolt.horizontal")
                            .font(.system(size: 12)).foregroundStyle(tokens.foreground.opacity(0.55))
                    }
                }
                .buttonStyle(.plain).help("Test connection")

                if let result = testResults[connection.id] {
                    Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(result.ok ? tokens.accentSecondary : tokens.accentTertiary)
                        .help(result.message)
                }

                Button {
                    revealedConnectionIDs.remove(connection.id)
                    store.removeConnection(connection)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(tokens.accentTertiary.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
            .opacity(hoveredConnectionID == connection.id ? 1 : 0.35)
            .animation(.easeOut(duration: 0.14), value: hoveredConnectionID)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(tokens.surfaceElevated.opacity(0.45)))
        .onHover { hovering in hoveredConnectionID = hovering ? connection.id : nil }
    }

    private func addConnectionRow(tokens: DesignTokens) -> some View {
        let preset = newPreset
        return VStack(alignment: .leading, spacing: 8) {
            menu(label: preset.displayName, tokens: tokens) {
                ForEach(ProviderPreset.all) { p in
                    Button(p.displayName) {
                        newPreset = p
                        newBaseURL = p.defaultBaseURL
                        if newDisplayName.isEmpty { newDisplayName = p.displayName }
                    }
                }
            }
            .fixedSize()

            if preset.allowsBaseURLEdit {
                NeonSecureField(text: $newBaseURL, placeholder: "Base URL", tokens: tokens)
            }
            HStack(spacing: 10) {
                if preset.requiresKey {
                    NeonSecureField(text: $newConnectionToken, placeholder: "API key", tokens: tokens)
                } else {
                    Text("No API key required")
                        .font(AinkradFont.display(11)).foregroundStyle(tokens.foreground.opacity(0.45))
                }
                Button { addConnection() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(canAddConnection ? tokens.accentSecondary : tokens.foreground.opacity(0.25))
                }
                .buttonStyle(.plain).disabled(!canAddConnection)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(tokens.surfaceElevated.opacity(0.3)))
    }

    private func testConnection(_ connection: Connection) {
        let key = environment.connectionStore.token(for: connection) ?? ""
        let svc = environment.modelCatalogService
        testingIDs.insert(connection.id)
        Task {
            let result = await svc.test(kind: connection.kind, baseURL: connection.baseURL, apiKey: key)
            testResults[connection.id] = result
            testingIDs.remove(connection.id)
        }
    }

    private var canAddConnection: Bool {
        let hasKey = !newConnectionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasURL = !newBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (!newPreset.requiresKey || hasKey) && hasURL
    }

    private func addConnection() {
        guard canAddConnection else { return }
        let name = newDisplayName.isEmpty ? newPreset.displayName : newDisplayName
        environment.connectionStore.addConnection(
            preset: newPreset, displayName: name, baseURL: newBaseURL, token: newConnectionToken)
        newConnectionToken = ""; newDisplayName = ""
    }

    // MARK: - Model

    private func modelSection(tokens: DesignTokens) -> some View {
        let configStore = environment.agentConfigStore
        let store = environment.connectionStore
        let active = modelPicker.activeConnection(environment)

        return VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "MODEL", tokens: tokens)

            if store.connections.isEmpty {
                Text("Add a connection above to choose a model.")
                    .font(AinkradFont.display(11)).foregroundStyle(tokens.foreground.opacity(0.45))
            } else {
                labeled("CONNECTION", tokens: tokens) {
                    menu(label: active?.displayName ?? "Select…", tokens: tokens) {
                        ForEach(store.connections) { connection in
                            Button(connection.displayName) { modelPicker.selectConnection(connection, environment) }
                        }
                    }
                }
                labeled("MODEL", tokens: tokens) {
                    HStack(spacing: 8) {
                        menu(label: configStore.current.model, tokens: tokens) {
                            ForEach(modelPicker.modelOptions(for: active), id: \.self) { m in
                                Button(m) { configStore.setModel(m) }
                            }
                        }
                        Button { if let c = active { modelPicker.refreshModels(for: c, environment) } } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                                .foregroundStyle(tokens.foreground.opacity(modelPicker.isRefreshing ? 0.3 : 0.6))
                        }
                        .buttonStyle(.plain).disabled(modelPicker.isRefreshing)
                    }
                }
                if active?.kind == .claude {
                    labeled("EFFORT", tokens: tokens) {
                        NeonSegmentedPicker(
                            items: ["low", "medium", "high", "xhigh"],
                            selection: Binding(get: { configStore.current.effort }, set: { configStore.setEffort($0) }),
                            label: { $0.capitalized }, tokens: tokens)
                    }
                }
            }
        }
        .onAppear { if let c = active { modelPicker.refreshModels(for: c, environment) } }
        .onChange(of: active?.id) { _, _ in if let c = active { modelPicker.refreshModels(for: c, environment) } }
    }

    /// A borderless neon dropdown label — the deseparatored menu style shared by
    /// the CONNECTION/MODEL rows (no stroke; soft fill only).
    private func menu<Content: View>(label: String, tokens: DesignTokens,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 6) {
                Text(label).font(AinkradFont.display(12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down").font(.system(size: 8))
            }
            .foregroundStyle(tokens.foreground.opacity(0.8))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(tokens.surfaceElevated.opacity(0.45)))
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Permissions

    private func permissionsSection(tokens: DesignTokens) -> some View {
        let permissionStore = environment.agentPermissionStore
        let allowed = permissionStore.allowlist.sorted()

        return VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "PERMISSIONS", tokens: tokens)

            labeled("DEFAULT MODE", tokens: tokens) {
                menu(label: modeTitle(permissionStore.mode), tokens: tokens) {
                    ForEach(AgentPermissionMode.allCases, id: \.self) { mode in
                        Button(modeTitle(mode)) { permissionStore.setMode(mode) }
                    }
                }
            }

            permissionToggleRow(
                title: "Ask before reading files",
                subtitle: "When on, the assistant asks before reading any file (except in Full-auto).",
                isOn: Binding(get: { permissionStore.gateReads }, set: { permissionStore.setGateReads($0) }),
                tokens: tokens)

            labeled("ALWAYS-ALLOWED TOOLS", tokens: tokens) {
                VStack(alignment: .leading, spacing: 8) {
                    if allowed.isEmpty {
                        Text("No tools are always-allowed yet. Use \u{201C}Allow always\u{201D} on an approval to add one.")
                            .font(AinkradFont.display(11)).foregroundStyle(tokens.foreground.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(allowed, id: \.self) { name in
                            HStack(spacing: 10) {
                                Text(toolLabel(name))
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
                            .background(RoundedRectangle(cornerRadius: 9).fill(tokens.surfaceElevated.opacity(0.45)))
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
            NeonToggle(isOn: isOn, tokens: tokens)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(tokens.surfaceElevated.opacity(0.45)))
    }

    private func modeTitle(_ mode: AgentPermissionMode) -> String {
        switch mode {
        case .ask: return "Ask"
        case .autoApprove: return "Auto-approve"
        case .fullAuto: return "Full-auto"
        }
    }

    /// Humanize a stored tool name (e.g. "run_terminal" → "Run terminal").
    private func toolLabel(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: - Context privacy

    private func contextPrivacySection(tokens: DesignTokens) -> some View {
        let settingsStore = environment.agentContextSettingsStore

        return VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "CONTEXT PRIVACY", tokens: tokens)

            Text("Choose what workspace context Assistant may read into its prompts.")
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.foreground.opacity(0.45))

            privacyRow(tokens: tokens, kind: "terminal", title: "Terminal buffers",
                       subtitle: "Recent output from open Terminal Blocks.", store: settingsStore)
            privacyRow(tokens: tokens, kind: "git", title: "Git status",
                       subtitle: "Branch, staged/unstaged changes, and recent commits.", store: settingsStore)
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
            NeonToggle(
                isOn: Binding(
                    get: { store.isEnabled(kind: kind) },
                    set: { store.setEnabled($0, for: kind) }
                ),
                tokens: tokens
            )
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(tokens.surfaceElevated.opacity(0.45)))
    }

    // MARK: - Appearance

    private func appearanceSection(tokens: DesignTokens) -> some View {
        let store = environment.assistantAppearanceStore
        return VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "APPEARANCE", tokens: tokens)

            labeled("SURFACE OPACITY", tokens: tokens) {
                HStack(spacing: 12) {
                    Slider(
                        value: Binding(get: { store.surfaceOpacity }, set: { store.setSurfaceOpacity($0) }),
                        in: 0.3...1.0
                    )
                    .tint(tokens.accentPrimary)
                    Text("\(Int(store.surfaceOpacity * 100))%")
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.foreground.opacity(0.55))
                        .frame(width: 42, alignment: .trailing)
                }
            }
            labeled("BACKGROUND BLUR", tokens: tokens) {
                NeonSegmentedPicker(
                    items: [true, false],
                    selection: Binding(get: { store.blurEnabled }, set: { store.setBlurEnabled($0) }),
                    label: { $0 ? "On" : "Off" }, tokens: tokens)
            }
            Text("Lower opacity (and blur) let the workspace show through the Assistant.")
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.foreground.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func labeled<Content: View>(_ title: String, tokens: DesignTokens,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(AinkradFont.display(10, weight: .medium)).kerning(0.6)
                .foregroundStyle(tokens.foreground.opacity(0.45))
            content()
        }
    }
}
