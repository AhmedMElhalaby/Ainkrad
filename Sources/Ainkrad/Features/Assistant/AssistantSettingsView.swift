import SwiftUI

/// The Assistant's Settings surface (rendered inside the BUILT-IN APPS
/// section of `SettingsOverlayView`): Connections (API keys), Model
/// (provider/model/effort), and Context privacy (per-source opt-outs).
struct AssistantSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var newConnectionProvider: ConnectionProvider = .claude
    @State private var newConnectionToken = ""
    @State private var revealedConnectionIDs: Set<UUID> = []

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

        return HStack(spacing: 12) {
            Text(providerTitle(connection.provider))
                .font(AinkradFont.display(12, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.85))
                .frame(width: 70, alignment: .leading)

            Text(isRevealed ? (store.token(for: connection) ?? "") : "••••••••••••")
                .font(AinkradFont.mono(12))
                .foregroundStyle(tokens.foreground.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

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
        VStack(alignment: .leading, spacing: 8) {
            NeonSegmentedPicker(
                items: ConnectionProvider.allCases,
                selection: $newConnectionProvider,
                label: providerTitle,
                tokens: tokens
            )

            HStack(spacing: 10) {
                NeonSecureField(text: $newConnectionToken, placeholder: "API key", tokens: tokens)

                Button {
                    addConnection()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(canAddConnection ? tokens.accentSecondary : tokens.foreground.opacity(0.25))
                }
                .buttonStyle(.plain)
                .disabled(!canAddConnection)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(tokens.surfaceElevated.opacity(0.3)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tokens.accentPrimary.opacity(0.1), lineWidth: 1))
    }

    private var canAddConnection: Bool {
        !newConnectionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addConnection() {
        guard canAddConnection else { return }
        environment.connectionStore.addConnection(
            provider: newConnectionProvider,
            displayName: "\(providerTitle(newConnectionProvider)) Key",
            token: newConnectionToken
        )
        newConnectionToken = ""
    }

    private func providerTitle(_ provider: ConnectionProvider) -> String {
        switch provider {
        case .claude: return "Claude"
        case .openai: return "OpenAI"
        }
    }

    // MARK: - Model

    private func modelSection(tokens: DesignTokens) -> some View {
        let configStore = environment.agentConfigStore

        return VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "MODEL", tokens: tokens)

            labeled("PROVIDER", tokens: tokens) {
                NeonSegmentedPicker(
                    items: AgentProvider.allCases,
                    selection: Binding(
                        get: { configStore.current.provider },
                        set: { configStore.setProvider($0) }
                    ),
                    label: agentProviderTitle,
                    tokens: tokens
                )
            }

            labeled("MODEL", tokens: tokens) {
                NeonSegmentedPicker(
                    items: modelOptions(for: configStore.current.provider),
                    selection: Binding(
                        get: { configStore.current.model },
                        set: { configStore.setModel($0) }
                    ),
                    label: { $0 },
                    tokens: tokens
                )
            }

            labeled("EFFORT", tokens: tokens) {
                NeonSegmentedPicker(
                    items: ["low", "medium", "high", "xhigh"],
                    selection: Binding(
                        get: { configStore.current.effort },
                        set: { configStore.setEffort($0) }
                    ),
                    label: { $0.capitalized },
                    tokens: tokens
                )
            }
        }
    }

    private func modelOptions(for provider: AgentProvider) -> [String] {
        AgentModelCatalog.models(for: provider)
    }

    private func agentProviderTitle(_ provider: AgentProvider) -> String {
        switch provider {
        case .claude: return "Claude"
        case .openai: return "OpenAI"
        }
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
