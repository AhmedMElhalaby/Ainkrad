/// Every UI sound effect Ainkrad can play (AIN-108) — a sci-fi menu-chime
/// family (original synthesized audio; see `scripts/gen-ui-sounds.py`), not
/// any copyrighted sound. This is the ONE place event→asset mapping lives:
/// `resourceName` is the bundled wav's base-name, so swapping the audio for
/// a given event later only ever touches this file.
enum UISound: String, CaseIterable {
    case open
    case close
    case install
    case uninstall
    case toggle
    case confirm
    case error

    /// The bundled wav's base-name (without extension), under
    /// `Resources/Sounds/`.
    var resourceName: String { rawValue }
}
