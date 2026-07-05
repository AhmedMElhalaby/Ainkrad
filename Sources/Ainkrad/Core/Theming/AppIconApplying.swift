/// Seam for the Dock-icon side effect, so `AppIconStore` is testable without a
/// real `NSApplication`. Real impl: `AppKitAppIconApplier` (App layer).
@MainActor protocol AppIconApplying {
    func apply(_ choice: AppIconChoice)
}
