/// The six app-wide shortcuts a user can rebind (AIN-144). The
/// positional/structural shortcuts (pane focus/resize, workspace cycle,
/// number jumps) are intentionally not represented here — they stay fixed.
enum ShortcutAction: String, Codable, CaseIterable {
    case openLauncher
    case toggleSettings
    case toggleAppStore
    case newWorkspace
    case toggleWorkspaceOverview
    case closeBlock

    var displayName: String {
        switch self {
        case .openLauncher: return "Open Launcher"
        case .toggleSettings: return "Toggle Settings"
        case .toggleAppStore: return "Toggle App Store"
        case .newWorkspace: return "New Workspace"
        case .toggleWorkspaceOverview: return "Toggle Workspace Overview"
        case .closeBlock: return "Close Block"
        }
    }

    /// The factory-default chord — see `KeyboardShortcutMonitor` for the
    /// side effects each action drives.
    var defaultChord: KeyChord {
        switch self {
        case .openLauncher:
            return KeyChord(keyCode: 40, command: true, shift: false, option: false, control: false)   // ⌘K
        case .toggleSettings:
            return KeyChord(keyCode: 43, command: true, shift: false, option: false, control: false)   // ⌘,
        case .toggleAppStore:
            return KeyChord(keyCode: 0, command: true, shift: true, option: false, control: false)     // ⌘⇧A
        case .newWorkspace:
            return KeyChord(keyCode: 45, command: true, shift: true, option: false, control: false)    // ⌘⇧N
        case .toggleWorkspaceOverview:
            return KeyChord(keyCode: 48, command: false, shift: false, option: true, control: false)   // ⌥Tab
        case .closeBlock:
            return KeyChord(keyCode: 13, command: true, shift: false, option: false, control: false)   // ⌘W
        }
    }
}
