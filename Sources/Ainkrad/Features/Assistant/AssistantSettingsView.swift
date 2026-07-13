import SwiftUI

/// The Assistant's Settings surface (rendered inside the BUILT-IN APPS
/// section of `SettingsOverlayView`): Connections (API keys), Model
/// (provider/model/effort), and Context privacy (per-source opt-outs).
struct AssistantSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var newPreset: ProviderPreset = ProviderPreset.preset(id: "openai")
    @State private var newBaseURL: String = ProviderPreset.preset(id: "openai").defaultBaseURL
    @State private var newDisplayName: String = ""
    @State private var newConnectionToken = ""
    @State private var revealedConnectionIDs: Set<UUID> = []
    @State private var discoveredModels: [UUID: [String]] = [:]
    @State private var isRefreshingModels = false

    var body: some View {
        let tokens = environment.themeManager.tokens

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                connectionsSection(tokens: tokens)
                modelSection(tokens: tokens)
                permissionsSection(tokens: tokens)
                contextPrivacySection(tokens: tokens)
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
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
    }

    private func addConnectionRow(tokens: DesignTokens) -> some View {
        let preset = newPreset
        return VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(ProviderPreset.all) { p in
                    Button(p.displayName) {
                        newPreset = p
                        newBaseURL = p.defaultBaseURL
                        if newDisplayName.isEmpty { newDisplayName = p.displayName }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(preset.displayName).font(AinkradFont.display(12, weight: .medium))
                    Image(systemName: "chevron.down").font(.system(size: 8))
                }
                .foregroundStyle(tokens.foreground.opacity(0.8))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(tokens.surfaceElevated.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
            }
            .menuStyle(.borderlessButton).fixedSize()

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
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tokens.accentPrimary.opacity(0.1), lineWidth: 1))
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
        let active = activeConnection()

        return VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "MODEL", tokens: tokens)

            if store.connections.isEmpty {
                Text("Add a connection above to choose a model.")
                    .font(AinkradFont.display(11)).foregroundStyle(tokens.foreground.opacity(0.45))
            } else {
                labeled("CONNECTION", tokens: tokens) {
                    NeonSegmentedPicker(
                        items: store.connections.map(\.id),
                        selection: Binding(
                            get: { active?.id ?? store.connections[0].id },
                            set: { id in
                                configStore.setActiveConnectionID(id)
                                if let c = store.connections.first(where: { $0.id == id }) {
                                    configStore.setModel(ProviderPreset.preset(id: c.presetID).curatedModels.first ?? configStore.current.model)
                                }
                            }),
                        label: { id in store.connections.first(where: { $0.id == id })?.displayName ?? "?" },
                        tokens: tokens)
                }
                labeled("MODEL", tokens: tokens) {
                    HStack(spacing: 8) {
                        NeonSegmentedPicker(
                            items: modelOptions(for: active),
                            selection: Binding(get: { configStore.current.model }, set: { configStore.setModel($0) }),
                            label: { $0 }, tokens: tokens)
                        Button { if let c = active { refreshModels(for: c) } } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                                .foregroundStyle(tokens.foreground.opacity(isRefreshingModels ? 0.3 : 0.6))
                        }
                        .buttonStyle(.plain).disabled(isRefreshingModels)
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
        .onAppear { if let c = active { refreshModels(for: c) } }
        .onChange(of: active?.id) { _, _ in if let c = active { refreshModels(for: c) } }
    }

    private func activeConnection() -> Connection? {
        let store = environment.connectionStore
        if let id = environment.agentConfigStore.activeConnectionID,
           let match = store.connections.first(where: { $0.id == id }) { return match }
        return store.connections.first
    }

    private func modelOptions(for connection: Connection?) -> [String] {
        guard let connection else { return [] }
        return discoveredModels[connection.id] ?? ProviderPreset.preset(id: connection.presetID).curatedModels
    }

    private func refreshModels(for connection: Connection) {
        let store = environment.connectionStore
        let svc = environment.modelCatalogService
        let preset = ProviderPreset.preset(id: connection.presetID)
        let key = store.token(for: connection) ?? ""
        isRefreshingModels = true
        Task {
            let result = await svc.modelsResult(kind: connection.kind, baseURL: connection.baseURL,
                                                apiKey: key, curatedFallback: preset.curatedModels)
            discoveredModels[connection.id] = result.models
            isRefreshingModels = false
            if result.isLive {
                reconcileModelIfNeeded(for: connection, availableModels: result.models)
            }
        }
    }

    /// If the active connection's active model isn't valid for it (e.g. still the
    /// Claude default on a freshly-added non-Claude connection), fall back to the
    /// first available model for that connection. Never overrides an explicitly
    /// chosen model that IS in the list. Only called when the model list was
    /// genuinely fetched live — never on a curated fallback from a failed fetch.
    private func reconcileModelIfNeeded(for connection: Connection, availableModels: [String]) {
        let configStore = environment.agentConfigStore
        guard activeConnection()?.id == connection.id else { return }
        guard !availableModels.isEmpty, !availableModels.contains(configStore.current.model) else { return }
        configStore.setModel(availableModels[0])
    }

    // MARK: - Permissions

    private func permissionsSection(tokens: DesignTokens) -> some View {
        let permissionStore = environment.agentPermissionStore

        return VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "PERMISSIONS", tokens: tokens)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ask before reading files")
                        .font(AinkradFont.display(13, weight: .medium))
                        .foregroundStyle(tokens.foreground.opacity(0.9))
                    Text("When on, the assistant asks before reading any file (except in Full-auto).")
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.foreground.opacity(0.5))
                }
                Spacer(minLength: 12)
                NeonToggle(
                    isOn: Binding(
                        get: { permissionStore.gateReads },
                        set: { permissionStore.setGateReads($0) }
                    ),
                    tokens: tokens
                )
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(tokens.surfaceElevated.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
        }
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
        .background(RoundedRectangle(cornerRadius: 10).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
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
