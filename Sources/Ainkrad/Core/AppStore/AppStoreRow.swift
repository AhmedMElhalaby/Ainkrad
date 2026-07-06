import Foundation

enum AppStoreRowStatus: Equatable { case available, installed, updateAvailable }
enum AppStoreRowKind: Equatable { case builtIn, plugin }

/// A plain, SILGen-safe projection of one row in the App Store grid.
struct AppStoreRow: Identifiable, Equatable {
    let id: String                  // appID
    let displayName: String
    let icon: String                // SF Symbol
    let description: String
    let catalogVersion: String?     // nil if not in catalog
    let installedVersion: String?   // nil if not installed
    let status: AppStoreRowStatus
    let isEnabled: Bool
    let kind: AppStoreRowKind
    /// True only for plugins the App Store installed (present in the installed
    /// doc) — the ones it can uninstall. Built-ins and dev-sideloaded plugins
    /// (registered but never App Store-installed) are `false`: visible and
    /// toggleable, but not uninstallable via the App Store.
    let isManaged: Bool
    /// From the catalog entry, if any (AIN-148). Used by search.
    let author: String?
}
