import Foundation

/// The single entry point the UI (AIN-136) will call: refresh the catalog,
/// install/uninstall, list what's installed, and detect updates.
@MainActor
final class MarketplaceService: MarketplaceServing {
    let catalog: CatalogService
    private let installer: PluginInstaller
    private let persistence: PersistenceStore

    init(catalog: CatalogService, installer: PluginInstaller, persistence: PersistenceStore) {
        self.catalog = catalog
        self.installer = installer
        self.persistence = persistence
    }

    var cachedCatalog: [CatalogEntry] { catalog.cached }

    func refreshCatalog() async -> [CatalogEntry] { await catalog.refresh() }

    func install(appID: String) async throws {
        guard let entry = catalog.cached.first(where: { $0.appID == appID }) else {
            throw MarketplaceError.notInstalled(appID)   // not in catalog
        }
        try await installer.install(entry)
    }

    /// Guarded update: installs the catalog version over the installed one,
    /// only when it is newer. Mirrors `install` but goes through the installer's
    /// version guard.
    func update(appID: String) async throws {
        guard let entry = catalog.cached.first(where: { $0.appID == appID }) else {
            throw MarketplaceError.notInstalled(appID)
        }
        try await installer.update(entry)
    }

    func uninstall(appID: String) throws { try installer.uninstall(appID: appID) }

    func installedApps() -> [String: InstalledPluginsDocument.Entry] {
        persistence.load(InstalledPluginsDocument.self)?.installed ?? [:]
    }

    /// Catalog entries whose version is newer than the installed version.
    func availableUpdates() -> [CatalogEntry] {
        let installed = installedApps()
        return catalog.cached.filter { entry in
            guard let cur = installed[entry.appID] else { return false }
            return PluginVersion.isNewer(entry.version, than: cur.version)
        }
    }
}
