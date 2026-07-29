import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Cardinal-HUD Settings surface for configured language servers: a
/// per-language list (command/args/file-globs, enabled toggle, live
/// connection health) plus inline editing and an "Add server" form. Mirrors
/// `MCPManagerView`'s structure/styling exactly — the closest analog — but
/// edits an existing entry's command/args/globs in place (LSP configs have
/// no secrets/trust dimension, unlike MCP's add-once + secrets-only-edit
/// model).
///
/// Every mutation (enable/disable, save an edit, add, remove, "Detect on
/// PATH") writes straight through to `LSPServerRegistry`'s new upsert/
/// toggle/remove API, which invalidates only that language's cached live
/// client(s) — so an edit takes effect on the NEXT file the edited language
/// serves, without disturbing any other language's live session. Clients are
/// lazy per file, so there's no explicit reconnect pass to trigger here.
@MainActor
struct LSPConfigView: View {
    @Environment(AppEnvironment.self) private var environment
    let registry: LSPServerRegistry

    /// In-progress command/args/globs edits, keyed by language id. Only
    /// written on Save (`registry.upsert`) — never persisted from a partial
    /// draft.
    @State private var commandDrafts: [String: String] = [:]
    @State private var argsDrafts: [String: String] = [:]
    @State private var globDrafts: [String: String] = [:]
    @State private var pendingRemovalID: String?

    @State private var newID = ""
    @State private var newCommand = ""
    @State private var newArgs = ""
    @State private var newGlobs = ""

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(alignment: .leading, spacing: 20) {
            serversSection(tokens: tokens)
            addServerSection(tokens: tokens)
        }
    }

    // MARK: - Servers

    private func serversSection(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SettingsSectionHeader(title: "LANGUAGE SERVERS", tokens: tokens)
                Spacer(minLength: 8)
                AinkradButton(title: "Detect on PATH", style: .secondary, icon: "sparkle.magnifyingglass",
                              action: detectOnPath)
            }

            if registry.servers().isEmpty {
                AinkradEmptyState(
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: "No language servers configured",
                    message: "Detect servers already on your PATH, or add one below by its command and file globs."
                )
            } else {
                ForEach(registry.servers()) { config in
                    serverCard(config, tokens: tokens)
                }
            }
        }
    }

    private func serverCard(_ config: LSPServerConfig, tokens: DesignTokens) -> some View {
        let status = healthStatus(for: config.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(config.id)
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.9))
                AinkradBadge(text: status.text, status: status.status)
                Spacer(minLength: 8)
                AinkradButton(title: "Remove", style: .danger, icon: "trash") {
                    pendingRemovalID = config.id
                }
            }

            AinkradFormRow(title: "Enabled") {
                AinkradToggle(isOn: Binding(
                    get: { config.enabled },
                    set: { registry.setEnabled($0, for: config.id) }))
            }

            AinkradTextField(
                text: Binding(
                    get: { commandDrafts[config.id] ?? config.command },
                    set: { commandDrafts[config.id] = $0 }),
                placeholder: "Command (absolute path or PATH-resolvable name)")

            HStack(spacing: 10) {
                AinkradTextField(
                    text: Binding(
                        get: { argsDrafts[config.id] ?? config.args.joined(separator: ", ") },
                        set: { argsDrafts[config.id] = $0 }),
                    placeholder: "Args, comma-separated")
                AinkradTextField(
                    text: Binding(
                        get: { globDrafts[config.id] ?? config.fileGlobs.joined(separator: ", ") },
                        set: { globDrafts[config.id] = $0 }),
                    placeholder: "File globs, e.g. *.swift")
            }

            HStack {
                Spacer(minLength: 0)
                AinkradButton(title: "Save", style: .primary) {
                    saveEdits(for: config)
                }
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
            title: "Remove \(config.id)?",
            message: "This deletes this language server's configuration. This can't be undone.",
            confirmTitle: "Remove",
            isDestructive: true,
            onConfirm: { registry.remove(id: config.id) }
        )
    }

    /// Connection health for `language`, aggregated across every live
    /// (language, workspace-root) session — the config UI has no single
    /// workspace-root context of its own, so a `.connected` session on ANY
    /// root reads as "connected", and a config with no live session yet
    /// (never opened a matching file this launch) reads as "not connected"
    /// rather than a false failure.
    private func healthStatus(for language: String) -> (text: String, status: AinkradStatus) {
        guard let config = registry.config(id: language) else { return ("off", .neutral) }
        guard config.enabled else { return ("off", .neutral) }

        let prefix = "\(language)::"
        let sessions = registry.health.filter { $0.key.hasPrefix(prefix) }
        if sessions.values.contains(where: { $0 == .connected }) {
            return ("connected", .success)
        }
        if sessions.values.contains(where: { if case .failed = $0 { return true }; return false }) {
            return ("failed", .danger)
        }
        return ("not connected yet", .neutral)
    }

    private func saveEdits(for config: LSPServerConfig) {
        let updated = LSPServerConfig(
            id: config.id,
            command: commandDrafts[config.id] ?? config.command,
            args: splitList(argsDrafts[config.id] ?? config.args.joined(separator: ", ")),
            fileGlobs: splitList(globDrafts[config.id] ?? config.fileGlobs.joined(separator: ", ")),
            enabled: config.enabled
        )
        registry.upsert(updated)
        commandDrafts[config.id] = nil
        argsDrafts[config.id] = nil
        globDrafts[config.id] = nil
    }

    /// Probes PATH for every known language server and upserts a config for
    /// each one found — off the main thread (autodetection shells out to
    /// `which` synchronously per server), hopping back to update the registry.
    private func detectOnPath() {
        Task.detached { [registry] in
            let configs = LSPServerRegistry.autodetect()
            await MainActor.run {
                for config in configs { registry.upsert(config) }
            }
        }
    }

    // MARK: - Add server

    private func addServerSection(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "ADD SERVER", tokens: tokens)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    AinkradTextField(text: $newID, placeholder: "Language id (e.g. swift, python)")
                    AinkradTextField(text: $newCommand, placeholder: "Command")
                }
                HStack(spacing: 10) {
                    AinkradTextField(text: $newArgs, placeholder: "Args, comma-separated (optional)")
                    AinkradTextField(text: $newGlobs, placeholder: "File globs, comma-separated (e.g. *.swift)")
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
            && registry.config(id: newID) == nil
        let commandOK = !newCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return idOK && commandOK
    }

    /// Splits a comma-separated field into trimmed, non-empty entries.
    private func splitList(_ raw: String) -> [String] {
        raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func addServer() {
        guard canAddServer else { return }

        let config = LSPServerConfig(
            id: newID,
            command: newCommand,
            args: splitList(newArgs),
            fileGlobs: splitList(newGlobs),
            enabled: true
        )
        registry.upsert(config)

        newID = ""; newCommand = ""; newArgs = ""; newGlobs = ""
    }
}
