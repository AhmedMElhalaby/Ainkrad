import AppKit

/// A single key + modifier combination — the unit a `ShortcutAction` is bound
/// to. Matching ignores caps-lock and fn, since neither is meaningful for the
/// app's shortcuts. See AIN-144.
struct KeyChord: Codable, Equatable {
    var keyCode: UInt16
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool

    /// The testable core: compares the four modifier flags plus the key code,
    /// with no `NSEvent` dependency.
    func matches(keyCode: UInt16, command: Bool, shift: Bool, option: Bool, control: Bool) -> Bool {
        self.keyCode == keyCode
            && self.command == command
            && self.shift == shift
            && self.option == option
            && self.control == control
    }

    /// Convenience overload for the monitor: reads the event's key code and
    /// modifier flags (ignoring caps-lock/fn) and delegates to the core.
    func matches(event: NSEvent) -> Bool {
        matches(
            keyCode: event.keyCode,
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift),
            option: event.modifierFlags.contains(.option),
            control: event.modifierFlags.contains(.control)
        )
    }

    /// A HUD-style rendering, e.g. "⌘K", "⌘⇧A", "⌥⇥" — modifier glyphs in
    /// ⌘⌥⇧⌃ order followed by the key's label.
    var displayString: String {
        var glyphs = ""
        if command { glyphs += "⌘" }
        if option { glyphs += "⌥" }
        if shift { glyphs += "⇧" }
        if control { glyphs += "⌃" }
        return glyphs + Self.keyLabel(for: keyCode)
    }

    /// macOS virtual key codes (ANSI layout) for the keys this app's
    /// shortcuts use, plus enough of the alphabet/digits/arrows to render any
    /// custom rebinding sensibly.
    private static let keyLabels: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
        38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
        22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        43: ",", 47: ".",
        36: "⏎", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    private static func keyLabel(for keyCode: UInt16) -> String {
        keyLabels[keyCode] ?? "?"
    }
}
