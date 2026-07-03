import AppKit

/// Real `DockIconUpdating` implementation. Swaps the Dock icon live via
/// `NSApplication.applicationIconImage` — no relaunch, from the bundled image
/// asset named by the resolved `AppIcon` (Neon Blue is also the static
/// Info.plist default). This is a thin platform side-effect with no branching
/// logic, so it's verified visually in the running app rather than by a unit
/// test — there is nothing here a unit test could assert beyond "the API was
/// called," which `ThemeManagerTests` already covers via the `DockIconUpdating`
/// seam.
struct AppKitDockIconUpdater: DockIconUpdating {
    @MainActor func updateDockIcon(_ icon: AppIcon) {
        NSApplication.shared.applicationIconImage = NSImage(named: icon.assetName)
    }
}
