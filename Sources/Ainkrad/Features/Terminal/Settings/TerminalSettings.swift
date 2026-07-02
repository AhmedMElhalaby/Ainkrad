import Foundation

/// Terminal's own settings, persisted through `SettingsStore` under
/// Terminal's key. `nil` fields mean "use the resolution order" — see
/// Terminal App Architecture.md.
struct TerminalSettings: Codable, Equatable {
    static let storeKey = "terminal-settings"

    var defaultShell: String?
    var defaultWorkingDirectory: URL?
}
