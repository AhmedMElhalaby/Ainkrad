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
    static func makeRootView() -> AnyView
    static func makeSettingsView() -> AnyView
}
