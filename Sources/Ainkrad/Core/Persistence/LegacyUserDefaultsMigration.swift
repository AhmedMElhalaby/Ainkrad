import Foundation

/// One-time import of M1's `UserDefaults`-backed settings into the new
/// file-based document store. Runs at bootstrap before the domain stores are
/// constructed; a marker document guarantees it happens exactly once. The
/// legacy `UserDefaults` values are left in place (harmless, and a safety net).
enum LegacyUserDefaultsMigration {
    struct LegacyImportMarker: PersistableDocument {
        static let documentID = "legacy-import-marker"
        var didImport: Bool = false
    }

    static func runIfNeeded(persistence: PersistenceStore, defaults: UserDefaults = .standard) {
        if persistence.load(LegacyImportMarker.self)?.didImport == true { return }

        let decoder = JSONDecoder()  // M1 wrote plain JSON with no date strategy

        if let data = defaults.data(forKey: "global-settings"),
           let value = try? decoder.decode(GlobalSettings.self, from: data) {
            persistence.save(value)
        }
        if let data = defaults.data(forKey: "registry-enabled-state"),
           let value = try? decoder.decode([String: Bool].self, from: data) {
            persistence.save(RegistryStateDocument(enabled: value))
        }
        if let data = defaults.data(forKey: "workspace-layout-v1"),
           let value = try? decoder.decode(LayoutStateSnapshot.self, from: data) {
            persistence.save(value)
        }
        if let data = defaults.data(forKey: "terminal-settings"),
           let value = try? decoder.decode(TerminalSettings.self, from: data) {
            persistence.save(value)
        }

        persistence.save(LegacyImportMarker(didImport: true))
        Log.persistence.info("Imported legacy UserDefaults settings into file documents")
    }
}
