import AinkradAppKit

/// Single source of truth for the plugin generations this host loads.
/// A plugin's declared `AinkradAPIVersion` must fall in `[minSupported ... current]`.
/// `current` tracks the embedded SDK; `minSupported` advances only when a
/// deprecation window closes (see SDK Generation Contract design).
public enum GenerationSupport {
    public static let current = AinkradAppKit.apiVersion
    /// Comes from the SDK rather than being hand-typed here, so the window can
    /// never drift from the generation it is a window onto. It resolves to
    /// `current - 1`: a plugin built for the previous generation still loads,
    /// giving authors one release to rebuild.
    ///
    /// This was `7` — equal to `current` — which meant a generation bump
    /// de-registered every installed plugin the moment it shipped.
    public static let minSupported = AinkradAppKit.minSupportedAPIVersion
}
