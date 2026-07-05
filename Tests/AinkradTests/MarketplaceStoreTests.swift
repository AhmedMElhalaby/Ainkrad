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
    private func plugin(_ id: String) -> RegisteredApp {
        RegisteredApp(id: id, displayName: id.capitalized, icon: "app", isEnabledByDefault: true,
            source: .plugin(url: URL(fileURLWithPath: "/tmp/\(id).bundle"), apiVersion: 1),
            makeRootView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) }, chromeFill: { nil })
    }
    private func store(service: FakeMarketplaceService, builtIns: [RegisteredApp] = [],
                      loaded: [RegisteredApp] = []) -> MarketplaceStore {
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        registry.install(builtIn: builtIns, loaded: loaded)
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

    @Test("install marks busy then clears, and the row becomes installed")
    func installFlow() async {
        let svc = FakeMarketplaceService(); svc.cachedCatalog = [entry("notes")]
        let s = store(service: svc)
        #expect(s.rows.first { $0.id == "notes" }?.status == .available)
        await s.install("notes")
        #expect(svc.installedCalls == ["notes"])
        #expect(s.busy.isEmpty)
        #expect(s.rows.first { $0.id == "notes" }?.status == .installed)
        #expect(s.error == nil)
    }

    @Test("a failing install surfaces the error and leaves rows unchanged")
    func installError() async {
        let svc = FakeMarketplaceService(); svc.cachedCatalog = [entry("notes")]
        svc.installError = .checksumMismatch
        let s = store(service: svc)
        await s.install("notes")
        #expect(s.error == .checksumMismatch)
        #expect(s.busy.isEmpty)
        #expect(s.rows.first { $0.id == "notes" }?.status == .available)
    }

    @Test("uninstall removes the row")
    func uninstallFlow() {
        let svc = FakeMarketplaceService()
        svc.cachedCatalog = [entry("notes")]
        svc.installedResult = ["notes": .init(version: "1.0.0", sourceRepo: "o/notes")]
        let s = store(service: svc)
        #expect(s.rows.first { $0.id == "notes" }?.status == .installed)
        s.uninstall("notes")
        #expect(svc.uninstalledCalls == ["notes"])
        #expect(s.rows.first { $0.id == "notes" }?.status == .available)   // back to catalog-only
    }

    @Test("a marketplace-installed plugin is managed (uninstallable)")
    func managedPluginRow() {
        let svc = FakeMarketplaceService()
        svc.cachedCatalog = [entry("notes")]
        svc.installedResult = ["notes": .init(version: "1.0.0", sourceRepo: "o/notes")]
        let row = store(service: svc, loaded: [plugin("notes")]).rows.first { $0.id == "notes" }
        #expect(row?.status == .installed)
        #expect(row?.kind == .plugin)
        #expect(row?.isManaged == true)
    }

    @Test("a dev-sideloaded plugin (registered, no installed-doc entry) is NOT managed")
    func devSideloadedPluginRow() {
        // Registered as a plugin, but never marketplace-installed → not in the
        // installed doc. Must be visible + installed, but not uninstallable.
        let svc = FakeMarketplaceService()   // installedApps() == empty
        let row = store(service: svc, loaded: [plugin("hello")]).rows.first { $0.id == "hello" }
        #expect(row?.status == .installed)
        #expect(row?.kind == .plugin)
        #expect(row?.isManaged == false)
    }

    @Test("a built-in is never managed (not uninstallable via marketplace)")
    func builtInNotManaged() {
        let row = store(service: FakeMarketplaceService(), builtIns: [builtIn("terminal")]).rows.first { $0.id == "terminal" }
        #expect(row?.isManaged == false)
    }

    @Test("a catalog-only app is not managed")
    func availableNotManaged() {
        let svc = FakeMarketplaceService(); svc.cachedCatalog = [entry("notes")]
        #expect(store(service: svc).rows.first { $0.id == "notes" }?.isManaged == false)
    }

    @Test("setEnabled flips the registry-backed enabled flag")
    func enableFlow() {
        let svc = FakeMarketplaceService()
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        registry.install(builtIn: [builtIn("terminal")])
        let s = MarketplaceStore(service: svc, registry: registry)
        s.reloadRows()
        #expect(s.rows.first { $0.id == "terminal" }?.isEnabled == true)
        s.setEnabled(false, for: "terminal")
        #expect(s.rows.first { $0.id == "terminal" }?.isEnabled == false)
    }
}
