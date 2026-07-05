import Foundation
import AinkradAppKit

/// One-time move of Terminal's settings from the host-global document store
/// (pre-decouple) into Terminal's app-scoped `host.documents`. Runs once, gated
/// by a `UserDefaults` flag. Never touches secrets. Refuses to overwrite an
/// existing scoped document.
enum TerminalSettingsMigration {
    static let flagKey = "terminal.settings.migratedToScopedStore"

    static func runIfNeeded(legacy: PersistenceStore, scoped: PluginDocumentStore, defaults: UserDefaults) {
        guard !defaults.bool(forKey: flagKey) else { return }
        defer { defaults.set(true, forKey: flagKey) }
        guard scoped.data(forKey: TerminalSettings.documentID) == nil,
              let existing = legacy.load(TerminalSettings.self),
              let data = try? JSONEncoder().encode(existing) else { return }
        scoped.setData(data, forKey: TerminalSettings.documentID)
    }
}
