import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Cardinal-HUD Settings surface for configured MCP servers: a list of
/// configured servers (health, enable/trust toggles, per-secret fields,
/// discovered tools) plus an "Add server" form for stdio or HTTPS servers.
///
/// Every mutation that can change what's live — enable/disable, add, remove,
/// and saving a secret (which can flip a server out of `.needsConfiguration`)
/// — calls `registry.connectEnabled()` afterward so the change takes effect
/// immediately, per the reconnect hook Task 10 left on the registry. Trust
/// alone never affects connectivity, so it writes straight to the config
/// store with no reconnect.
///
/// Secrets never touch `MCPServerConfig`/the persisted JSON: every secret
/// field writes through `configStore.setSecret(_:for:)` straight to the
/// `SecretStore` (Keychain), keyed by `MCPSecretKey`. Config-add only ever
/// carries secret KEY NAMES (`envKeys`/`headerKeys`); the values are entered
/// afterward, per-key, in the server's own Secrets section.
@MainActor
struct MCPManagerView: View {
    @Environment(AppEnvironment.self) private var environment
    let configStore: MCPServerConfigStore
    let registry: MCPServerRegistry

    @State private var newTransport: MCPTransportKind = .stdio
    @State private var newID = ""
    @State private var newDisplayName = ""
    @State private var newCommand = ""
    @State private var newArgs = ""
    @State private var newURL = ""
    @State private var newEnvKeys = ""
    @State private var newHeaderKeys = ""
    /// In-progress secret VALUE drafts, keyed by `MCPSecretKey.keychainID`.
    /// Never persisted anywhere but `SecretStore` (via explicit Save), and
    /// cleared immediately after a successful save.
    @State private var secretDrafts: [String: String] = [:]
    @State private var pendingRemovalID: String?

