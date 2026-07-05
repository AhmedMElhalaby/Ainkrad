import Foundation

/// The catalog+install surface the Marketplace UI depends on. `MarketplaceService`
/// conforms; tests use a fake so the store is unit-testable without network/fs.
@MainActor
protocol MarketplaceServing {
    var cachedCatalog: [CatalogEntry] { get }
    func refreshCatalog() async -> [CatalogEntry]
    func install(appID: String) async throws
    func update(appID: String) async throws
    func uninstall(appID: String) throws
    func installedApps() -> [String: InstalledPluginsDocument.Entry]
    func availableUpdates() -> [CatalogEntry]
    func hasRetainedData(appID: String) -> Bool
    func restoreRetainedData(appID: String)
    func discardRetainedData(appID: String)
}
