import Foundation
import Observation
import OSLog
import AinkradAppKit

/// The host's `HostServices`, scoped to one app id. `theme` is an observable
/// wrapper kept in sync with the theme manager, so a loaded app follows theme
/// changes live.
@MainActor
public final class HostServicesImpl: HostServices {
    public let documents: PluginDocumentStore
    public let secrets: PluginSecretStore
    public let log: PluginLogger
    public let theme: HostTheme
    public let context: PluginContextRegistry
    public let actions: AgentActionProvider
    public let apps: PluginAppLauncher
    public let presentation: PluginPresentationControl
    private let themeManager: ThemeManager

    public init(appID: String, dataRootURL: URL, secretStore: SecretStore, themeManager: ThemeManager,
         hub: AgentContextRegistryHub, actionHub: AgentActionRegistryHub,
         launchHub: PluginLaunchHub,
         declaredPresentation: PluginPresentation,
         appAppearanceStore: AppAppearanceStore) {
        self.documents = ScopedPluginDocumentStore(directory: dataRootURL.appendingPathComponent(appID, isDirectory: true))
        self.secrets = ScopedPluginSecretStore(appID: appID, backing: secretStore)
        self.log = PluginLoggerImpl(appID: appID)
        self.themeManager = themeManager
        self.theme = HostTheme(HostThemeTokens(from: themeManager.currentTheme))
        self.context = HostContextRegistry(appID: appID, hub: hub)
        self.actions = HostActionRegistry(appID: appID, hub: actionHub)
        self.apps = HostAppLauncher(appID: appID, hub: launchHub)
        self.presentation = HostPresentationControl(
            appID: appID, declaredDefault: declaredPresentation, store: appAppearanceStore)
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

/// Host-side `PluginPresentationControl`: reads/writes the per-appID override in
/// `AppAppearanceStore`, falling back to the bundle's declared default.
@MainActor
public final class HostPresentationControl: PluginPresentationControl {
    private let appID: String
    private let declaredDefault: PluginPresentation
    private let store: AppAppearanceStore
    public init(appID: String, declaredDefault: PluginPresentation, store: AppAppearanceStore) {
        self.appID = appID; self.declaredDefault = declaredDefault; self.store = store
    }
    public var current: PluginPresentation { store.presentationOverride(appID) ?? declaredDefault }
    public func set(_ presentation: PluginPresentation) { store.setPresentationOverride(appID, presentation) }
    public func reset() { store.setPresentationOverride(appID, nil) }
}

/// Key→data storage confined to a single directory. Keys are sanitized so a
/// malicious key cannot escape the app's directory.
public final class ScopedPluginDocumentStore: PluginDocumentStore {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }

    private func fileURL(_ key: String) -> URL {
        directory.appendingPathComponent(sanitize(key)).appendingPathExtension("bin")
    }

    private func sanitize(_ key: String) -> String {
        key.components(separatedBy: CharacterSet(charactersIn: "/\\")).joined(separator: "_")
            .replacingOccurrences(of: "..", with: "_")
    }

    public func data(forKey key: String) -> Data? { try? Data(contentsOf: fileURL(key)) }

    public func setData(_ data: Data?, forKey key: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data else { try? FileManager.default.removeItem(at: fileURL(key)); return }
        try? data.write(to: fileURL(key), options: .atomic)
    }
}

/// Secret storage that prefixes every key with the app id, so apps share the
/// host Keychain store without colliding or reading each other's secrets.
public final class ScopedPluginSecretStore: PluginSecretStore {
    private let appID: String
    private let backing: SecretStore
    public init(appID: String, backing: SecretStore) { self.appID = appID; self.backing = backing }

    // Separator OUTSIDE the appID allowlist ([A-Za-z0-9._-]) so the appID prefix
    // is unambiguous and no two distinct (appID, key) pairs collide.
    private func scoped(_ key: String) -> String { "\(appID)/\(key)" }
    public func secret(forKey key: String) -> String? { backing.secret(for: scoped(key)) }
    public func setSecret(_ value: String?, forKey key: String) { backing.setSecret(value, for: scoped(key)) }
}

public final class PluginLoggerImpl: PluginLogger {
    private let logger: Logger
    public init(appID: String) { logger = Logger(subsystem: "com.ainkrad.app.plugin.\(appID)", category: "plugin") }
    public func info(_ message: String) { logger.info("\(message, privacy: .public)") }
    public func error(_ message: String) { logger.error("\(message, privacy: .public)") }
}

extension HostThemeTokens {
    public init(from theme: Theme) {
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
