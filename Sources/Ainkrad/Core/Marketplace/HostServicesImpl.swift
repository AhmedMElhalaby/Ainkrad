import Foundation
import OSLog
import AinkradAppKit

/// The host's `HostServices`, scoped to one app id. `theme` is live (recomputed
/// from the theme manager) so a loaded app follows theme changes.
@MainActor
final class HostServicesImpl: HostServices {
    let documents: PluginDocumentStore
    let secrets: PluginSecretStore
    let log: PluginLogger
    private let themeManager: ThemeManager

    init(appID: String, dataRootURL: URL, secretStore: SecretStore, themeManager: ThemeManager) {
        self.documents = ScopedPluginDocumentStore(directory: dataRootURL.appendingPathComponent(appID, isDirectory: true))
        self.secrets = ScopedPluginSecretStore(appID: appID, backing: secretStore)
        self.log = PluginLoggerImpl(appID: appID)
        self.themeManager = themeManager
    }

    var theme: HostThemeTokens { HostThemeTokens(from: themeManager.tokens) }
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

    private func scoped(_ key: String) -> String { "\(appID).\(key)" }
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
    init(from tokens: DesignTokens) {
        self.init(
            background: tokens.background, surface: tokens.surface,
            surfaceElevated: tokens.surfaceElevated, accentPrimary: tokens.accentPrimary,
            accentSecondary: tokens.accentSecondary, accentTertiary: tokens.accentTertiary,
            foreground: tokens.foreground
        )
    }
}
