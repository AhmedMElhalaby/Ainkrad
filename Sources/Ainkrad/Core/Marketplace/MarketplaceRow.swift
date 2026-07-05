import Foundation

enum MarketplaceRowStatus: Equatable { case available, installed, updateAvailable }
enum MarketplaceRowKind: Equatable { case builtIn, plugin }

/// A plain, SILGen-safe projection of one row in the Marketplace grid.
struct MarketplaceRow: Identifiable, Equatable {
    let id: String                  // appID
    let displayName: String
    let icon: String                // SF Symbol
    let description: String
    let catalogVersion: String?     // nil if not in catalog
    let installedVersion: String?   // nil if not installed
    let status: MarketplaceRowStatus
    let isEnabled: Bool
    let kind: MarketplaceRowKind
    /// True only for plugins the marketplace installed (present in the installed
    /// doc) — the ones it can uninstall. Built-ins and dev-sideloaded plugins
    /// (registered but never marketplace-installed) are `false`: visible and
    /// toggleable, but not uninstallable via the marketplace.
    let isManaged: Bool
}
