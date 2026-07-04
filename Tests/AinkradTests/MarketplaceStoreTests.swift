import Testing
import Foundation
import SwiftUI
@testable import Ainkrad

@MainActor
final class FakeMarketplaceService: MarketplaceServing {
    var cachedCatalog: [CatalogEntry] = []
    var installedResult: [String: InstalledPluginsDocument.Entry] = [:]
    var updatesResult: [CatalogEntry] = []
    var installError: MarketplaceError?
    private(set) var installedCalls: [String] = []
    private(set) var uninstalledCalls: [String] = []

    func refreshCatalog() async -> [CatalogEntry] { cachedCatalog }
    func install(appID: String) async throws {
        if let installError { throw installError }
        installedCalls.append(appID)
        let v = cachedCatalog.first { $0.appID == appID }?.version ?? "1.0.0"
        installedResult[appID] = .init(version: v, sourceRepo: "o/\(appID)")
    }
    func update(appID: String) async throws { try await install(appID: appID) }
    func uninstall(appID: String) throws { uninstalledCalls.append(appID); installedResult[appID] = nil }
    func installedApps() -> [String: InstalledPluginsDocument.Entry] { installedResult }
    func availableUpdates() -> [CatalogEntry] { updatesResult }
}

@MainActor
struct MarketplaceStoreTests {
    private func entry(_ id: String, _ v: String = "1.0.0") -> CatalogEntry {
        CatalogEntry(appID: id, displayName: id.capitalized, icon: "app", description: "desc \(id)",
                     version: v, apiVersion: 1, downloadURL: URL(string: "https://e/\(id).zip")!,
                     sha256: "x", sourceRepo: "o/\(id)")
    }
    private func builtIn(_ id: String) -> RegisteredApp {
        RegisteredApp(id: id, displayName: id.capitalized, icon: "terminal", isEnabledByDefault: true,
            source: .builtIn, makeRootView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) }, chromeFill: { nil })
    }
    private func store(service: FakeMarketplaceService, builtIns: [RegisteredApp] = []) -> MarketplaceStore {
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        registry.install(builtIn: builtIns)
        let s = MarketplaceStore(service: service, registry: registry)
        s.reloadRows()
        return s
    }

    @Test("a catalog-only app is .available")
    func availableRow() {
        let svc = FakeMarketplaceService(); svc.cachedCatalog = [entry("notes")]
        let row = store(service: svc).rows.first { $0.id == "notes" }
        #expect(row?.status == .available)
        #expect(row?.kind == .plugin)
    }

    @Test("a built-in is .installed and .builtIn with no catalog version")
    func builtInRow() {
        let svc = FakeMarketplaceService()
        let row = store(service: svc, builtIns: [builtIn("terminal")]).rows.first { $0.id == "terminal" }
        #expect(row?.status == .installed)
        #expect(row?.kind == .builtIn)
    }

    @Test("an installed plugin with a newer catalog version is .updateAvailable")
    func updateRow() {
        let svc = FakeMarketplaceService()
        svc.cachedCatalog = [entry("notes", "2.0.0")]
        svc.installedResult = ["notes": .init(version: "1.0.0", sourceRepo: "o/notes")]
        svc.updatesResult = [entry("notes", "2.0.0")]
        let row = store(service: svc).rows.first { $0.id == "notes" }
        #expect(row?.status == .updateAvailable)
        #expect(row?.installedVersion == "1.0.0")
        #expect(row?.catalogVersion == "2.0.0")
    }

    @Test("filters select the right rows")
    func filters() {
        let svc = FakeMarketplaceService()
        svc.cachedCatalog = [entry("notes"), entry("timer", "2.0.0")]
        svc.installedResult = ["timer": .init(version: "1.0.0", sourceRepo: "o/timer")]
        svc.updatesResult = [entry("timer", "2.0.0")]
        let s = store(service: svc, builtIns: [builtIn("terminal")])
        s.filter = .all;       #expect(Set(s.visibleRows.map(\.id)) == ["notes", "timer", "terminal"])
        s.filter = .installed;  #expect(Set(s.visibleRows.map(\.id)) == ["timer", "terminal"])
        s.filter = .updates;    #expect(s.visibleRows.map(\.id) == ["timer"])
    }

    @Test("empty catalog still lists the built-in under installed")
    func emptyCatalog() {
        let s = store(service: FakeMarketplaceService(), builtIns: [builtIn("terminal")])
        s.filter = .all;       #expect(s.visibleRows.map(\.id) == ["terminal"])
        s.filter = .updates;   #expect(s.visibleRows.isEmpty)
    }
}
