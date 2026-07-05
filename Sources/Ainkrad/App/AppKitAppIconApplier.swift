import AppKit

/// Real `AppIconApplying`: sets the running app's Dock icon to the composed
/// `.icns` for the choice under the current appearance, and re-applies when the
/// system Light/Dark appearance changes. Thin platform side-effect (verified
/// visually), so the logic (`AppIconResolver`) is tested, not this.
@MainActor
final class AppKitAppIconApplier: NSObject, AppIconApplying {
    private var current: AppIconChoice = .blue
    private var observation: NSKeyValueObservation?

    override init() {
        super.init()
        // Re-apply on Light/Dark change.
        observation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.reapply() }
        }
    }

    func apply(_ choice: AppIconChoice) { current = choice; reapply() }

    private func reapply() {
        let dark = NSApplication.shared.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let name = AppIconResolver.resourceName(for: current, dark: dark)
        guard let url = Bundle.main.url(forResource: name, withExtension: "icns"),
              let image = NSImage(contentsOf: url) else { return }
        NSApplication.shared.applicationIconImage = image
    }
}
