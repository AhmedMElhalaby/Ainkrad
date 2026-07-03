/// Seam for the Dock icon swap side effect — kept behind a protocol so
/// `ThemeManager` is testable without a real `NSApplication`. The real
/// implementation lives in `AppKitDockIconUpdater` (App layer). Takes a
/// resolved `AppIcon` (not a theme) since the icon is now a decoupled
/// preference — see `AppIconChoice`.
protocol DockIconUpdating {
    @MainActor func updateDockIcon(_ icon: AppIcon)
}
