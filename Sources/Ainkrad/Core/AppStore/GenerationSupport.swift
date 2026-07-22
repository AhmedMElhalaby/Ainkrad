import AinkradAppKit

/// Single source of truth for the plugin generations this host loads.
/// A plugin's declared `AinkradAPIVersion` must fall in `[minSupported ... current]`.
/// `current` tracks the embedded SDK; `minSupported` advances only when a
/// deprecation window closes (see SDK Generation Contract design).
enum GenerationSupport {
    static let current = AinkradAppKit.apiVersion   // 7
    static let minSupported = 7                     // first resilient-ABI generation
}
