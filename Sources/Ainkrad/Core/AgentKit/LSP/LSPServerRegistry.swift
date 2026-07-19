// Sources/Ainkrad/Core/AgentKit/LSP/LSPServerRegistry.swift
import Foundation

/// Connection health for one (language, workspace-root) LSP session.
enum LSPHealth: Equatable {
    case connected
    case failed(String)
}

/// Owns the live LSP connections: resolves which configured language server handles a
/// given file (by glob match against `LSPServersDocument`), lazily starts and caches ONE
/// `LSPClient` per (language, workspace-root), and tracks health.
///
/// Advisory, never blocking: a language with no enabled/configured server, or one whose
/// client fails to start, yields `nil` from `client(forFilePath:rootURI:)` — it never
/// throws. One failing server can't break another: each (language, root) is started
/// independently, so a bad "swift" config still leaves "python" working.
@MainActor
final class LSPServerRegistry {
    private var doc: LSPServersDocument
    private let clientFactory: @MainActor @Sendable (LSPServerConfig) -> LSPClient?
    private var clients: [String: LSPClient] = [:]
    private(set) var health: [String: LSPHealth] = [:]

    /// - Parameter clientFactory: builds a real transport-backed client from a config.
    ///   Injectable so tests pass a stub-backed client and never spawn a real language
    ///   server process.
    init(persistence: PersistenceStore,
         clientFactory: @escaping @MainActor @Sendable (LSPServerConfig) -> LSPClient? =
            LSPServerRegistry.defaultClientFactory) {
        self.doc = persistence.load(LSPServersDocument.self) ?? LSPServersDocument()
        self.clientFactory = clientFactory
    }

    /// Builds a real `LSPStdioTransport`-backed client from a config. A config with an
    /// empty command (e.g. autodetection found nothing) yields `nil` rather than
    /// attempting to spawn an empty path.
    static func defaultClientFactory(_ config: LSPServerConfig) -> LSPClient? {
        guard !config.command.isEmpty else { return nil }
        let transport = LSPStdioTransport(command: config.command, args: config.args, env: [:])
        return LSPClient(transport: transport)
    }

    /// The language id of the first enabled config whose `fileGlobs` matches `filePath`,
    /// or `nil` when nothing configured/enabled applies to this file.
    func language(forFilePath filePath: String) -> String? {
        let name = (filePath as NSString).lastPathComponent
        for config in doc.servers where config.enabled {
            if config.fileGlobs.contains(where: { Self.matches(glob: $0, name: name) }) {
                return config.id
            }
        }
        return nil
    }

    /// Lazily starts (or reuses) the one `LSPClient` for the language serving `filePath`,
    /// scoped to `rootURI` — repeated calls for the same (language, root) pair return the
    /// SAME client instance rather than spawning another server. Returns `nil` — never
    /// throws — when no server is configured/enabled for this file, its config has no
    /// resolvable command, or its handshake failed (recorded in `health`; other
    /// (language, root) pairs are unaffected).
    func client(forFilePath filePath: String, rootURI: String) async -> LSPClient? {
        guard let language = language(forFilePath: filePath) else { return nil }
        let key = cacheKey(language: language, rootURI: rootURI)
        if let existing = clients[key] { return existing }
        guard let config = doc.servers.first(where: { $0.id == language && $0.enabled }) else { return nil }
        guard let client = clientFactory(config) else {
            health[key] = .failed("no server available for '\(language)'")
            return nil
        }
        do {
            try await client.initialize(rootURI: rootURI)
            clients[key] = client
            health[key] = .connected
            return client
        } catch {
            health[key] = .failed(String(describing: error))
            return nil
        }
    }

    private func cacheKey(language: String, rootURI: String) -> String {
        "\(language)::\(rootURI)"
    }

    /// Supports the one glob shape every built-in/autodetected config uses: a `*`-prefixed
    /// extension suffix (`*.swift`, `*.tsx`, ...). Anything else is matched as a literal
    /// file name.
    private static func matches(glob: String, name: String) -> Bool {
        if glob.hasPrefix("*") {
            return name.hasSuffix(String(glob.dropFirst()))
        }
        return glob == name
    }

    // MARK: - PATH autodetection

    private nonisolated static let knownServers: [(language: String, binary: String, globs: [String])] = [
        ("swift", "sourcekit-lsp", ["*.swift"]),
        ("typescript", "typescript-language-server", ["*.ts", "*.tsx"]),
        ("go", "gopls", ["*.go"]),
        ("python", "pyright-langserver", ["*.py"]),
        ("rust", "rust-analyzer", ["*.rs"]),
    ]

    /// Probes PATH for each known language server binary, returning an enabled
    /// `LSPServerConfig` for every one found.
    ///
    /// - Parameter which: resolves a binary name to its absolute path on PATH, or `nil`
    ///   if not found. Defaults to a real `/usr/bin/which` lookup, but tests MUST inject a
    ///   fake resolver — this must never spawn a real process or depend on what happens
    ///   to be installed on the machine running the tests.
    nonisolated static func autodetect(which: (String) -> String? = defaultWhich) -> [LSPServerConfig] {
        knownServers.compactMap { entry in
            guard let resolved = which(entry.binary) else { return nil }
            return LSPServerConfig(id: entry.language, command: resolved, args: [],
                                    fileGlobs: entry.globs, enabled: true)
        }
    }

    /// Real PATH lookup via `/usr/bin/which <binary>` — mirrors `DittoUnzipper.entryNames`'s
    /// Process+Pipe pattern. Returns the resolved absolute path, or `nil` if not found or
    /// the lookup itself failed to launch/exit cleanly.
    nonisolated static func defaultWhich(_ binary: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [binary]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}
