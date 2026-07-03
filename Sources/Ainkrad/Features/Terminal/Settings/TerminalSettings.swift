import Foundation

/// Terminal's own settings, persisted through `SettingsStore` under
/// Terminal's key. `nil` shell/working-directory mean "use the resolution
/// order"; appearance fields default to Match Theme + the default font — see
/// Terminal App Architecture.md. Decoding tolerates payloads written before
/// the appearance fields existed.
struct TerminalSettings: Codable, Equatable {
    static let storeKey = "terminal-settings"

    var defaultShell: String?
    var defaultWorkingDirectory: URL?
    var colorSchemeID: String = TerminalColorScheme.matchThemeID
    var fontFamily: String?
    var fontSize: Double?

    init(
        defaultShell: String? = nil,
        defaultWorkingDirectory: URL? = nil,
        colorSchemeID: String = TerminalColorScheme.matchThemeID,
        fontFamily: String? = nil,
        fontSize: Double? = nil
    ) {
        self.defaultShell = defaultShell
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.colorSchemeID = colorSchemeID
        self.fontFamily = fontFamily
        self.fontSize = fontSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultShell = try container.decodeIfPresent(String.self, forKey: .defaultShell)
        defaultWorkingDirectory = try container.decodeIfPresent(URL.self, forKey: .defaultWorkingDirectory)
        colorSchemeID = try container.decodeIfPresent(String.self, forKey: .colorSchemeID) ?? TerminalColorScheme.matchThemeID
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily)
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize)
    }
}
