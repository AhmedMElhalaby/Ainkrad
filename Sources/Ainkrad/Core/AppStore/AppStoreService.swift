import Foundation

/// The single entry point the UI (AIN-136) will call: refresh the catalog,
/// install/uninstall, list what's installed, and detect updates.
@MainActor
final class AppStoreService: AppStoreServing {
    let catalog: CatalogService
    private let installer: PluginInstaller
    // Optional (defaulted) so existing call sites that predate the `.skill`
    // catalog kind keep compiling unchanged; `AppEnvironment` wires a real one.
    // A `.skill` install/uninstall with no installer configured fails gracefully
    // via `AppStoreError` rather than crashing.
    private let skillInstaller: SkillInstaller?
    private let persistence: PersistenceStore

    init(catalog: CatalogService, installer: PluginInstaller, persistence: PersistenceStore,
         skillInstaller: SkillInstaller? = nil) {
        self.catalog = catalog
        self.installer = installer
        self.persistence = persistence
        self.skillInstaller = skillInstaller
    }

    var cachedCatalog: [CatalogEntry] { catalog.cached }

    func refreshCatalog() async -> [CatalogEntry] { await catalog.refresh() }

    func install(appID: String) async throws {
        guard let entry = catalog.cached.first(where: { $0.appID == appID }) else {
            throw AppStoreError.notInstalled(appID)   // not in catalog
        }
        switch entry.kind {
        case .plugin:
            try await installer.install(entry)
        case .skill:
            guard let skillInstaller else { throw AppStoreError.invalidBundle("skill installer unavailable") }
            try await skillInstaller.install(entry)
        }
    }

    /// Guarded update: installs the catalog version over the installed one,
    /// only when it is newer. Mirrors `install` but goes through the installer's
    /// version guard.
    func update(appID: String) async throws {
        guard let entry = catalog.cached.first(where: { $0.appID == appID }) else {
            throw AppStoreError.notInstalled(appID)
        }
        switch entry.kind {
        case .plugin:
            try await installer.update(entry)
        case .skill:
            // Skills have no version guard yet — re-installing simply refetches
            // and overwrites (see `SkillInstaller.install`'s idempotency note).
            guard let skillInstaller else { throw AppStoreError.invalidBundle("skill installer unavailable") }
            try await skillInstaller.install(entry)
        }
    }

    func uninstall(appID: String) throws {
        if catalog.cached.first(where: { $0.appID == appID })?.kind == .skill {
            guard let skillInstaller else { throw AppStoreError.invalidBundle("skill installer unavailable") }
            try skillInstaller.uninstall(appID: appID)
        } else {
            try installer.uninstall(appID: appID)
        }
    }

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

    func hasRetainedData(appID: String) -> Bool { installer.hasRetainedData(appID: appID) }
    func restoreRetainedData(appID: String) { installer.restoreRetainedData(appID: appID) }
    func discardRetainedData(appID: String) { installer.discardRetainedData(appID: appID) }
}
