import Foundation
import Observation
import OSLog
import AinkradAppKit

/// The host's `HostServices`, scoped to one app id. `theme` is an observable
/// wrapper kept in sync with the theme manager, so a loaded app follows theme
/// changes live.
@MainActor
final class HostServicesImpl: HostServices {
    let documents: PluginDocumentStore
    let secrets: PluginSecretStore
    let log: PluginLogger
    let theme: HostTheme
    let context: PluginContextRegistry
    let actions: AgentActionProvider
    private let themeManager: ThemeManager

    init(appID: String, dataRootURL: URL, secretStore: SecretStore, themeManager: ThemeManager,
         hub: AgentContextRegistryHub, actionHub: AgentActionRegistryHub) {
        self.documents = ScopedPluginDocumentStore(directory: dataRootURL.appendingPathComponent(appID, isDirectory: true))
        self.secrets = ScopedPluginSecretStore(appID: appID, backing: secretStore)
        self.log = PluginLoggerImpl(appID: appID)
        self.themeManager = themeManager
        self.theme = HostTheme(HostThemeTokens(from: themeManager.currentTheme))
        self.context = HostContextRegistry(appID: appID, hub: hub)
        self.actions = HostActionRegistry(appID: appID, hub: actionHub)
        armThemeSync()
    }

    /// Observation fires `onChange` once, just before `currentTheme` changes, so
    /// read the new value on the next main-actor hop and re-arm for the next one.
    private func armThemeSync() {
        withObservationTracking {
            _ = themeManager.currentTheme
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.theme.update(HostThemeTokens(from: self.themeManager.currentTheme))
                self.armThemeSync()
            }
        }
    }
}

/// Key→data storage confined to a single directory. Keys are sanitized so a
/// malicious key cannot escape the app's directory.
final class ScopedPluginDocumentStore: PluginDocumentStore {
    private let directory: URL
    init(directory: URL) { self.directory = directory }

    private func fileURL(_ key: String) -> URL {
        directory.appendingPathComponent(sanitize(key)).appendingPathExtension("bin")
    }

    private func sanitize(_ key: String) -> String {
        key.components(separatedBy: CharacterSet(charactersIn: "/\\")).joined(separator: "_")
            .replacingOccurrences(of: "..", with: "_")
    }

    func data(forKey key: String) -> Data? { try? Data(contentsOf: fileURL(key)) }

    func setData(_ data: Data?, forKey key: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data else { try? FileManager.default.removeItem(at: fileURL(key)); return }
        try? data.write(to: fileURL(key), options: .atomic)
    }
}

/// Secret storage that prefixes every key with the app id, so apps share the
/// host Keychain store without colliding or reading each other's secrets.
final class ScopedPluginSecretStore: PluginSecretStore {
    private let appID: String
    private let backing: SecretStore
    init(appID: String, backing: SecretStore) { self.appID = appID; self.backing = backing }

    // Separator OUTSIDE the appID allowlist ([A-Za-z0-9._-]) so the appID prefix
    // is unambiguous and no two distinct (appID, key) pairs collide.
    private func scoped(_ key: String) -> String { "\(appID)/\(key)" }
    func secret(forKey key: String) -> String? { backing.secret(for: scoped(key)) }
    func setSecret(_ value: String?, forKey key: String) { backing.setSecret(value, for: scoped(key)) }
}

final class PluginLoggerImpl: PluginLogger {
    private let logger: Logger
    init(appID: String) { logger = Logger(subsystem: "com.ainkrad.app.plugin.\(appID)", category: "plugin") }
    func info(_ message: String) { logger.info("\(message, privacy: .public)") }
    func error(_ message: String) { logger.error("\(message, privacy: .public)") }
}

extension HostThemeTokens {
    init(from theme: Theme) {
        let t = theme.tokens
        self.init(
            themeID: theme.rawValue,
            background: t.background, surface: t.surface,
            surfaceElevated: t.surfaceElevated, accentPrimary: t.accentPrimary,
            accentSecondary: t.accentSecondary, accentTertiary: t.accentTertiary,
            foreground: t.foreground
        )
    }
}
