import Foundation
import Testing
@testable import Ainkrad
import AinkradAppKit

@Suite("Home adoption")
@MainActor
struct HomeAdoptionTests {
    private func sandbox(_ label: String) -> (base: URL, pointer: URL, cache: URL, vault: URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        return (base,
                base.appendingPathComponent("pointer"),
                base.appendingPathComponent("cache"),
                base.appendingPathComponent("vault"))
    }

    @Test func adoptingRebuildsTheEnvironmentAgainstTheChosenVault() throws {
        let s = sandbox("adopt")
        defer { try? FileManager.default.removeItem(at: s.base) }
        try FileManager.default.createDirectory(at: s.vault, withIntermediateDirectories: true)

        let suite = "com.ainkrad.tests.adopt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var installed: AppEnvironment?
        let result = try HomeAdoption.adoptAndRebuild(
            chosen: s.vault,
            pointerDirectory: s.pointer,
            cacheRoot: s.cache,
            legacyContainer: nil,
            defaults: defaults,
            install: { installed = $0 })

        #expect(result.home.vaultRoot.standardizedFileURL == s.vault.standardizedFileURL)
        #expect(installed != nil)
        // The rebuilt environment must persist into the chosen vault, not anywhere else.
        installed?.themeManager.setFontScale(.large)
        #expect(FileManager.default.fileExists(
            atPath: s.vault.appendingPathComponent("Config/global-settings.json").path))
    }

    @Test func aFailedAdoptionInstallsNothing() throws {
        let s = sandbox("adopt-fail")
        defer { try? FileManager.default.removeItem(at: s.base) }
        try FileManager.default.createDirectory(at: s.vault, withIntermediateDirectories: true)
        // Populated and not a home -> HomeError.notEmpty
        try "x".write(to: s.vault.appendingPathComponent("occupied.txt"),
                      atomically: true, encoding: .utf8)

        let suite = "com.ainkrad.tests.adoptfail.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var installed: AppEnvironment?
        #expect(throws: (any Error).self) {
            _ = try HomeAdoption.adoptAndRebuild(
                chosen: s.vault, pointerDirectory: s.pointer, cacheRoot: s.cache,
                legacyContainer: nil, defaults: defaults, install: { installed = $0 })
        }
        #expect(installed == nil, "a failed adoption must not install a half-built environment")
        #expect(!FileManager.default.fileExists(atPath: s.pointer.appendingPathComponent("home.json").path))
    }
}
