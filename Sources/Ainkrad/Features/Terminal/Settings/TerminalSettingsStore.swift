import Observation
import Foundation
import AinkradAppKit

/// Observable owner of `TerminalSettings`, backed by the app-scoped
/// `HostServices.documents`. Editing persists immediately AND publishes to
/// observers, so the Settings UI and every running Terminal restyle live.
@MainActor
@Observable
final class TerminalSettingsStore {
    private(set) var settings: TerminalSettings
    private let documents: PluginDocumentStore
    private static let key = TerminalSettings.documentID

    init(documents: PluginDocumentStore) {
        self.documents = documents
        if let data = documents.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(TerminalSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = TerminalSettings()
        }
    }

    /// Mutates the settings, publishes to observers, and persists immediately.
    func update(_ mutate: (inout TerminalSettings) -> Void) {
        var updated = settings
        mutate(&updated)
        settings = updated
        if let data = try? JSONEncoder().encode(updated) {
            documents.setData(data, forKey: Self.key)
        }
    }
}
