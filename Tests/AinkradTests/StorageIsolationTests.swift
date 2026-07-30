import Foundation
import Testing
@testable import Ainkrad
import AinkradHostRuntime

@Suite("Storage isolation")
@MainActor
struct StorageIsolationTests {
    /// Bootstrapping under an injected root must not create or touch anything
    /// in the real Application Support tree. Guards the drift that let the
    /// test suite write into the developer's live data.
    @Test func bootstrapUnderInjectedRootTouchesNothingOutsideIt() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("iso-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        let suiteName = "com.ainkrad.tests.isolation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ainkrad.app"
        let live = support.appendingPathComponent(bundleID, isDirectory: true)
        let watched = ["Shares", "Checkpoints", "Commands", "GeneratedMedia"]
        let before = watched.map { fm.fileExists(atPath: live.appendingPathComponent($0).path) }

        _ = AppEnvironment.bootstrap(rootURL: root, defaults: defaults)

        let after = watched.map { fm.fileExists(atPath: live.appendingPathComponent($0).path) }
        #expect(before == after, "bootstrap created directories outside the injected root")
    }

    @Test func injectedRootReceivesTheSubsystemDirectories() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("iso2-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        let suiteName = "com.ainkrad.tests.isolation2.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        _ = AppEnvironment.bootstrap(rootURL: root, defaults: defaults)

        #expect(fm.fileExists(atPath: root.appendingPathComponent("Checkpoints").path))
    }
}