    var body: some View {
        let tokens = environment.themeManager.tokens

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                appsSection(tokens: tokens)
                serversSection(tokens: tokens)
                addServerSection(tokens: tokens)
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Grouping

    /// Ainkrad apps hosting their MCP server in-process. `nonisolated` because
    /// it's a pure filter with no view/store access — callable synchronously
    /// from tests without hopping onto the main actor.
    nonisolated static func appConfigs(from configs: [MCPServerConfig]) -> [MCPServerConfig] {
        configs.filter { $0.transport == .inProcess }
    }

    /// Everything else: user-configured stdio commands and HTTPS endpoints.
    nonisolated static func externalConfigs(from configs: [MCPServerConfig]) -> [MCPServerConfig] {
        configs.filter { $0.transport != .inProcess }
    }

    // MARK: - Apps

    /// Ainkrad apps that publish MCP servers. Deliberately NOT editable the way
    /// external servers are: there is no command, URL, or secret to configure,
    /// and the row cannot be deleted — these are synthesized from installed
    /// apps, so the control is enable/disable. Removing the app itself belongs
    /// to the App Store surface, not here.
    private func appsSection(tokens: DesignTokens) -> some View {
        let apps = Self.appConfigs(from: configStore.all())
        return Group {
            if !apps.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsSectionHeader(title: "AINKRAD APPS", tokens: tokens)
                    ForEach(apps) { config in
                        appCard(config, tokens: tokens)
                    }
                }
            }
        }
    }

    /// Same enable/trust/tools contract as `serverCard`, minus the fields that
    /// don't apply to an in-process app server: no command/URL (nothing was
    /// configured), no secrets (nothing to store), no remove button (the row
    /// is synthesized from the installed app, not owned by this store).
    private func appCard(_ config: MCPServerConfig, tokens: DesignTokens) -> some View {
        let tools = registry.discoveredTools().filter { $0.server == config.id }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(config.displayName)
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.9))
                healthBadge(registry.health[config.id])
                Spacer(minLength: 8)
            }

            enabledRow(config)
            trustedRow(config)

            if !tools.isEmpty {
                toolsSection(tools, tokens: tokens)
            }
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.45)))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Servers

    private func serversSection(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "MCP SERVERS", tokens: tokens)

            let externals = Self.externalConfigs(from: configStore.all())
            if externals.isEmpty {
                AinkradEmptyState(
                    icon: "point.3.connected.trianglepath.dotted",
                    title: "No MCP servers configured",
                    message: "Add a stdio command or an HTTPS endpoint below to connect external tools."
                )
            } else {
                ForEach(externals) { config in
                    serverCard(config, tokens: tokens)
                }
            }
        }
    }

    private func serverCard(_ config: MCPServerConfig, tokens: DesignTokens) -> some View {
        let secretKeys = config.transport == .stdio ? config.envKeys : config.headerKeys
        let tools = registry.discoveredTools().filter { $0.server == config.id }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(config.displayName)
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.9))
                healthBadge(registry.health[config.id])
                Spacer(minLength: 8)
                AinkradButton(title: "Remove", style: .danger, icon: "trash") {
                    pendingRemovalID = config.id
                }
            }

            Text(config.transport == .stdio ? (config.command ?? "—") : (config.url?.absoluteString ?? "—"))
                .font(AinkradFont.mono(11))
                .foregroundStyle(tokens.foreground.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.middle)

            enabledRow(config)
            trustedRow(config)

            if !secretKeys.isEmpty {
                secretsSection(config, keys: secretKeys, tokens: tokens)
            }

            if !tools.isEmpty {
                toolsSection(tools, tokens: tokens)
            }
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.45)))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
        .ainkradConfirmDialog(
            isPresented: Binding(
                get: { pendingRemovalID == config.id },
                set: { isPresented in if !isPresented { pendingRemovalID = nil } }
            ),
            title: "Remove \(config.displayName)?",
            message: "This deletes the server's configuration and any secrets stored for it. This can't be undone.",
            confirmTitle: "Remove",
            isDestructive: true,
            onConfirm: {
                configStore.remove(id: config.id)
                Task { await registry.connectEnabled() }
            }
        )
    }

    private func secretsSection(_ config: MCPServerConfig, keys: [String], tokens: DesignTokens) -> some View {
        let missing = Set(configStore.missingSecrets(for: config.id))

        return VStack(alignment: .leading, spacing: 8) {
            Text(config.transport == .stdio ? "ENV SECRETS" : "AUTH HEADERS")
                .font(AinkradFont.mono(9, weight: .medium))
                .kerning(1.5)
                .foregroundStyle(tokens.foreground.opacity(0.4))

            ForEach(keys, id: \.self) { key in
                secretRow(config, key: key, isMissing: missing.contains(key), tokens: tokens)
            }
        }
    }

    private func secretRow(_ config: MCPServerConfig, key: String, isMissing: Bool, tokens: DesignTokens) -> some View {
        let secretKey = MCPSecretKey(serverID: config.id, key: key)

        return HStack(spacing: 10) {
            Text(key)
                .font(AinkradFont.mono(11))
                .foregroundStyle(tokens.foreground.opacity(0.7))
                .frame(width: 130, alignment: .leading)

            NeonSecureField(
                text: Binding(
                    get: { secretDrafts[secretKey.keychainID] ?? "" },
                    set: { secretDrafts[secretKey.keychainID] = $0 }
                ),
                placeholder: isMissing ? "Not set" : "Replace value",
                tokens: tokens
            )

            AinkradBadge(text: isMissing ? "missing" : "set", status: isMissing ? .warning : .success)

            AinkradButton(title: "Save", style: .secondary) {
                let value = secretDrafts[secretKey.keychainID] ?? ""
                guard !value.isEmpty else { return }
                configStore.setSecret(value, for: secretKey)
                secretDrafts[secretKey.keychainID] = ""
                Task { await registry.connectEnabled() }
            }
        }
    }

    private func toolsSection(_ tools: [(server: String, descriptor: MCPToolDescriptor)], tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DISCOVERED TOOLS")
                .font(AinkradFont.mono(9, weight: .medium))
                .kerning(1.5)
                .foregroundStyle(tokens.foreground.opacity(0.4))

            ForEach(tools, id: \.descriptor.name) { entry in
                Text("mcp/\(entry.server)/\(entry.descriptor.name)")
                    .font(AinkradFont.mono(11))
                    .foregroundStyle(tokens.foreground.opacity(0.6))
            }
        }
    }

    /// Shared by `serverCard` and `appCard`: flips the config live via
    /// `configStore.setEnabled` and immediately reconnects, per the contract
    /// documented on the type — an app server and an external server both
    /// need enable/disable to take effect right away.
    private func enabledRow(_ config: MCPServerConfig) -> some View {
        AinkradFormRow(title: "Enabled") {
            AinkradToggle(isOn: Binding(
                get: { config.enabled },
                set: { newValue in
                    configStore.setEnabled(newValue, for: config.id)
                    Task { await registry.connectEnabled() }
                }))
        }
    }

    /// Shared by `serverCard` and `appCard`: trust never affects connectivity
    /// (per the contract documented on the type), so it writes straight to
    /// the config store with no reconnect — for both app and external rows.
    private func trustedRow(_ config: MCPServerConfig) -> some View {
        AinkradFormRow(title: "Trusted", help: "Auto-approve this server's tools") {
            AinkradToggle(isOn: Binding(
                get: { config.trusted },
                set: { configStore.setTrusted($0, for: config.id) }))
        }
    }

    private func healthBadge(_ health: MCPHealth?) -> some View {
        let text: String
        let status: AinkradStatus
        switch health {
        case .connected(let count):
            text = "\(count) tools"; status = .success
        case .needsConfiguration:
            text = "needs config"; status = .warning
        case .failed:
            text = "failed"; status = .danger
        case .disabled, .none:
            text = "off"; status = .neutral
        }
        return AinkradBadge(text: text, status: status)
    }

    // MARK: - Add server

    private func addServerSection(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "ADD SERVER", tokens: tokens)

            VStack(alignment: .leading, spacing: 10) {
                AinkradSegmentedPicker(
                    items: [MCPTransportKind.stdio, .httpSSE],
                    selection: $newTransport,
                    label: { $0 == .stdio ? "Stdio command" : "HTTPS endpoint" }
                )

                HStack(spacing: 10) {
                    AinkradTextField(text: $newID, placeholder: "Server ID (unique)")
                    AinkradTextField(text: $newDisplayName, placeholder: "Display name")
                }

                if newTransport == .stdio {
                    AinkradTextField(text: $newCommand, placeholder: "Command (e.g. npx -y some-mcp-server)")
                    AinkradTextField(text: $newArgs, placeholder: "Args, comma-separated (optional)")
                    AinkradTextField(text: $newEnvKeys, placeholder: "Secret env var names, comma-separated (optional)")
                } else {
                    AinkradTextField(text: $newURL, placeholder: "https://…")
                    AinkradTextField(text: $newHeaderKeys, placeholder: "Secret header names, comma-separated (optional)")
                }

                AinkradButton(title: "Add server", style: .primary, action: addServer)
                    .opacity(canAddServer ? 1 : 0.4)
                    .disabled(!canAddServer)
            }
            .padding(14)
            .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.3)))
        }
    }

    private var canAddServer: Bool {
        let idOK = !newID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && configStore.config(id: newID) == nil
        let nameOK = !newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch newTransport {
        case .stdio:
            return idOK && nameOK && !newCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .httpSSE:
            return idOK && nameOK && URL(string: newURL) != nil
        // In-process rows are synthesized from installed apps; not addable through this form.
        case .inProcess:
            return false
        }
    }

    /// Splits a comma-separated field into trimmed, non-empty entries.
    private func splitList(_ raw: String) -> [String] {
        raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func addServer() {
        guard canAddServer else { return }

        let config = MCPServerConfig(
            id: newID,
            displayName: newDisplayName,
            transport: newTransport,
            command: newTransport == .stdio ? newCommand : nil,
            args: newTransport == .stdio ? splitList(newArgs) : [],
            url: newTransport == .httpSSE ? URL(string: newURL) : nil,
            envKeys: newTransport == .stdio ? splitList(newEnvKeys) : [],
            headerKeys: newTransport == .httpSSE ? splitList(newHeaderKeys) : [],
            enabled: false,
            trusted: false
        )
        configStore.upsert(config)

        newID = ""; newDisplayName = ""; newCommand = ""; newArgs = ""
        newURL = ""; newEnvKeys = ""; newHeaderKeys = ""

        Task { await registry.connectEnabled() }
    }
}
