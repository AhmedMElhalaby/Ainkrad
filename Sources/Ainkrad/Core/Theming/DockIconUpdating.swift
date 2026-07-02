/// Seam for the Dock icon swap side effect — kept behind a protocol so
/// `ThemeManager` is testable without a real `NSApplication`. The real
/// implementation lives in `AppKitDockIconUpdater` (App layer).
protocol DockIconUpdating {
    @MainActor func updateDockIcon(for theme: Theme)
}
