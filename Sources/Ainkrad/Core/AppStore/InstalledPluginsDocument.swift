import Foundation
import AinkradHostRuntime

/// What is installed and at which version — the source of truth for update
/// detection and uninstall. (Enabled/disabled state stays in RegistryStateDocument.)
struct InstalledPluginsDocument: PersistableDocument {
    static let documentID = "installed-plugins"
    struct Entry: Codable, Equatable {
        let version: String
        let sourceRepo: String
    }
    var installed: [String: Entry] = [:]      // keyed by appID
}
