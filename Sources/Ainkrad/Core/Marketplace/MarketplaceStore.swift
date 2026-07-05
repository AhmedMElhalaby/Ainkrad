import Foundation
import Observation

/// View-model for the Marketplace overlay. Owns all UI state and derives a flat
/// `[MarketplaceRow]` from the cached catalog + installed-state + the registry.
@MainActor
@Observable
final class MarketplaceStore {
    enum Filter: Equatable { case all, installed, updates }

    var filter: Filter = .all
    private(set) var rows: [MarketplaceRow] = []
    private(set) var busy: Set<String> = []
    private(set) var isRefreshing = false
    var error: MarketplaceError?
    /// Non-nil while a reinstall of this appID awaits the user's Restore/Reset
    /// choice (retained data exists). Drives the overlay's modal.
    private(set) var pendingReinstall: String? = nil

    private let service: MarketplaceServing
    private let registry: BuiltInAppRegistry

    init(service: MarketplaceServing, registry: BuiltInAppRegistry) {
        self.service = service
        self.registry = registry
    }

    var visibleRows: [MarketplaceRow] {
        switch filter {
        case .all: return rows
        case .installed: return rows.filter { $0.status != .available }
        case .updates: return rows.filter { $0.status == .updateAvailable }
        }
    }

    /// Recompute rows from the current cached catalog + installed doc + registry.
    /// No network. Installed rows (built-ins + installed plugins) sort first by
    /// name; available (catalog-only) rows follow, also by name.
    func reloadRows() {
        let catalog = service.cachedCatalog
        let catalogByID = Dictionary(catalog.map { ($0.appID, $0) }, uniquingKeysWith: { a, _ in a })
        let installedDoc = service.installedApps()
        let updates = Set(service.availableUpdates().map(\.appID))
        let registeredByID = Dictionary(registry.allApps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var installedIDs = Set(registry.allApps.map(\.id))
        installedIDs.formUnion(installedDoc.keys)

        var installedRows: [MarketplaceRow] = []
        for id in installedIDs {
            let reg = registeredByID[id]
            let entry = catalogByID[id]
            let isBuiltIn = reg?.source == .builtIn
            installedRows.append(MarketplaceRow(
                id: id,
                displayName: reg?.displayName ?? entry?.displayName ?? id,
                icon: reg?.icon ?? entry?.icon ?? "app",
                description: entry?.description ?? "",
                catalogVersion: entry?.version,
                installedVersion: installedDoc[id]?.version,
                status: updates.contains(id) ? .updateAvailable : .installed,
                isEnabled: registry.isEnabled(id),
                kind: isBuiltIn ? .builtIn : .plugin,
                isManaged: installedDoc[id] != nil))
        }

        var availableRows: [MarketplaceRow] = []
        for entry in catalog where !installedIDs.contains(entry.appID) {
            availableRows.append(MarketplaceRow(
                id: entry.appID, displayName: entry.displayName, icon: entry.icon,
                description: entry.description, catalogVersion: entry.version,
                installedVersion: nil, status: .available, isEnabled: false, kind: .plugin,
                isManaged: false))
        }

        rows = installedRows.sorted { $0.displayName < $1.displayName }
             + availableRows.sorted { $0.displayName < $1.displayName }
    }

    /// Fetch the catalog (offline → cache) then recompute rows.
    func refresh() async {
        isRefreshing = true
        _ = await service.refreshCatalog()
        isRefreshing = false
        reloadRows()
    }

    func install(_ id: String) async {
        if service.hasRetainedData(appID: id) { pendingReinstall = id; return }
        await run(id) { try await self.service.install(appID: id) }
    }

    /// Reinstall keeping the retained settings.
    func restoreAndInstall(_ id: String) async {
        service.restoreRetainedData(appID: id)
        pendingReinstall = nil
        await run(id) { try await self.service.install(appID: id) }
    }

    /// Reinstall discarding the retained settings (fresh defaults).
    func resetAndInstall(_ id: String) async {
        service.discardRetainedData(appID: id)
        pendingReinstall = nil
        await run(id) { try await self.service.install(appID: id) }
    }

    /// Dismiss the reinstall prompt without installing.
    func cancelReinstall() { pendingReinstall = nil }

    func update(_ id: String) async  { await run(id) { try await self.service.update(appID: id) } }

    func uninstall(_ id: String) {
        do { try service.uninstall(appID: id) }
        catch let e as MarketplaceError { error = e }
        catch { self.error = .notInstalled(id) }
        reloadRows()
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        registry.setEnabled(enabled, for: id)
        reloadRows()
    }

    /// Runs an async action for one app id, tracking busy + surfacing errors,
    /// always clearing busy and recomputing rows afterwards.
    private func run(_ id: String, _ op: @escaping () async throws -> Void) async {
        busy.insert(id)
        do { try await op() }
        catch let e as MarketplaceError { error = e }
        catch { self.error = .download(String(describing: error)) }
        busy.remove(id)
        reloadRows()
    }
}
