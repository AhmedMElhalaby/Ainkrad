import Foundation

/// Terminal's own settings, persisted through `SettingsStore` under
/// Terminal's key. `nil` shell/working-directory mean "use the resolution
/// order"; appearance fields default to Match Theme + the default font — see
/// Terminal App Architecture.md. Decoding tolerates payloads written before
/// the appearance fields existed.
struct TerminalSettings: PersistableDocument {
    static let documentID = "terminal-settings"

    var defaultShell: String?
    var defaultWorkingDirectory: URL?
    var colorSchemeID: String = TerminalColorScheme.matchThemeID
    var fontFamily: String?
    var fontSize: Double?
    var cursorShape: TerminalCursorShape = .block
    var cursorBlink: Bool = true
    var optionAsMeta: Bool = true
    var scrollbackLines: Int = 1000
    var cursorColor: String?
    var selectionColor: String?
    var backgroundOpacity: Double = 1.0

    init(
        defaultShell: String? = nil,
        defaultWorkingDirectory: URL? = nil,
        colorSchemeID: String = TerminalColorScheme.matchThemeID,
        fontFamily: String? = nil,
        fontSize: Double? = nil,
        cursorShape: TerminalCursorShape = .block,
        cursorBlink: Bool = true,
        optionAsMeta: Bool = true,
        scrollbackLines: Int = 1000,
        cursorColor: String? = nil,
        selectionColor: String? = nil,
        backgroundOpacity: Double = 1.0
    ) {
        self.defaultShell = defaultShell
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.colorSchemeID = colorSchemeID
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.cursorShape = cursorShape
        self.cursorBlink = cursorBlink
        self.optionAsMeta = optionAsMeta
        self.scrollbackLines = scrollbackLines
        self.cursorColor = cursorColor
        self.selectionColor = selectionColor
        self.backgroundOpacity = backgroundOpacity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultShell = try container.decodeIfPresent(String.self, forKey: .defaultShell)
        defaultWorkingDirectory = try container.decodeIfPresent(URL.self, forKey: .defaultWorkingDirectory)
        colorSchemeID = try container.decodeIfPresent(String.self, forKey: .colorSchemeID) ?? TerminalColorScheme.matchThemeID
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily)
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize)
        cursorShape = try container.decodeIfPresent(TerminalCursorShape.self, forKey: .cursorShape) ?? .block
        cursorBlink = try container.decodeIfPresent(Bool.self, forKey: .cursorBlink) ?? true
        optionAsMeta = try container.decodeIfPresent(Bool.self, forKey: .optionAsMeta) ?? true
        scrollbackLines = try container.decodeIfPresent(Int.self, forKey: .scrollbackLines) ?? 1000
        cursorColor = try container.decodeIfPresent(String.self, forKey: .cursorColor)
        selectionColor = try container.decodeIfPresent(String.self, forKey: .selectionColor)
        backgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 1.0
    }
}
