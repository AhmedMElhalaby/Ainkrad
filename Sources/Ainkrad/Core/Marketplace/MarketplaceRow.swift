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
}
