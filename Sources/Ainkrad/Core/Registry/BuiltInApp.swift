import SwiftUI

/// The extension seam every Built-in App conforms to. See
/// WorkShop/Ainkrad/02 Architecture/Built-in App System & Registry.md.
protocol BuiltInApp {
    static var id: String { get }
    static var displayName: String { get }
    /// SF Symbol name. Views must tint this from `DesignTokens`, never a
    /// hardcoded color, so every Built-in App is theme-correct by default.
    static var icon: String { get }
    static var isEnabledByDefault: Bool { get }
    @MainActor static func makeRootView() -> AnyView
    @MainActor static func makeSettingsView() -> AnyView
    /// The app window's own background fill — its color *and* opacity. When
    /// non-nil, the pane header adopts it so the title bar reads as part of the
    /// window (same color, same transparency) rather than a separate HUD strip.
    /// `nil` (the default) keeps the standard HUD surface header. Resolved from
    /// `environment` because a window's color can depend on the app's own
    /// settings and the active theme (e.g. Terminal's scheme + transparency).
    @MainActor static func chromeFill(environment: AppEnvironment) -> Color?
}

extension BuiltInApp {
    @MainActor static func chromeFill(environment: AppEnvironment) -> Color? { nil }
}
