/// The user's chosen app/Dock icon — a manual preference (NOT theme-driven).
/// Persisted in `GlobalSettings`; applied to the running app's Dock icon.
enum AppIconChoice: String, Codable, CaseIterable {
    case blue
    case purple
}

/// Pure mapping from a choice + current appearance to the bundled composed
/// `.icns` resource base-name. Kept AppKit-free so it is unit-testable.
enum AppIconResolver {
    static func resourceName(for choice: AppIconChoice, dark: Bool) -> String {
        switch (choice, dark) {
        case (.blue, false):   return "blue-light"
        case (.blue, true):    return "blue-dark"
        case (.purple, false): return "purple-light"
        case (.purple, true):  return "purple-dark"
        }
    }
}
