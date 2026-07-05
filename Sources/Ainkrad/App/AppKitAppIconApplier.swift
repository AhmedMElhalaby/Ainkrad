import AppKit

/// Real `AppIconApplying`: sets the running app's Dock icon to the composed
/// `.icns` resolved from the user's color + appearance settings and (for Auto)
/// the current theme, under the current system appearance. Re-applies when the
/// system Light/Dark appearance changes (relevant when Appearance = System).
@MainActor
final class AppKitAppIconApplier: NSObject, AppIconApplying {
    private var choice: AppIconChoice = .auto
    private var appearance: AppIconAppearance = .system
    private var theme: Theme = .neonBlue
    private var observation: NSKeyValueObservation?

    override init() {
        super.init()
        observation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.reapply() }
        }
    }

    func apply(choice: AppIconChoice, appearance: AppIconAppearance, theme: Theme) {
        self.choice = choice
        self.appearance = appearance
        self.theme = theme
        reapply()
    }

    private func reapply() {
        let systemDark = NSApplication.shared.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let name = AppIconResolver.resourceName(for: choice, theme: theme,
                                                appearance: appearance, systemDark: systemDark)
        guard let url = Bundle.main.url(forResource: name, withExtension: "icns"),
              let image = NSImage(contentsOf: url) else { return }
        NSApplication.shared.applicationIconImage = image
    }
}
