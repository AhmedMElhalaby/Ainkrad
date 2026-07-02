import AppKit

/// Real `DockIconUpdating` implementation. Swaps the Dock icon live via
/// `NSApplication.applicationIconImage` — no relaunch, two bundled image
/// assets (`AppIcon-NeonBlue`, `AppIcon-CyberPurple`; Neon Blue is also the
/// static Info.plist default). This is a thin platform side-effect with no
/// branching logic, so it's verified visually in the running app rather
/// than by a unit test — there is nothing here a unit test could assert
/// beyond "the API was called," which `ThemeManagerTests` already covers
/// via the `DockIconUpdating` seam.
struct AppKitDockIconUpdater: DockIconUpdating {
    @MainActor func updateDockIcon(for theme: Theme) {
        switch theme {
        case .neonBlue:
            NSApplication.shared.applicationIconImage = NSImage(named: "AppIcon-NeonBlue")
        case .cyberPurple:
            NSApplication.shared.applicationIconImage = NSImage(named: "AppIcon-CyberPurple")
        }
    }
}
